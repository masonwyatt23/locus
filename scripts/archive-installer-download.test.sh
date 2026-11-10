#!/usr/bin/env bash
# Offline regression: a failed, partially written archive must not install anything.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
case_dir=$(mktemp -d "${TMPDIR:-/tmp}/locus-download-test.XXXXXX")
trap 'rm -rf -- "$case_dir"' EXIT
mkdir -p "$case_dir/tools" "$case_dir/home" "$case_dir/tmp"

cat > "$case_dir/tools/uname" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    -s) printf 'Linux\n' ;;
    -m) printf 'x86_64\n' ;;
    *) exit 1 ;;
esac
MOCK
cat > "$case_dir/tools/curl" <<'MOCK'
#!/usr/bin/env bash
out= url=
while (($#)); do
    case "$1" in
        --output) out=$2; shift 2 ;;
        --proto|--proto-redir|--connect-timeout|--max-time|--retry) shift 2 ;;
        https://*) url=$1; shift ;;
        *) shift ;;
    esac
done
printf '%s\n' "$url" >> "$DOWNLOAD_LOG"
[[ $url == https://github.com/ashlrai/locus/releases/download/v1.2.3/locus-x86_64-unknown-linux-gnu.tar.gz ]] || exit 2
printf 'partial archive' > "$out"
exit 22
MOCK
chmod +x "$case_dir/tools/uname" "$case_dir/tools/curl"

status=0
DOWNLOAD_LOG="$case_dir/downloads" HOME="$case_dir/home" TMPDIR="$case_dir/tmp" \
    PATH="$case_dir/tools:$PATH" bash "$root/scripts/install.sh" \
    --version v1.2.3 --bin-dir "$case_dir/bin" \
    > "$case_dir/stdout" 2> "$case_dir/stderr" || status=$?
[[ $status -ne 0 ]] || { printf 'FAIL: download failure succeeded\n' >&2; exit 1; }
grep -Fq 'archive download failed; nothing installed' "$case_dir/stderr" \
    || { printf 'FAIL: missing download error\n' >&2; exit 1; }
[[ ! -e $case_dir/bin ]] || { printf 'FAIL: install destination created\n' >&2; exit 1; }
[[ $(wc -l < "$case_dir/downloads") -eq 1 ]] \
    || { printf 'FAIL: unexpected further download\n' >&2; exit 1; }
[[ -z $(ls -A "$case_dir/tmp") ]] \
    || { printf 'FAIL: partial download not cleaned up\n' >&2; exit 1; }
printf 'ok - failed archive download leaves no installed binaries\n'
