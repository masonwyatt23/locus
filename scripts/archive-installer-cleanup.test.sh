#!/usr/bin/env bash
# Offline regression: an extraction failure removes only the installer's work directory.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/locus-cleanup-test.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT

target=x86_64-unknown-linux-gnu
asset="locus-$target.tar.gz"
real_tar=$(command -v tar)
mkdir -p "$fixture/package/locus-$target" "$fixture/tools" "$fixture/tmp space/unrelated" "$fixture/bin" "$fixture/home"
printf 'new locus\n' > "$fixture/package/locus-$target/locus"
printf 'new mcp\n' > "$fixture/package/locus-$target/locus-mcp"
"$real_tar" -czf "$fixture/$asset" -C "$fixture/package" "locus-$target"
if command -v sha256sum >/dev/null 2>&1; then
  digest=$(sha256sum "$fixture/$asset")
else
  digest=$(shasum -a 256 "$fixture/$asset")
fi
printf '%s  %s\n' "${digest%% *}" "$asset" > "$fixture/$asset.sha256"
printf 'keep temp sibling\n' > "$fixture/tmp space/unrelated/sentinel"
printf 'keep existing binary\n' > "$fixture/bin/locus"
printf 'keep existing mcp\n' > "$fixture/bin/locus-mcp"

cat > "$fixture/tools/uname" <<'STUB'
#!/bin/bash
case "$1" in -s) echo Linux ;; -m) echo x86_64 ;; *) exit 1 ;; esac
STUB
cat > "$fixture/tools/curl" <<'STUB'
#!/bin/bash
out= url=
while (($#)); do
  case "$1" in
    --output) out=$2; shift 2 ;;
    --proto|--proto-redir|--connect-timeout|--max-time|--retry) shift 2 ;;
    https://*) url=$1; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  */"$TEST_ASSET"|*/"$TEST_ASSET.sha256") cp "$TEST_FIXTURE/${url##*/}" "$out" ;;
  *) exit 1 ;;
esac
STUB
cat > "$fixture/tools/tar" <<'STUB'
#!/bin/bash
if [[ $1 == -xOzf && $3 == */locus-mcp ]]; then
  printf '%s\n' "${2%/*}" > "$TEST_FIXTURE/extraction-work-dir"
  printf 'partial output\n'
  exit 42
fi
exec "$TEST_REAL_TAR" "$@"
STUB
chmod +x "$fixture/tools/uname" "$fixture/tools/curl" "$fixture/tools/tar"

if TEST_FIXTURE="$fixture" TEST_ASSET="$asset" TEST_REAL_TAR="$real_tar" \
  TMPDIR="$fixture/tmp space" HOME="$fixture/home" PATH="$fixture/tools:$PATH" \
  bash "$root/scripts/install.sh" --version v1.2.3 --bin-dir "$fixture/bin" \
  > "$fixture/stdout" 2> "$fixture/stderr"; then
  printf 'FAIL: installer succeeded despite extraction failure\n' >&2; exit 1
fi
[[ -f "$fixture/extraction-work-dir" ]] || { echo 'FAIL: extraction failure was not reached' >&2; exit 1; }
work_dir=$(cat "$fixture/extraction-work-dir")
[[ $work_dir == "$fixture/tmp space"/locus-install.* && ! -e $work_dir ]] \
  || { echo 'FAIL: installer work directory was not removed' >&2; exit 1; }
[[ $(cat "$fixture/tmp space/unrelated/sentinel") == 'keep temp sibling' ]] \
  || { echo 'FAIL: unrelated temporary file changed' >&2; exit 1; }
[[ $(cat "$fixture/bin/locus") == 'keep existing binary' && $(cat "$fixture/bin/locus-mcp") == 'keep existing mcp' ]] \
  || { echo 'FAIL: existing installation changed' >&2; exit 1; }
[[ $(ls -A "$fixture/tmp space") == unrelated && $(ls -A "$fixture/bin" | wc -l | tr -d ' ') == 2 ]] \
  || { echo 'FAIL: unexpected temporary or installation files remain' >&2; exit 1; }
grep -q 'could not unpack locus-mcp' "$fixture/stderr" \
  || { echo 'FAIL: expected extraction diagnostic' >&2; exit 1; }
printf 'ok - extraction failure cleans its work directory and preserves unrelated files\n'
