#!/bin/bash
# harness/nonvacuous.sh — prove the differential can actually fail by building a
# deliberately corrupted candidate and requiring a mismatch vs the oracle.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/nonvacuous"
rm -rf "$OUT"
mkdir -p "$OUT/src"
cp "$ROOT"/src/*.c "$ROOT"/src/*.h "$OUT/src/"

# Corrupt adler-32 in the copied SIMD helper (reached on this host).
if ! sed -i 's/return (s2 << 16) | s1;/return ((s2 << 16) | s1) + 1u;/' "$OUT/src/miniz_simd.h"; then
    echo "nonvacuous: could not patch copy"; exit 1
fi
if cmp -s "$ROOT/src/miniz_simd.h" "$OUT/src/miniz_simd.h"; then
    echo "nonvacuous: patch had no effect (no injection point)"; exit 1
fi

build_oracle_driver "$OUT/dump_oracle"
# shellcheck disable=SC2086
$CC $CAND_FLAGS -I "$OUT/src" "$ROOT/tools/dump.c" \
    "$OUT/src/miniz.c" "$OUT/src/miniz_tdef.c" "$OUT/src/miniz_tinfl.c" "$OUT/src/miniz_zip.c" \
    -o "$OUT/dump_broken"

f=$(corpus_files_small | head -1)
"$OUT/dump_oracle" "$f" >"$OUT/o.bin"
"$OUT/dump_broken" "$f" >"$OUT/b.bin"
if cmp -s "$OUT/o.bin" "$OUT/b.bin"; then
    echo "nonvacuous: FAILED — corrupted candidate still matched (suite is vacuous)"
    exit 1
fi
echo "nonvacuous: OK — corrupted candidate differs on $(basename "$f")"
