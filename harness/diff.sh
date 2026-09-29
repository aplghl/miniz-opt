#!/bin/bash
# harness/diff.sh — exact-tier differential: candidate vs pristine oracle.
#
#   usage: harness/diff.sh [candidate CFLAGS...]
#   env:   CC, ORACLE_CC, ORACLE_FLAGS, CORPUS (comma list), QUICK=1
#
# Builds the same deterministic driver (tools/dump.c) against the pristine
# upstream sources (stock build) and against src/ (candidate flags), runs both
# over the corpus, and byte-compares. Exit non-zero on any mismatch.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

if [ "$#" -gt 0 ]; then
    CAND_FLAGS="$*"
fi
CAND_EXTRA=${CAND_EXTRA:-}

OUT="$ROOT/build/diff"
mkdir -p "$OUT"
echo "oracle  : $ORACLE_CC $ORACLE_FLAGS"
echo "cand    : $CC $CAND_FLAGS"

build_oracle_driver "$OUT/dump_oracle"
# shellcheck disable=SC2086
build_cand_driver "$OUT/dump_cand" $CAND_EXTRA

if [ -n "${CORPUS:-}" ]; then
    IFS=',' read -r -a files <<<"$CORPUS"
elif [ "${FULL:-0}" = 1 ]; then
    mapfile -t files < <(corpus_files)
else
    mapfile -t files < <(corpus_files_small)
fi
if [ "${QUICK:-0}" = 1 ]; then
    files=("${files[@]:0:4}")
fi

pass=0
fail=0
for f in "${files[@]}"; do
    "$OUT/dump_oracle" "$f" >"$OUT/o.bin"
    "$OUT/dump_cand" "$f" >"$OUT/c.bin"
    if cmp -s "$OUT/o.bin" "$OUT/c.bin"; then
        pass=$((pass + 1))
    else
        echo "MISMATCH: $f"
        fail=$((fail + 1))
    fi
done
if [ "$fail" -eq 0 ]; then
    echo "diff: $pass files byte-identical ($CC $CAND_FLAGS)"
    exit 0
fi
echo "diff: $fail/$((pass + fail)) files DIFFER"
exit 1
