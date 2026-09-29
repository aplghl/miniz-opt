#!/bin/bash
# Build the drop-in static library from src/.
#
#   usage: scripts/build_opt.sh [exact|fast] [outdir]
#   env:   CC (default clang), CFLAGS, PGO=1, PGO_TRAIN (trainer binary)
#
# exact (default): -O3 -march=x86-64-v2 -ffp-contract=off (byte-identical)
# fast           : adds -ffast-math / no fp in miniz, kept for parity of API
#
# The public symbols/ABI are exactly upstream miniz. Runtime AVX2 dispatch (when
# present) is confined to internal kernels; see docs/CONFIG.md.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-exact}
OUT=${2:-"$ROOT/build/lib_$MODE"}
CC=${CC:-clang}
PGO=${PGO:-0}
ARCH_BASE=${ARCH_BASE:-x86-64-v2}

case "$MODE" in
    exact) FP="-ffp-contract=off" ;;
    fast)  FP="-ffast-math" ;;
    *) echo "unknown mode: $MODE (expected exact|fast)"; exit 2 ;;
esac
BASE_FLAGS="-O3 -march=$ARCH_BASE $FP"
: "${CFLAGS:=$BASE_FLAGS}"

SRCS=(miniz miniz_tdef miniz_tinfl miniz_zip)
mkdir -p "$OUT"

build_objects() {
    local extra="$*"
    local objs=()
    for f in "${SRCS[@]}"; do
        # shellcheck disable=SC2086
        $CC $CFLAGS $extra -fvisibility=hidden -I "$ROOT/src" -c "$ROOT/src/$f.c" -o "$OUT/$f.o"
        objs+=("$OUT/$f.o")
    done
    OBJS=("${objs[@]}")
}

if [ "$PGO" = 1 ]; then
    PROF="$ROOT/build/pgo_$MODE"
    rm -rf "$PROF" && mkdir -p "$PROF"

    # Held-out training corpus (disjoint from the benchmark's small-file rows):
    # the 1 MiB / 4 MiB generated regimes only. Override with TRAIN_FILES.
    if [ -z "${TRAIN_FILES:-}" ]; then
        TRAIN_FILES=("$ROOT"/corpus/*_1048576.bin "$ROOT"/corpus/*_4194304.bin)
    else
        read -r -a TRAIN_FILES <<<"$TRAIN_FILES"
    fi

    echo "PGO: instrumenting ($MODE)"
    build_objects -fprofile-generate="$PROF"

    echo "PGO: building trainer over ${#TRAIN_FILES[@]} files"
    # shellcheck disable=SC2086
    $CC $CFLAGS -fprofile-generate="$PROF" -I "$ROOT/src" \
        "$ROOT/tools/train.c" "$ROOT/src/miniz.c" "$ROOT/src/miniz_tdef.c" \
        "$ROOT/src/miniz_tinfl.c" "$ROOT/src/miniz_zip.c" -o "$PROF/train"
    # Train both dispatch paths (if the CPU supports avx2).
    MALLOC_PERTURB_=85 MINIZ_CPU=base "$PROF/train" "${TRAIN_FILES[@]}" >/dev/null 2>&1 || true
    MALLOC_PERTURB_=85 MINIZ_CPU=avx2 "$PROF/train" "${TRAIN_FILES[@]}" >/dev/null 2>&1 || true

    case "$CC" in
        *clang*) llvm-profdata merge -output="$PROF/default.profdata" "$PROF"/*.profraw ;;
    esac
    echo "PGO: rebuilding with profile ($MODE)"
    rm -f "$OUT"/*.o
    case "$CC" in
        *clang*) build_objects -fprofile-use="$PROF/default.profdata" ;;
        *)       build_objects -fprofile-use="$PROF" -fprofile-correction ;;
    esac
else
    build_objects
fi

ar rcs "$OUT/libminiz.a" "${OBJS[@]}"
cp "$ROOT/src/miniz.h" "$ROOT/src/miniz_common.h" "$ROOT/src/miniz_tdef.h" \
   "$ROOT/src/miniz_tinfl.h" "$ROOT/src/miniz_zip.h" "$ROOT/src/miniz_export.h" "$OUT/"
echo "built $OUT/libminiz.a (mode=$MODE pgo=$PGO)"
