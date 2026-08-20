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

version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)"[,]*$/\1/p' package.json | head -n 1)"
[[ -n "$version" ]] || { echo "Could not read package version" >&2; exit 2; }

if [[ ! -d node_modules ]]; then
  pnpm install --frozen-lockfile
fi

export VITE_DBX_OFFLINE_MODE=true
export DBX_OFFLINE_BUILD=true
pnpm tauri build --ci --features offline-uos --bundles deb --config src-tauri/tauri.uos-offline.conf.json

deb_source="$(find target -type f -path '*/bundle/deb/*.deb' -printf '%T@ %p\n' 2>/dev/null | sort -nr | sed -n '1s/^[^ ]* //p')"
if [[ -z "$deb_source" ]]; then
  echo "Tauri completed without producing a .deb under target/**/bundle/deb/" >&2
  exit 1
fi

output_dir="$repo_root/dist/uos-offline"
mkdir -p "$output_dir"
asset="$output_dir/DBX_${version}_uos-offline_${deb_arch}.deb"
cp "$deb_source" "$asset"
sha256sum "$asset" > "$asset.sha256"
cp "$asset.sha256" "$output_dir/SHA256SUMS"

source_commit="$(git rev-parse HEAD)"
upstream_commit="$(git rev-parse upstream/main 2>/dev/null || true)"
printf '%s\n' \
  '{' \
  "  \"product\": \"DBX UOS Offline\"," \
  "  \"version\": \"$version\"," \
  "  \"architecture\": \"$deb_arch\"," \
  "  \"source_commit\": \"$source_commit\"," \
  "  \"upstream_commit\": \"$upstream_commit\"," \
  '  "target_family": "UOS/Debian-like Linux x86_64",' \
  '  "runtime_network_required": false,' \
  '  "public_update_checks": false,' \
  '  "remote_agent_and_mcp_downloads": false,' \
  '  "required_webkit": "WebKitGTK 4.1 (libwebkit2gtk-4.1-0)"' \
  '}' > "$output_dir/manifest.json"

echo "Built offline package: $asset"
echo "SHA256: $(awk '{print $1}' "$asset.sha256")"
