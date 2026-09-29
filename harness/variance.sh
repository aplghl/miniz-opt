#!/bin/bash
# harness/variance.sh — same-source rebuild spread (noise bound).
#   Writes results/variance.csv (per-row max/min across 3 fresh builds).
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/variance"
mkdir -p "$OUT" "$ROOT/results"
REPS=${REPS:-5}; export REPS
mapfile -t files < <(corpus_files_small | head -6)
pin=(); command -v taskset >/dev/null 2>&1 && pin=(taskset -c 0)

for i in 1 2 3; do
    # shellcheck disable=SC2086
    $CC ${CAND_FLAGS:-} -I "$ROOT/src" "$ROOT/bench/bench.c" $CAND_SRCS -o "$OUT/bench_$i"
    "${pin[@]}" "$OUT/bench_$i" "${files[@]}" >"$OUT/run_$i.csv"
done

python3 - "$OUT/run_1.csv" "$OUT/run_2.csv" "$OUT/run_3.csv" "$ROOT/results/variance.csv" <<'PY'
import csv, sys
runs=[]
for p in sys.argv[1:4]:
    d={}
    with open(p) as f:
        for row in csv.DictReader(f):
            if row['ns_best']:
                d[(row['file'],row['op'],row['level'])]=float(row['ns_best'])
    runs.append(d)
keys=set(runs[0])&set(runs[1])&set(runs[2])
with open(sys.argv[4],'w') as out:
    out.write('file,op,level,ns_ratio_maxmin\n')
    worst=0.0
    for k in sorted(keys):
        vals=[r[k] for r in runs]
        r=max(vals)/min(vals)
        worst=max(worst,r)
        out.write(f'{k[0]},{k[1]},{k[2]},{r:.4f}\n')
print(f"variance: {len(keys)} rows, worst max/min across 3 fresh builds = {worst:.4f}")
PY
