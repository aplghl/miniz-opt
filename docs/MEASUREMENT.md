# miniz-opt measurement & environment audit

Target: **Intel Core i7-14700F** (Raptor Lake; AVX2 + FMA + BMI2 + F16C +
SSE4.2 + PCLMULQDQ, **no AVX-512**), WSL2 Ubuntu 24.04, 28 logical CPUs.
Oracle: `richgel999/miniz` @ `77d0dce8627735138c51770d1799a1ef48f2117d`
(v3.1.2), vendored pristine in `upstream/`, per-file `sha256` in
`scripts/oracle_hashes.txt`.

## Toolchain (Layer 0.1 audit)

| Tool | Availability | Notes |
|---|---|---|
| gcc | 13.3.0 | system fallback |
| clang + LLD | 23.1.2 (hermetic, user space) | primary; `scripts/env.sh` |
| zig | 0.16.0 | cross-compilation |
| cmake / g++ | 3.28.3 / 13.3 | upstream conformance suite |
| `perf` | absent (WSL2, no PMU) | AutoFDO/BOLT out of reach |
| valgrind / callgrind | present but unusable on this host (stripped system `ld.so` breaks the mandatory `strlen` redirection without libc6-dbg) | ASan/UBSan carry safety |
| llvm-mca / llvm-bolt | present in the LLVM tarball | static analysis available |
| objdump / llvm-objdump | present | baseline-ISA assembly audit |

The **build driver is part of the contract**: `zig cc -march=x86-64-v2` is
silently ignored (Zig maps it to `-mcpu`) and native `zig build` widens every
file, per the V1.4 resize postmortem. All ISA claims here are validated by
`harness/asm_audit.sh`, not by the command line.

## Observable Output Contract (OOC)

miniz is a **codec-pair** (deflate encoder + inflate decoder + checksums, plus
optional ZIP).

- **deflate (encoder) exact tier** — the compressed byte stream is
  **byte-identical** to the pristine oracle for the same input and settings
  (level 0–10 × strategy default/filtered/huffman-only/rle/fixed × raw/zlib).
  Only *mechanics* may change; any change to parse/match/Huffman **choices**
  changes the bytes and is forbidden.
- **inflate (decoder) exact tier** — decompressed bytes are bit-identical.
- **checksums (exact)** — `mz_adler32`/`mz_crc32` return identical 32-bit bits.
- **ZIP exact tier** — archive bytes identical given fixed timestamps.
- **fast tier (off by default)** — `MINIZ_USE_UNALIGNED_LOADS_AND_STORES=1`
  compiles a different level-1 parser (`tdefl_compress_fast`) and a 16-bit
  match comparator. It is **not** byte-identical (proven by
  `harness/portable.sh`); it is documented and never the default.

## Clock / units

Throughput is reported in **nanoseconds** (min over repeats, pinned with
`taskset`). **Ratios only**; `rdtsc` ticks are never called "cycles". Sub-~3%
per-row differences are noise. Tiny (≤64 KiB random) rows are dominated by
clock/call overhead and are not used for headline claims.

## Corpora

- Generated deterministic regimes (`tools/gen.c`): `zeros`, `repeat`, `ramp`,
  `text`, `source`, `random`, `runs`, `mixed` at 4 KiB / 64 KiB / 1 MiB / 4 MiB.
- Real files: upstream `miniz_tdef.c`, `miniz_zip.c`, `ChangeLog.md`; optional
  downloaded real corpus under `corpus/real/` (see `scripts/fetch_corpus.sh`).
- Differential matrix (`tools/dump.c`): checksums × 11 levels × 5 strategies ×
  {raw,zlib} × single-shot and chunked streaming, plus `mz_compress2`/
  `mz_uncompress`. Every produced stream is also decompressed and re-emitted.

## Exactness findings so far

| candidate config | exact? | notes |
|---|---|---|
| `-O2`, `-O3`, `-Os` | yes | baseline |
| `-O3 -march=x86-64-v2` | yes | candidate default |
| `-O3 -march=x86-64-v3` | yes | AVX2 emits; not drop-in until dispatched |
| `-O3 -march=native` | yes | not drop-in |
| gcc and clang | yes | |
| C++ (`clang++`) | yes | |
| `-DMINIZ_USE_UNALIGNED_LOADS_AND_STORES=1` + `MINIZ_EXACT_LEVEL1` | **yes** | adopted exact path; 16-bit match compare, level 1 kept on the normal parser |
| Held-out PGO | n/a | **rejected**: regressed inflate (0.74× whole-library) for no compress gain |

## Results (v0.1, clang 23.1.2, no PGO)

Candidate `-O3 -march=x86-64-v2 -ffp-contract=off` vs stock oracle `-O2`,
min-of-7 ns, `taskset -c 0`, `results/summary.csv` (16 files × levels 1/6/9):

| group | geomean speedup |
|---|---|
| compress (47 rows) | **+21.1%** (1.211×) |
| decompress (48 rows) | +1.7% (1.017×; parity, a few noisy rows) |
| adler32 | ~3.6–4.3× |
| crc32 | ~4.0× |

Isolated kernels (`results/kernels.csv`, SIMD vs `MINIZ_NO_SIMD`):
match scan 4.2–15.3× for mismatches ≥32 bytes, **0.67–0.99× below 16 bytes**
(the evalue prefix filter keeps most real probes short), adler32 **3.8×**,
crc32 **4.0×**. Weak regimes are reported, not hidden: the short-match scan and
some decompress rows are parity-to-slightly-negative.

## Dispatch decision

Baseline **SSE2** (x86-64 ABI) needs no dispatch and carries the match scan and
inflate copy. The library is compiled at `-march=x86-64-v2` (SSE4.2/SSSE3
baseline, as the sibling stb forks), so the vectorized adler32 uses
SSSE3/SSE4.1. Optional **AVX2** (self-contained CPUID/XGETBV, `MINIZ_FORCE_*`,
`MINIZ_CPU`) is wired for the match scan but measured neutral, so the match scan
stays baseline. A forced-base build is disassembly-audited (`harness/asm_audit.sh`)
to contain no `ymm`/`zmm`.

## Measurement caveats

- No PMU → hotspot ranking uses labeled-`objdump` instruction budgets,
  `llvm-mca`, and kernel-isolated microbenchmarks; instruction share only ranks
  candidates, the controlled A/B is the verdict.
- Compression is compute-bound (hash probes + match compares); checksum and
  streaming rows may be plumbing-bound and are classified as such.
- Run the differential under `MALLOC_PERTURB_=85` with oracle/candidate sharing
  the same optional macros (none here) to control layout/uninitialized-read
  effects.
