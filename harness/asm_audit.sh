#!/bin/bash
# harness/asm_audit.sh — prove the drop-in baseline build contains no wider-ISA
# instructions (no ymm/zmm). The default library intentionally contains AVX2
# target functions; the *baseline* configuration is MINIZ_FORCE_BASE.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/asm_audit"
rm -rf "$OUT"
mkdir -p "$OUT/base" "$OUT/default"
OBJDUMP=$(command -v llvm-objdump || command -v objdump)

build_set() { # <dir> <extra flags>
    local dir="$1"; shift
    for f in miniz miniz_tdef miniz_tinfl miniz_zip; do
        # shellcheck disable=SC2086
        $CC -O3 -march=x86-64-v2 "$@" -fvisibility=hidden -I "$ROOT/src" \
            -c "$ROOT/src/$f.c" -o "$dir/$f.o"
    done
}

build_set "$OUT/base" -DMINIZ_FORCE_BASE
build_set "$OUT/default"

count_wide() { # <file>
    "$OBJDUMP" -d "$1" 2>/dev/null | grep -cE '\b(ymm|zmm)[0-9]' || true
}

base_wide=0
for o in "$OUT"/base/*.o; do base_wide=$((base_wide + $(count_wide "$o"))); done
def_wide=0
for o in "$OUT"/default/*.o; do def_wide=$((def_wide + $(count_wide "$o"))); done

echo "baseline (MINIZ_FORCE_BASE) ymm/zmm count = $base_wide"
echo "default  (with AVX2 target)  ymm/zmm count = $def_wide"

if [ "$base_wide" -ne 0 ]; then
    echo "asm_audit: FAILED — baseline contains wider-ISA instructions"
    exit 1
fi
echo "asm_audit: baseline is clean (xmm/SSE only)"
