# Configuration & exactness manifest

For each configuration, whether the candidate is **byte-identical** to the
pristine upstream oracle and which code path applies.

## Build configurations

| config | flags / macros | exact? | mechanism |
|---|---|---|---|
| oracle | `-O2`, default macros | reference | scalar |
| candidate exact | `-O3 -march=x86-64-v2 -ffp-contract=off` | yes | baseline SSE2 + `x86-64-v2` (SSSE3/SSE4.1) kernels |
| forced base | `-DMINIZ_FORCE_BASE` | yes | no AVX2 target functions; assembly-audited clean |
| forced avx2 | `-DMINIZ_FORCE_AVX2` | yes | AVX2 match scan assumed available |
| no SIMD | `-DMINIZ_NO_SIMD` | yes | scalar + original CRC table |
| no copy | `-DMINIZ_NO_SIMD_COPY` | yes | no SSE2 inflate copy |
| unaligned fast tier | `-DMINIZ_ALLOW_FAST_PARSER` | **no** | level-1 `tdefl_compress_fast` parser changes bytes |

The candidate always enables `MINIZ_USE_UNALIGNED_LOADS_AND_STORES` +
`MINIZ_UNALIGNED_USE_MEMCPY` on x86-64 (`src/miniz_opt.h`) and forces level 1
onto the normal parser via `MINIZ_EXACT_LEVEL1`, so every level/strategy matches
the strict-scalar oracle.

## Per-operation exactness

| operation | exact tier | kernel |
|---|---|---|
| deflate (levels 1–10, all strategies) | byte-identical stream | 16-bit unaligned probe filter + SSE2 match scan |
| inflate | bit-identical output | scalar overlapping copy + SSE2 `mz_copy_match` (non-overlapping) |
| adler32 | identical 32-bit value | `psadbw`/`pmaddubsw` (SSSE3/SSE4.1) |
| crc32 | identical 32-bit value | slicing-by-8 |
| ZIP archive | byte-identical with fixed mtime | deflate payload carried through |

## Dispatch

Baseline SSE2 needs no dispatch. The host baseline is `-march=x86-64-v2`, so the
adler32 path may use SSSE3/SSE4.1. AVX2 is selected via a self-contained
CPUID/XGETBV check (`mz_cpu_flags`) with `MINIZ_FORCE_BASE`/`MINIZ_FORCE_AVX2`
overrides, but is measured neutral and used only for tests.

## Gates

`harness/diff.sh` (39-file differential), `harness/diff_dispatch.sh` (every
exact configuration), `harness/diff_lib.sh` (prebuilt archive),
`harness/asm_audit.sh` (baseline `ymm`/`zmm` = 0), `harness/sanitize.sh`,
`harness/nonvacuous.sh`, `harness/portable.sh`, `harness/consumer/run.sh`.
