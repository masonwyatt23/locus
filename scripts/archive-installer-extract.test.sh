#!/usr/bin/env bash
# Exercise malformed release archives without network access or a real home.
set -euo pipefail

installer=$(cd "$(dirname "$0")" && pwd)/install.sh
root=$(mktemp -d "${TMPDIR:-/tmp}/locus-invalid-archive.XXXXXX")
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/home" "$root/tools" "$root/tmp"
printf 'not a gzip archive\n' > "$root/archive.tar.gz"
if command -v sha256sum >/dev/null 2>&1; then
  digest=$(sha256sum "$root/archive.tar.gz")
else
  digest=$(shasum -a 256 "$root/archive.tar.gz")
fi
printf '%s  locus-x86_64-unknown-linux-gnu.tar.gz\n' "${digest%% *}" > "$root/checksum"

cat > "$root/tools/uname" <<'EOF'
#!/usr/bin/env bash
case "$1" in -s) printf 'Linux\n';; -m) printf 'x86_64\n';; *) exit 1;; esac
EOF
cat > "$root/tools/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out='' url=''
while (($#)); do
  case "$1" in
    --output) out=$2; shift 2;;
    https://*) url=$1; shift;;
    *) shift;;
  esac
done
case "$url" in
  *.sha256) cp "$FIXTURE_ROOT/checksum" "$out";;
  *.tar.gz) cp "$FIXTURE_ROOT/archive.tar.gz" "$out";;
  *) exit 1;;
esac
EOF
chmod +x "$root/tools/uname" "$root/tools/curl"

if HOME="$root/home" TMPDIR="$root/tmp" PATH="$root/tools:$PATH" FIXTURE_ROOT="$root" \
  bash "$installer" --version v1.2.3 --bin-dir "$root/bin" > "$root/stdout" 2> "$root/stderr"; then
  printf 'FAIL: malformed archive was accepted\n' >&2
  exit 1
fi
if ! grep -q 'archive must contain locus and locus-mcp' "$root/stderr"; then
  printf 'FAIL: installer did not reject the archive during inspection\n' >&2
  exit 1
fi
for binary in locus locus-mcp; do
  if [[ -e "$root/bin/$binary" || -L "$root/bin/$binary" ]]; then
    printf 'FAIL: %s was installed from a malformed archive\n' "$binary" >&2
    exit 1
  fi
done
if [[ -n $(ls -A "$root/tmp") ]]; then
  printf 'FAIL: installer left temporary files behind\n' >&2
  exit 1
fi
printf 'PASS: malformed archive rejected without installing binaries\n'
