#!/bin/bash
# harness/bench_vs_upstream.sh — head-to-head candidate vs stock upstream -O2.
#
#   env: PGO=1 (candidate built with scripts/build_opt.sh pgo), CAND_FLAGS,
#        CORPUS (comma list), REPS, LEVELS
# Writes results/summary.csv and prints a geomean table (ratios only).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/bench"
mkdir -p "$OUT" "$ROOT/results"
REPS=${REPS:-3}
export REPS
: "${LEVELS:=1,6,9}"
export LEVELS

if [ -n "${CORPUS:-}" ]; then
    IFS=',' read -r -a files <<<"$CORPUS"
else
    mapfile -t files < <(corpus_files_small)
fi

# --- build both benches -----------------------------------------------------
# shellcheck disable=SC2086
$ORACLE_CC $ORACLE_FLAGS -I "$ROOT/build/oracle_include" -I "$ROOT/upstream" \
    "$ROOT/bench/bench.c" $UP_SRCS -o "$OUT/bench_oracle"

if [ "${PGO:-0}" = 1 ]; then
    bash "$ROOT/scripts/build_opt.sh" exact "$OUT/lib_pgo" >/dev/null
    CAND_FILES=("$OUT/lib_pgo/libminiz.a")
    # shellcheck disable=SC2086
    $CC ${CAND_FLAGS:-} -I "$ROOT/src" "$ROOT/bench/bench.c" "${CAND_FILES[@]}" -o "$OUT/bench_cand"
else
    # shellcheck disable=SC2086
    $CC ${CAND_FLAGS:-} -I "$ROOT/src" "$ROOT/bench/bench.c" $CAND_SRCS -o "$OUT/bench_cand"
fi

pin=()
command -v taskset >/dev/null 2>&1 && pin=(taskset -c 0)
"${pin[@]}" "$OUT/bench_oracle" "${files[@]}" >"$OUT/oracle.csv"
"${pin[@]}" "$OUT/bench_cand" "${files[@]}" >"$OUT/cand.csv"

awk -F, '
FNR==NR { if (FNR>1) { key=$1"|"$2"|"$3; o[key]=$6; } next }
FNR>1 {
  key=$1"|"$2"|"$3; c=$6;
  if (!(key in o) || o[key]<=0 || c<=0) next;
  sp=o[key]/c;
  n++;
  logsum+=log(sp);
  printf "%s,%s,%s,%.4f,%s,%s\n", $1,$2,$3,sp,o[key],c;
}
END { if (n>0) printf "GEOMEAN,all,all,%.4f,,\n", exp(logsum/n); }
' "$OUT/oracle.csv" "$OUT/cand.csv" >"$ROOT/results/summary.csv"

echo "== speedup = oracle_ns / cand_ns (file,op,level,speedup,o_ns,c_ns) =="
head -40 "$ROOT/results/summary.csv"
echo "wrote results/summary.csv"
