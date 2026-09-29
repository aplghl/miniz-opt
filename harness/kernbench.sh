#!/bin/bash
# harness/kernbench.sh — isolated kernel speedups (SIMD vs scalar baseline).
#   Writes results/kernels.csv: kernel,case,speedup,simd_ns,base_ns
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/kern"
mkdir -p "$OUT" "$ROOT/results"
SRCS="$ROOT/src/miniz.c $ROOT/src/miniz_tdef.c $ROOT/src/miniz_tinfl.c $ROOT/src/miniz_zip.c"
pin=(); command -v taskset >/dev/null 2>&1 && pin=(taskset -c 0)

# shellcheck disable=SC2086
$CC -O3 -march=x86-64-v2 -I "$ROOT/src" "$ROOT/bench/kernbench.c" $SRCS -o "$OUT/kern_simd"
# shellcheck disable=SC2086
$CC -O3 -march=x86-64-v2 -DMINIZ_NO_SIMD -I "$ROOT/src" "$ROOT/bench/kernbench.c" $SRCS -o "$OUT/kern_base"

"${pin[@]}" "$OUT/kern_simd" >"$OUT/simd.csv"
"${pin[@]}" "$OUT/kern_base" >"$OUT/base.csv"

printf 'kernel,case,speedup,simd_ns,base_ns\n' >"$ROOT/results/kernels.csv"
awk -F, 'FNR==NR{if(FNR>1){b[$1"|"$2]=$3}next}FNR>1{k=$1"|"$2;if(k in b && $3>0){printf "%s,%s,%.3f,%s,%.4f\n",$1,$2,b[k]/$3,$3,b[k]}}' \
    "$OUT/base.csv" "$OUT/simd.csv" >>"$ROOT/results/kernels.csv"
cat "$ROOT/results/kernels.csv"
