# Rejected experiments (do not retry blindly)

| # | experiment | result | reason |
|---|---|---|---|
| 1 | Held-out **PGO** (whole-library) | **rejected** (off by default) | PGO badly *regressed* inflate (0.74× whole-library, 0.97× even when only the deflate TUs use the profile) and did not improve compress. The giant `tinfl_decompress` coroutine is layout-sensitive; the V1.4 lesson ("PGO value is a property of the artifact structure") applies in the negative here. |
| 2 | Upstream **8-byte unaligned inflate copy** (`MINIZ_USE_UNALIGNED_LOADS_AND_STORES` path in `miniz_tinfl.c`) | **rejected** | enabling it perturbed the hot overlapping scalar copy loop in the huge coroutine: `zeros`/`repeat` decompressed ~2× slower with byte-identical streams. Replaced with an out-of-line SSE2 16-byte copy for the non-overlapping case (`mz_copy_match`), which keeps parity on overlaps and gains 1.01–1.16× elsewhere. |
| 3 | **`-O3`/`-march=` flags alone** | neutral | `-O3`, `-march=x86-64-v2/v3/native`, `-mtune=haswell`, `-funroll-loops` are all ~1.00× on the scalar codec; miniz's hot loops are already tight. `-flto` needs `-fuse-ld=lld` (LLVMgold absent under the system `ld`). |
| 4 | AVX2 match scan (runtime-dispatched) | kept but no gain | an out-of-line `target("avx2")` 32-byte scan is neutral vs the inlined SSE2 16-byte scan (candidates rarely survive to a long scan after the prefix filter), so the match scan is baseline SSE2. |
| 5 | "Flattened deflate hash table (remove per-bucket realloc)" | **N/A** | miniz already uses flat `m_hash[1<<15]` / `m_next[32768]` arrays; this was an stb_image_write item. |
| 6 | `MINIZ_USE_UNALIGNED_LOADS_AND_STORES` in the **default** exact tier | **adopted, level-1 guarded** | the 16-bit match compare is byte-identical for all levels except level 1 (whose separate `tdefl_compress_fast` parser changes bytes). `MINIZ_EXACT_LEVEL1` forces level 1 onto the normal parser, so the whole stream matches the strict-scalar oracle. |

Add entries with the measured number and the reason, per V1.4.
