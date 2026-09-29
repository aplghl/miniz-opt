#!/bin/bash
# harness/sanitize.sh — ASan + UBSan over the differential driver.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/san"
mkdir -p "$OUT"
SAN="-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined -fno-sanitize-recover=all"

echo "candidate under: $SAN"
# shellcheck disable=SC2086
build_cand_driver "$OUT/dump_san" $SAN

mapfile -t files < <(corpus_files_small)
pass=0
for f in "${files[@]}"; do
    # shellcheck disable=SC2086
    ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=print_stacktrace=1 \
        MALLOC_PERTURB_=85 "$OUT/dump_san" "$f" >/dev/null 2>"$OUT/err.txt" || {
        echo "SANITIZER FAILURE on $f"; cat "$OUT/err.txt"; exit 1; }
    if [ -s "$OUT/err.txt" ]; then
        echo "sanitizer diagnostics on $f:"; cat "$OUT/err.txt"; exit 1
    fi
    pass=$((pass + 1))
done
echo "sanitize: $pass files clean (ASan+UBSan)"
