#!/bin/bash
# harness/oracle_integrity.sh — the vendored oracle must be untouched.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/upstream"
if sha256sum -c "$ROOT/scripts/oracle_hashes.txt" >/tmp/opencode/oracle_check.txt 2>&1; then
    echo "oracle-integrity: all $(wc -l <"$ROOT/scripts/oracle_hashes.txt") files match pinned hashes"
    exit 0
fi
echo "oracle-integrity: FAILED"
cat /tmp/opencode/oracle_check.txt
exit 1
