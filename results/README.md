# results/ — artifact → generator → status

| file | producer | status |
|---|---|---|
| `summary.csv` | `harness/bench_vs_upstream.sh` | candidate vs upstream `-O2` (compress/decompress/checksums) |
| `flags.csv` | `harness/flagsweep.sh` | compiler/ISA A/B geomeans |
| `kernels.csv` | `harness/kernbench.sh` | isolated SIMD vs scalar kernels |
| `consumer.csv` | `harness/consumer/run.sh` | downstream consumer linked against the library |
| `variance.csv` | `harness/variance.sh` | pending |
| `dispatch.csv` | `harness/diff_dispatch.sh` | exact-tier ISA matrix (text output) |

## summary.csv

`file,op,level,speedup,oracle_ns,candidate_ns`; `speedup = oracle_ns /
candidate_ns` (>1 faster). A trailing `GEOMEAN,all,all,<x>` row summarizes. All
times are min-of-repeats nanoseconds, pinned with `taskset`; ratios only.

Latest (16 files × levels 1/6/9, clang 23.1.2, i7-14700F):
**compress +21.1%**, decompress +1.7%, checksums ~3.7×.

## kernels.csv

`kernel,case,speedup,simd_ns,base_ns`. Isolated match scan / adler32 / crc32
(SIMD build vs `MINIZ_NO_SIMD`). Match scan is 4.2–15.3× for mismatches ≥32 bytes
but 0.67–0.99× below 16 bytes — a reported weak regime.

## consumer.csv

`consumer,op,level,speedup,oracle_ns,cand_ns`. 2 MiB structured text through the
zlib API: **compress 1.32×, decompress 1.04×**.

Sub-~3% per-row differences are noise. Absolute times are host/run specific.
