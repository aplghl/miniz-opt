# shellcheck shell=bash
# Shared paths / source lists / driver builders for the miniz-opt harnesses.
# Source from a harness script after setting ROOT.

ROOT=${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CC=${CC:-clang}
ORACLE_CC=${ORACLE_CC:-$CC}
ORACLE_FLAGS=${ORACLE_FLAGS:--O2}
CAND_FLAGS=${CAND_FLAGS:--O3 -march=x86-64-v2 -ffp-contract=off}

UP_SRCS="$ROOT/upstream/miniz.c $ROOT/upstream/miniz_tdef.c $ROOT/upstream/miniz_tinfl.c $ROOT/upstream/miniz_zip.c"
CAND_SRCS="$ROOT/src/miniz.c $ROOT/src/miniz_tdef.c $ROOT/src/miniz_tinfl.c $ROOT/src/miniz_zip.c"

# The oracle tree has no generated miniz_export.h; provide it from a private dir.
mkdir -p "$ROOT/build/oracle_include"
cat >"$ROOT/build/oracle_include/miniz_export.h" <<'EOF'
#ifndef MINIZ_EXPORT
#define MINIZ_EXPORT
#endif
EOF

build_oracle_driver() { # <out>
    # shellcheck disable=SC2086
    $ORACLE_CC $ORACLE_FLAGS -I "$ROOT/build/oracle_include" -I "$ROOT/upstream" \
        "$ROOT/tools/dump.c" $UP_SRCS -o "$1"
}

build_cand_driver() { # <out> [extra flags...]
    local out="$1"; shift
    # shellcheck disable=SC2086
    $CC $CAND_FLAGS "$@" -I "$ROOT/src" \
        "$ROOT/tools/dump.c" $CAND_SRCS -o "$out"
}

# Corpus: all generated files; add real files from upstream/examples if present.
corpus_files() {
    ls "$ROOT"/corpus/*.bin 2>/dev/null
    ls "$ROOT"/corpus/real/* 2>/dev/null
    [ -f "$ROOT/upstream/miniz_tdef.c" ] && echo "$ROOT/upstream/miniz_tdef.c"
    [ -f "$ROOT/upstream/miniz_zip.c" ] && echo "$ROOT/upstream/miniz_zip.c"
    [ -f "$ROOT/upstream/ChangeLog.md" ] && echo "$ROOT/upstream/ChangeLog.md"
}

# Fast default: files small enough that the full level/strategy matrix is quick.
corpus_files_small() {
    ls "$ROOT"/corpus/*_4096.bin "$ROOT"/corpus/*_65536.bin 2>/dev/null
    if [ -d "$ROOT/corpus/real" ]; then
        find "$ROOT/corpus/real" -type f -size -131073c 2>/dev/null | sort
    fi
    [ -f "$ROOT/upstream/miniz_tdef.c" ] && echo "$ROOT/upstream/miniz_tdef.c"
    [ -f "$ROOT/upstream/ChangeLog.md" ] && echo "$ROOT/upstream/ChangeLog.md"
}
