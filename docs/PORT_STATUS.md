# Port status

Per-kernel ledger. Status: `pending`, `proposed`, `exact`, `rejected`, `deferred`.

| kernel | location | ISA | status | notes |
|---|---|---|---|---|
| `tdefl_find_match` match scan | `miniz_tdef.c` | SSE2 | **exact** | 16-byte `movemask`/`ctz`; 4.2–15.3× on ≥32-byte mismatches, parity below 16 B |
| `tdefl_find_match` outer probe filter | `miniz_tdef.c` | scalar 16-bit | **exact** | upstream unaligned word compare (part of the compression win) |
| `tdefl_compress_fast` (level-1 parser) | `miniz_tdef.c` | — | **rejected from exact** | changes bytes; available only via `MINIZ_ALLOW_FAST_PARSER` (fast tier) |
| `mz_adler32` | `miniz_simd.h`/`miniz.c` | SSSE3/SSE4.1 | **exact** | `sad` + `maddubs`; ~3.8× isolated |
| `mz_crc32` | `miniz_simd.h`/`miniz.c` | scalar slice-8 | **exact** | ~4.0× isolated, byte-identical value |
| inflate non-overlapping copy | `miniz_tinfl.c`/`miniz_simd.h` | SSE2 | **exact** | out-of-line 16-byte `mz_copy_match`; +1–16% decompress, overlap loop untouched |
| upstream 8-byte inflate copy | `miniz_tinfl.c` | — | **rejected** | perturbed the overlapping scalar loop (~2× on runs); disabled |
| AVX2 match scan | `miniz_simd.h` | AVX2 | **exact, neutral** | runtime-dispatched but no gain; kept for forcing/tests |
| inflate literal fast loop | `miniz_tinfl.c` | — | deferred | already 64-bit bitbuf |
| `tdefl_compress_lz_codes` bit output | `miniz_tdef.c` | — | deferred | already 64-bit accumulator |
| held-out PGO | — | — | **rejected** | regressed inflate |

All active kernels are byte-exact on every level/strategy (39-file differential)
and ASan/UBSan-clean.
