/* miniz_opt.h — candidate build configuration (internal, not public API).
 *
 * Included at the very top of the candidate C sources, before miniz.h, so the
 * settings are visible to the upstream `#if !defined(...)` defaults.
 *
 * Exact tier guarantees:
 *   - x86-64 uses the unaligned (word-at-a-time) match comparator. This is
 *     byte-identical to the strict-scalar oracle for every level except the
 *     level-1 "fast parser"; MINIZ_EXACT_LEVEL1 below forces level 1 onto the
 *     normal parser so the whole stream stays byte-identical.
 *   - All loads use memcpy (MINIZ_UNALIGNED_USE_MEMCPY) so the code is
 *     defined-behavior and sanitizer-clean.
 *
 * Define MINIZ_ALLOW_FAST_PARSER to restore upstream's level-1 fast parser
 * (different bytes; fast tier only).
 */
#ifndef MINIZ_OPT_H
#define MINIZ_OPT_H

/* Do not force the unaligned path under sanitizers: miniz.h itself disables it
 * under UBSan, and defining it here would merely trigger a redefinition. */
#if defined(__has_feature)
#if __has_feature(undefined_behavior_sanitizer) || __has_feature(address_sanitizer)
#define MINIZ_OPT_SANITIZER 1
#endif
#endif
#if defined(__SANITIZE_ADDRESS__) || defined(__SANITIZE_UNDEFINED__)
#define MINIZ_OPT_SANITIZER 1
#endif

#if (defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)) && !defined(MINIZ_NO_SIMD) && !defined(MINIZ_OPT_SANITIZER)
#if !defined(MINIZ_USE_UNALIGNED_LOADS_AND_STORES)
#define MINIZ_USE_UNALIGNED_LOADS_AND_STORES 1
#endif
#if !defined(MINIZ_UNALIGNED_USE_MEMCPY)
#define MINIZ_UNALIGNED_USE_MEMCPY 1
#endif
#endif

#if !defined(MINIZ_ALLOW_FAST_PARSER)
#define MINIZ_EXACT_LEVEL1 1
#endif

/* The upstream 8-byte unaligned inflate copy perturbs the hot overlapping
 * scalar copy loop on this toolchain (measured ~2x slower on run-heavy input)
 * and is not needed: miniz_simd.h provides a 16-byte SSE2 copy for the
 * non-overlapping case, and the original scalar loop handles overlaps. */
#define MINIZ_NO_TINFL_UNALIGNED_COPY 1

#endif /* MINIZ_OPT_H */
