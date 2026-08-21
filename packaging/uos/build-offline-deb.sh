#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

if [[ "$(uname -s)" != "Linux" && "${DBX_ALLOW_NON_LINUX_BUILD:-0}" != "1" ]]; then
  echo "The UOS .deb must be built on Linux x86_64 (or inside the provided Linux builder)." >&2
  exit 2
fi

case "$(uname -m)" in
  x86_64|amd64) deb_arch="amd64" ;;
  *)
    echo "Unsupported build architecture $(uname -m); use an x86_64 Linux builder for UOS/Debian10-like targets." >&2
    exit 2
    ;;
esac

command -v pnpm >/dev/null || { echo "pnpm 10.27.0 is required" >&2; exit 2; }
command -v git >/dev/null || { echo "git is required" >&2; exit 2; }
command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required to build the UOS package" >&2; exit 2; }

version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)"[,]*$/\1/p' package.json | head -n 1)"
[[ -n "$version" ]] || { echo "Could not read package version" >&2; exit 2; }

# Keep this ABI branch's Rust target separate from the WebKitGTK 4.1 branch.
# CI overrides this with its cache-backed target directory; local builds get a
# stable reusable directory without mixing incompatible Linux artifacts.
build_target_dir="${CARGO_TARGET_DIR:-$repo_root/target-uos1070-webkit40}"
export CARGO_TARGET_DIR="$build_target_dir"
export CARGO_INCREMENTAL="${CARGO_INCREMENTAL:-1}"
mkdir -p "$build_target_dir"

echo "Build cache configuration:"
echo "  pnpm_store=$(pnpm store path 2>/dev/null || echo unavailable)"
echo "  cargo_home=${CARGO_HOME:-$HOME/.cargo}"
echo "  cargo_target=$CARGO_TARGET_DIR"
echo "  cargo_incremental=$CARGO_INCREMENTAL"
echo "  rustc_wrapper=${RUSTC_WRAPPER:-none}"
if command -v sccache >/dev/null 2>&1; then
  sccache --show-stats || true
fi

if [[ ! -x node_modules/.bin/tauri ]]; then
  pnpm install --frozen-lockfile --force
elif ! compgen -G 'node_modules/.pnpm/@rolldown+binding-linux-x64-gnu@*/node_modules/@rolldown/binding-linux-x64-gnu/rolldown-binding*.node' >/dev/null; then
  echo "Frontend cache is missing the Linux x64 Rolldown native binding; repairing it with pnpm --force."
  pnpm install --frozen-lockfile --force
fi

export VITE_DBX_OFFLINE_MODE=true
export DBX_OFFLINE_BUILD=true
pnpm tauri build --ci --features offline-uos --bundles deb --config src-tauri/tauri.uos-offline.conf.json

deb_source="$(find "$CARGO_TARGET_DIR" -type f -path '*/bundle/deb/*.deb' -printf '%T@ %p\n' 2>/dev/null | sort -nr | sed -n '1s/^[^ ]* //p')"
if [[ -z "$deb_source" ]]; then
  echo "Tauri completed without producing a .deb under $CARGO_TARGET_DIR/**/bundle/deb/" >&2
  exit 1
fi

output_dir="$repo_root/dist/uos1070-webkit40"
mkdir -p "$output_dir"
asset="$output_dir/DBX_${version}_uos1070-webkit40_${deb_arch}.deb"

# Keep a stable local entrypoint even when a Tauri CLI/config combination uses
# the product name for the Debian binary filename. The offline manual and
# smoke image intentionally depend on /usr/bin/dbx, so normalize the bundle
# before publishing it instead of making every consumer discover a variant.
normalize_deb_entrypoint() {
  local input="$1"
  local output="$2"
  local package_root
  local candidate
  local -a candidates=()

  package_root="$(mktemp -d "${TMPDIR:-/tmp}/dbx-uos-deb.XXXXXX")"
  dpkg-deb --extract "$input" "$package_root"
  mkdir -p "$package_root/DEBIAN"
  dpkg-deb --control "$input" "$package_root/DEBIAN"

  if [[ ! -x "$package_root/usr/bin/dbx" ]]; then
    while IFS= read -r candidate; do
      candidates+=("$candidate")
    done < <(find "$package_root/usr/bin" -maxdepth 1 -type f -perm -u+x -printf '%f\n' 2>/dev/null | sort)

    if [[ "${#candidates[@]}" -ne 1 ]]; then
      echo "Could not identify the single Tauri application binary in the Debian bundle." >&2
      dpkg-deb --contents "$input" >&2
      rm -rf "$package_root"
      return 1
    fi

    ln -s "${candidates[0]}" "$package_root/usr/bin/dbx"
    echo "Normalized offline entrypoint: /usr/bin/dbx -> ${candidates[0]}"
  fi

  (
    cd "$package_root"
    find . -type f ! -path './DEBIAN/*' -print0 |
      sort -z |
      xargs -0 md5sum |
      sed 's#  \./#  #'
  ) > "$package_root/DEBIAN/md5sums"

  # Debian 10's dpkg-deb does not reliably understand the zstd members that
  # newer Ubuntu builders choose by default. gzip keeps the archive readable
  # by Debian 10-like UOS installers.
  dpkg-deb --build --root-owner-group -Zgzip -z9 "$package_root" "$output" >/dev/null
  rm -rf "$package_root"
}

normalize_deb_entrypoint "$deb_source" "$asset"
asset_name="$(basename "$asset")"
(
  cd "$output_dir"
  sha256sum "$asset_name" > "$asset_name.sha256"
)
cp "$asset.sha256" "$output_dir/SHA256SUMS"

source_commit="$(git rev-parse HEAD)"
upstream_commit=""
if git rev-parse --verify upstream/main^{commit} >/dev/null 2>&1; then
  upstream_commit="$(git rev-parse upstream/main)"
fi
if [[ -n "$upstream_commit" ]]; then
  upstream_manifest_line='  "upstream_commit": "'"$upstream_commit"'",'
else
  upstream_manifest_line='  "upstream_commit": null,'
fi
printf '%s\n' \
  '{' \
  "  \"product\": \"DBX UOS Offline\"," \
  "  \"version\": \"$version\"," \
  "  \"architecture\": \"$deb_arch\"," \
  "  \"source_commit\": \"$source_commit\"," \
  "$upstream_manifest_line" \
  '  "target_family": "UOS/Debian-like Linux x86_64",' \
  '  "runtime_network_required": false,' \
  '  "public_update_checks": false,' \
  '  "remote_agent_and_mcp_downloads": false,' \
  '  "required_webkit": "WebKitGTK 4.0 (libwebkit2gtk-4.0-37)",' \
  '  "required_libsoup": "libsoup2.4 (libsoup-2.4.so.1)",' \
  '  "minimum_webkit_api": "2.36"' \
  '}' > "$output_dir/manifest.json"

echo "Built offline package: $asset"
echo "SHA256: $(awk '{print $1}' "$asset.sha256")"
if command -v sccache >/dev/null 2>&1; then
  sccache --show-stats || true
fi
