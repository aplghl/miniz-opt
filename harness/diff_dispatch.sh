#!/bin/bash
# harness/diff_dispatch.sh — every ISA/dispatch configuration must be exact.
#   auto (default), forced base, forced avx2, no-simd, no-copy.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/dispatch"
mkdir -p "$OUT"
mapfile -t files < <(corpus_files_small)
build_oracle_driver "$OUT/dump_oracle"

run_cfg() { # <label> <flags...>
    local label="$1"; shift
    local bin="$OUT/dump_$label"
    # shellcheck disable=SC2086
    $CC ${CAND_FLAGS:-} "$@" -I "$ROOT/src" "$ROOT/tools/dump.c" $CAND_SRCS -o "$bin"
    local pass=0
    for f in "${files[@]}"; do
        "$OUT/dump_oracle" "$f" >"$OUT/o.bin"
        "$bin" "$f" >"$OUT/c.bin"
        cmp -s "$OUT/o.bin" "$OUT/c.bin" || { echo "MISMATCH [$label]: $f"; exit 1; }
        pass=$((pass + 1))
    done
    echo "  exact  $label ($pass files)"
}

echo "== dispatch / ISA matrix =="
run_cfg auto
run_cfg base        -DMINIZ_FORCE_BASE
run_cfg avx2        -DMINIZ_FORCE_AVX2
run_cfg nosimd      -DMINIZ_NO_SIMD
run_cfg nocopy      -DMINIZ_NO_SIMD_COPY
echo "dispatch: all exact-tier configurations byte-identical (fastparser is a documented fast tier, excluded)"
