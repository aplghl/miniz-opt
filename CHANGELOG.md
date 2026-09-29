# Changelog

## v0.1.0

- Baseline SIMD (SSE2 match scan, SSSE3/SSE4.1 adler32, SSE2 inflate copy) and
  slicing-by-8 CRC-32, all byte-exact vs the pristine oracle.
- 16-bit unaligned deflate probe filter; level 1 held on the normal parser
  (`MINIZ_EXACT_LEVEL1`) so its output matches.
- Held-out PGO evaluated and rejected (regressed inflate).
- Full gate matrix: differential, dispatch/ISA, ABI (115 symbols), ASan+UBSan,
  non-vacuous, portability, baseline assembly audit, downstream consumer.
