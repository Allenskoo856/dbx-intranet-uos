#!/usr/bin/env bash
set -euo pipefail

deb_path="${1:-}"
if [[ -z "$deb_path" || ! -f "$deb_path" ]]; then
  echo "Usage: $0 /path/to/DBX_*.deb" >&2
  exit 2
fi

command -v dpkg-deb >/dev/null || { echo "dpkg-deb is required" >&2; exit 2; }
command -v sha256sum >/dev/null || { echo "sha256sum is required" >&2; exit 2; }

if [[ -f "$deb_path.sha256" ]]; then
  (cd "$(dirname "$deb_path")" && sha256sum -c "$(basename "$deb_path.sha256")")
fi

package_info="$(dpkg-deb --info "$deb_path")"
printf '%s\n' "$package_info"
printf '%s\n' "$package_info" | rg -q 'Architecture: amd64' || {
  echo "The offline UOS package must be amd64/x86_64." >&2
  exit 1
}
printf '%s\n' "$package_info" | rg -q 'libwebkit2gtk-4\.1-0' || {
  echo "The package does not declare the WebKitGTK 4.1 runtime dependency." >&2
  exit 1
}

contents="$(dpkg-deb --contents "$deb_path")"
printf '%s\n' "$contents" | rg -q '/usr/bin/dbx([[:space:]]|$)' || {
  echo "The package does not contain /usr/bin/dbx." >&2
  exit 1
}

extract_dir="$(mktemp -d "${TMPDIR:-/tmp}/dbx-uos-verify.XXXXXX")"
dpkg-deb --extract "$deb_path" "$extract_dir"
self_test="$extract_dir/usr/bin/dbx"
[[ -x "$self_test" ]] || { echo "Extracted DBX executable is missing" >&2; exit 1; }

self_test_output="$($self_test --dbx-offline-self-test)"
printf '%s\n' "$self_test_output"
for marker in network_policy=deny-public updater=disabled agent_remote_downloads=disabled mcp_registry_checks=disabled; do
  printf '%s\n' "$self_test_output" | rg -q "$marker" || {
    echo "Missing offline self-test marker: $marker" >&2
    exit 1
  }
done

echo "Offline .deb metadata and runtime self-test passed."
