#!/bin/bash
# harness/diff_lib.sh — byte-exact differential of a prebuilt archive vs oracle.
#   usage: harness/diff_lib.sh <archive> [include_dir]
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

ARCHIVE=${1:?usage: diff_lib.sh <archive> [include_dir]}
INCDIR=${2:-"$ROOT/src"}
OUT="$ROOT/build/difflib"
mkdir -p "$OUT"

build_oracle_driver "$OUT/dump_oracle"
# shellcheck disable=SC2086
$CC ${CAND_FLAGS:-} -I "$INCDIR" "$ROOT/tools/dump.c" "$ARCHIVE" -o "$OUT/dump_cand"

mapfile -t files < <(corpus_files_small)
[ "${FULL:-0}" = 1 ] && mapfile -t files < <(corpus_files)
pass=0
for f in "${files[@]}"; do
    "$OUT/dump_oracle" "$f" >"$OUT/o.bin"
    "$OUT/dump_cand" "$f" >"$OUT/c.bin"
    cmp -s "$OUT/o.bin" "$OUT/c.bin" || { echo "MISMATCH: $f"; exit 1; }
    pass=$((pass + 1))
done
echo "diff_lib: $pass files byte-identical vs $ARCHIVE"
