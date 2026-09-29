#!/bin/bash
# harness/portable.sh — candidate must stay byte-exact across compilers, ISAs,
# C++, and must cross-compile. Reports a matrix; the unaligned-loads macro is
# allowed to differ (documented fast tier) and is labeled EXPECTED-DIFF.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck disable=SC1091
. "$ROOT/harness/matrix.inc.sh"

OUT="$ROOT/build/portable"
mkdir -p "$OUT"
mapfile -t files < <(corpus_files_small)
probe="$ROOT/build/sample.txt"
[ -f "$probe" ] || printf 'abcabcabcabc\n%.0s' $(seq 1 2000) >"$probe"

build_oracle_driver "$OUT/dump_oracle"
"$OUT/dump_oracle" "$probe" >"$OUT/o.bin"

run_spec() { # <label> <cc> <flags...>
    local label="$1" cc="$2"; shift 2
    local flags="$*"
    local bin="$OUT/dump_$(echo "$label" | tr -c 'a-zA-Z0-9' '_')"
    # shellcheck disable=SC2086
    if ! $cc $flags -I "$ROOT/src" "$ROOT/tools/dump.c" $CAND_SRCS -o "$bin" 2>"$OUT/err.txt"; then
        echo "  FAIL(compile) $label: $cc $flags"; sed 's/^/      /' "$OUT/err.txt" | head -5
        return 1
    fi
    "$bin" "$probe" >"$OUT/c.bin"
    if cmp -s "$OUT/o.bin" "$OUT/c.bin"; then
        echo "  exact         $label   ($cc $flags)"
    else
        echo "  EXPECTED-DIFF $label   ($cc $flags)"
    fi
}

echo "== compiler / flag matrix (probe: $(basename "$probe")) =="
run_spec clang_O2          clang -O2
run_spec clang_v2          clang -O3 -march=x86-64-v2
run_spec clang_v3          clang -O3 -march=x86-64-v3
run_spec clang_native      clang -O3 -march=native
run_spec clang_omax        clang -Os
run_spec gcc_O2            gcc   -O2
run_spec gcc_v2            gcc   -O3 -march=x86-64-v2
run_spec gcc_v3            gcc   -O3 -march=x86-64-v3
run_spec clang_unaligned   clang -O3 -march=x86-64-v2 -DMINIZ_USE_UNALIGNED_LOADS_AND_STORES=1 -DMINIZ_UNALIGNED_USE_MEMCPY
run_spec gcc_unaligned     gcc   -O3 -march=x86-64-v2 -DMINIZ_USE_UNALIGNED_LOADS_AND_STORES=1 -DMINIZ_UNALIGNED_USE_MEMCPY

echo "== C++ build =="
if clang++ -O2 -x c++ -I "$ROOT/src" "$ROOT/tools/dump.c" $CAND_SRCS -o "$OUT/dump_cpp" 2>"$OUT/err.txt"; then
    "$OUT/dump_cpp" "$probe" >"$OUT/c.bin"
    cmp -s "$OUT/o.bin" "$OUT/c.bin" && echo "  exact         C++ (clang++ -O2)" || echo "  DIFF          C++ (clang++ -O2)"
else
    echo "  FAIL(compile) C++"; sed 's/^/      /' "$OUT/err.txt" | head -5
fi

echo "== cross-compile (build only, zig) =="
if command -v zig >/dev/null 2>&1; then
    for tgt in aarch64-linux-musl x86_64-linux-musl x86_64-windows-gnu aarch64-macos; do
        if zig cc -target "$tgt" -O2 -I "$ROOT/src" -c "$ROOT/src/miniz_tinfl.c" -o "$OUT/tinfl_$tgt.o" 2>"$OUT/err.txt"; then
            echo "  build         $tgt"
        else
            echo "  FAIL(build)   $tgt"; sed 's/^/      /' "$OUT/err.txt" | head -5
        fi
    done
else
    echo "  SKIP (zig not found)"
fi
