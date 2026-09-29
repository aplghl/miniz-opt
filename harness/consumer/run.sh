#!/bin/bash
# harness/consumer/run.sh — link the prebuilt library into a real consumer and
# benchmark vs stock upstream. Writes results/consumer.csv.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/consumer"
mkdir -p "$OUT" "$ROOT/results"
pin=(); command -v taskset >/dev/null 2>&1 && pin=(taskset -c 0)

# Candidate: build the library, then link the consumer against the real archive.
bash "$ROOT/scripts/build_opt.sh" exact "$OUT/lib" >/dev/null
# shellcheck disable=SC2086
$CC -O3 -march=x86-64-v2 -I "$ROOT/src" "$ROOT/harness/consumer/consumer.c" \
    "$OUT/lib/libminiz.a" -o "$OUT/consumer_cand"
# Oracle: stock build, as a consumer would compile it.
# shellcheck disable=SC2086
$ORACLE_CC $ORACLE_FLAGS -I "$ROOT/build/oracle_include" -I "$ROOT/upstream" \
    "$ROOT/harness/consumer/consumer.c" $UP_SRCS -o "$OUT/consumer_oracle"

"${pin[@]}" "$OUT/consumer_oracle" >"$OUT/oracle.csv"
"${pin[@]}" "$OUT/consumer_cand" >"$OUT/cand.csv"

printf 'consumer,op,level,speedup,oracle_ns,cand_ns\n' >"$ROOT/results/consumer.csv"
awk -F, 'FNR==NR{o[$1"|"$2]=$5;next}{k=$1"|"$2;if(k in o && $5>0)printf "%s,%s,%s,%.4f,%s,%s\n",$1,$2,$3,o[k]/$5,o[k],$5}' \
    "$OUT/oracle.csv" "$OUT/cand.csv" >>"$ROOT/results/consumer.csv"
cat "$ROOT/results/consumer.csv"
