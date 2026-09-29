#!/bin/bash
# harness/abi.sh — exported-symbol set must be identical to pristine upstream.
#
# Builds a static archive from upstream and from src/ and diffs their global
# defined symbols. The candidate may add no exports and remove none.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

NM=$(command -v llvm-nm || command -v nm)
OUT="$ROOT/build/abi"
rm -rf "$OUT"
mkdir -p "$OUT/o" "$OUT/c"

compile_archive() { # <srcdir> <cc> <flags> <objdir> <archive>
    local srcdir="$1" cc="$2" flags="$3" objdir="$4" archive="$5"
    local objs=()
    for f in miniz miniz_tdef miniz_tinfl miniz_zip; do
        # shellcheck disable=SC2086
        $cc $flags -I "$ROOT/build/oracle_include" -I "$srcdir" -c "$srcdir/$f.c" -o "$objdir/$f.o"
        objs+=("$objdir/$f.o")
    done
    ar rcs "$archive" "${objs[@]}"
}

compile_archive "$ROOT/upstream" "$ORACLE_CC" "$ORACLE_FLAGS" "$OUT/o" "$OUT/oracle.a"
compile_archive "$ROOT/src" "$CC" "${CAND_FLAGS:-}" "$OUT/c" "$OUT/cand.a"

symset() { "$NM" -g --defined-only "$1" | awk 'NF>=3{print $3}' | sort -u; }
symset "$OUT/oracle.a" >"$OUT/o.syms"
symset "$OUT/cand.a" >"$OUT/c.syms"

if diff -u "$OUT/o.syms" "$OUT/c.syms" >"$OUT/syms.diff"; then
    echo "abi: $(wc -l <"$OUT/o.syms") exported symbols identical"
    exit 0
fi
echo "abi: exported symbol set DIFFERS"
cat "$OUT/syms.diff"
exit 1
