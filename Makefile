# miniz-opt convenience targets. Source scripts/env.sh first so the hermetic
# clang toolchain is on PATH (or override CC).
#
# The oracle is ALWAYS the pristine upstream sources under upstream/; only src/
# is modified.
ROOT := $(CURDIR)
ifeq ($(origin CC),default)
CC := $(shell command -v clang 2>/dev/null || command -v gcc 2>/dev/null || echo cc)
endif
export CC

EXACT_FLAGS ?= -O3 -march=x86-64-v2 -ffp-contract=off

.PHONY: all verify diff diff-lib dispatch abi oracle-integrity sanitize \
        nonvacuous portable asm-audit bench bench-vs-upstream kernels consumer \
        lib lib-fast clean help

all: verify

## Full correctness gate: differential + dispatch matrix + ABI + oracle hash.
verify: oracle-integrity diff dispatch abi

## Byte-exact differential vs the pristine oracle.
diff:
	bash harness/diff.sh $(EXACT_FLAGS)

## Byte-exact differential of the prebuilt library vs the oracle.
diff-lib: lib
	bash harness/diff_lib.sh build/lib_exact/libminiz.a src

## Every exact-tier ISA/dispatch configuration.
dispatch:
	bash harness/diff_dispatch.sh

## Exported-symbol set identical to upstream.
abi:
	bash harness/abi.sh

## The vendored oracle is untouched.
oracle-integrity:
	bash harness/oracle_integrity.sh

## ASan+UBSan over the differential driver.
sanitize:
	bash harness/sanitize.sh

## Prove the differential is non-vacuous.
nonvacuous:
	bash harness/nonvacuous.sh

## Compiler / ISA / C++ / cross-target matrix.
portable:
	bash harness/portable.sh

## Baseline (MINIZ_FORCE_BASE) contains no ymm/zmm.
asm-audit:
	bash harness/asm_audit.sh

## Head-to-head vs upstream -O2 -> results/summary.csv.
bench-vs-upstream:
	bash harness/bench_vs_upstream.sh
bench: bench-vs-upstream

## Isolated kernel speedups -> results/kernels.csv.
kernels:
	bash harness/kernbench.sh

## Downstream consumer linked against the library -> results/consumer.csv.
consumer:
	bash harness/consumer/run.sh

## Build the exact / fast static library.
lib:
	bash scripts/build_opt.sh exact
lib-fast:
	bash scripts/build_opt.sh fast

clean:
	rm -rf build gmon.out .zig-cache zig-out

help:
	@grep -E '^## ' Makefile | sed 's/^## //'
