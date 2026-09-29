#!/bin/bash
# harness/oracle_integrity.sh — the vendored oracle must be untouched.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
cd "$ROOT/upstream"
if sha256sum -c "$ROOT/scripts/oracle_hashes.txt" >"$TMP" 2>&1; then
    echo "oracle-integrity: all $(wc -l <"$ROOT/scripts/oracle_hashes.txt") files match pinned hashes"
    exit 0
fi
echo "oracle-integrity: FAILED"
cat "$TMP"
exit 1
