#!/bin/bash
# harness/flagsweep.sh — compiler/ISA A/B vs the stock -O2 oracle.
#   Writes results/flags.csv (geomean speedups, ratios only).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/flagsweep"
mkdir -p "$OUT" "$ROOT/results"
REPS=${REPS:-3}; export REPS
LEVELS=${LEVELS:-1,6,9}; export LEVELS

# Representative, compute-bound corpus (small/medium so the sweep is quick).
mapfile -t files < <(
    ls "$ROOT"/corpus/text_65536.bin "$ROOT"/corpus/source_65536.bin \
       "$ROOT"/corpus/mixed_65536.bin "$ROOT"/corpus/runs_65536.bin \
       "$ROOT"/corpus/ramp_65536.bin "$ROOT"/corpus/text_1048576.bin 2>/dev/null
    ls "$ROOT"/corpus/real/* 2>/dev/null | head -8
)

# shellcheck disable=SC2086
$ORACLE_CC $ORACLE_FLAGS -I "$ROOT/build/oracle_include" -I "$ROOT/upstream" \
    "$ROOT/bench/bench.c" $UP_SRCS -o "$OUT/bench_oracle"
pin=(); command -v taskset >/dev/null 2>&1 && pin=(taskset -c 0)
"${pin[@]}" "$OUT/bench_oracle" "${files[@]}" >"$OUT/oracle.csv"

printf 'flags,geomean_all,geomean_compress,geomean_decompress,geomean_checksum\n' >"$ROOT/results/flags.csv"

sweep() { # <label> <cc> <flags...>
    local label="$1" cc="$2"; shift 2
    local flags="$*"
    local bin="$OUT/bench_$(echo "$label" | tr -c 'a-zA-Z0-9' '_')"
    # shellcheck disable=SC2086
    if ! $cc $flags -I "$ROOT/src" "$ROOT/bench/bench.c" $CAND_SRCS -o "$bin" 2>"$OUT/err.txt"; then
        echo "  build-fail $label"; return 0
    fi
    "${pin[@]}" "$bin" "${files[@]}" >"$OUT/cand.csv"
    awk -F, -v spec="$label" '
      FNR==NR { if (FNR>1) { k=$1"|"$2"|"$3; o[k]=$6 } next }
      FNR>1 {
        k=$1"|"$2"|"$3; if (!(k in o) || o[k]<=0 || $6<=0) next;
        sp=o[k]/$6; op=$2; n++; ls+=log(sp);
        if (op=="compress"){nc++;lc+=log(sp)}
        else if (op=="decompress"){nd++;ld+=log(sp)}
        else {nk++;lk+=log(sp)}
      }
      END { if (n) printf "%s,%.4f,%.4f,%.4f,%.4f\n", spec, exp(ls/n),
                 (nc?exp(lc/nc):0), (nd?exp(ld/nd):0), (nk?exp(lk/nk):0) }
    ' "$OUT/oracle.csv" "$OUT/cand.csv" >>"$ROOT/results/flags.csv"
    tail -1 "$ROOT/results/flags.csv"
}

echo "== flag sweep (geomean oracle_ns/cand_ns; >1 faster) =="
sweep O2                   "$CC" -O2
sweep O3                   "$CC" -O3
sweep O3_v2                "$CC" -O3 -march=x86-64-v2
sweep O3_v2_mtune_haswell  "$CC" -O3 -march=x86-64-v2 -mtune=haswell
sweep O3_v2_unroll         "$CC" -O3 -march=x86-64-v2 -funroll-loops
sweep O3_v2_flto           "$CC" -O3 -march=x86-64-v2 -flto
sweep O3_v3                "$CC" -O3 -march=x86-64-v3
sweep O3_native            "$CC" -O3 -march=native
sweep O3_v2_unaligned      "$CC" -O3 -march=x86-64-v2 -DMINIZ_USE_UNALIGNED_LOADS_AND_STORES=1 -DMINIZ_UNALIGNED_USE_MEMCPY
sweep gcc_O3_v2            gcc   -O3 -march=x86-64-v2
echo "wrote results/flags.csv"
