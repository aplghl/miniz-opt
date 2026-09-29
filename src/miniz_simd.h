/* miniz_simd.h — internal SIMD helpers for miniz-opt.
 *
 * NOT part of the public API. Included only by the candidate miniz C sources.
 * Everything here has internal (static) linkage so the exported symbol set and
 * ABI stay exactly upstream.
 *
 * Controls:
 *   MINIZ_NO_SIMD    disable all SIMD (scalar only)
 *   MINIZ_FORCE_BASE force the baseline paths (no AVX2 target functions)
 *   MINIZ_FORCE_AVX2 assume/require AVX2 at runtime (skips CPUID)
 *
 * SSE2 is baseline on x86-64 (no dispatch). AVX2 is selected at runtime via a
 * self-contained CPUID/XGETBV check (no __builtin_cpu_supports, whose
 * __cpu_model symbol is unresolvable under `zig cc`).
 */
#ifndef MINIZ_SIMD_H
#define MINIZ_SIMD_H

#if !defined(MINIZ_NO_SIMD) && (defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86) || defined(__i386))
#define MZ_SIMD_X86 1
#else
#define MZ_SIMD_X86 0
#endif

#if MZ_SIMD_X86 && (defined(__SSE2__) || defined(_M_X64))
#include <emmintrin.h>
#define MZ_SIMD_SSE2 1
#else
#define MZ_SIMD_SSE2 0
#endif

/* AVX2 intrinsics are only valid inside a target("avx2") function; compile
 * support is guaranteed by clang/gcc even when the TU baseline is x86-64-v2.
 * Include the full intrinsic headers whenever the compiler is GNU-like so the
 * SSSE3/SSE4.1 adler32 path and the SSE2 copy compile too. */
#if MZ_SIMD_X86 && (defined(__GNUC__) || defined(__clang__))
#include <immintrin.h>
#endif
#if MZ_SIMD_X86 && (defined(__GNUC__) || defined(__clang__)) && !defined(MINIZ_FORCE_BASE)
#define MZ_SIMD_AVX2_TARGET 1
#else
#define MZ_SIMD_AVX2_TARGET 0
#endif

#define MZ_CPU_SSE2 1
#define MZ_CPU_AVX2 2

#if MZ_SIMD_X86 && (defined(__GNUC__) || defined(__clang__)) && !defined(MINIZ_FORCE_BASE)
static int mz_cpu_flags(void)
{
    static int cached = -1;
    int f = cached;
    if (f < 0)
    {
        unsigned a = 0, b = 0, c = 0, d = 0, max_leaf;
        f = 0;
        __asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(0u), "c"(0u));
        max_leaf = a;
        if (max_leaf >= 1u)
        {
            __asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(1u), "c"(0u));
            {
                int sse2 = (int)((d >> 26) & 1u);
                int osxsave = (int)((c >> 27) & 1u);
                int avx = (int)((c >> 28) & 1u);
                if (sse2)
                    f |= MZ_CPU_SSE2;
                if (avx && osxsave)
                {
                    unsigned long long xcr0;
                    unsigned lo, hi;
                    __asm__ volatile(".byte 0x0f, 0x01, 0xd0" : "=a"(lo), "=d"(hi) : "c"(0u));
                    xcr0 = ((unsigned long long)hi << 32) | lo;
                    if ((xcr0 & 0x6u) == 0x6u && max_leaf >= 7u)
                    {
                        __asm__ volatile("cpuid" : "=a"(a), "=b"(b), "=c"(c), "=d"(d) : "a"(7u), "c"(0u));
                        if ((b >> 5) & 1u)
                            f |= MZ_CPU_AVX2;
                    }
                }
            }
        }
        cached = f;
    }
    return f;
}
#endif /* x86 GNU/clang */

static mz_uint mz_match_len_scalar(const mz_uint8 *p, const mz_uint8 *q, mz_uint max_len)
{
    mz_uint i;
    for (i = 0; i < max_len; i++)
        if (p[i] != q[i])
            break;
    return i;
}

#if MZ_SIMD_SSE2
static MZ_FORCEINLINE mz_uint mz_match_len_sse2(const mz_uint8 *p, const mz_uint8 *q, mz_uint max_len)
{
    mz_uint i = 0;
    for (; i + 16 <= max_len; i += 16)
    {
        __m128i a = _mm_loadu_si128((const __m128i *)(const void *)(p + i));
        __m128i b = _mm_loadu_si128((const __m128i *)(const void *)(q + i));
        unsigned m = (unsigned)_mm_movemask_epi8(_mm_cmpeq_epi8(a, b));
        if (m != 0xFFFFu)
            return i + (mz_uint)__builtin_ctz((~m) & 0xFFFFu);
    }
    for (; i < max_len; i++)
        if (p[i] != q[i])
            break;
    return i;
}
#endif

#if MZ_SIMD_AVX2_TARGET
__attribute__((target("avx2"))) static mz_uint mz_match_len_avx2(const mz_uint8 *p, const mz_uint8 *q, mz_uint max_len)
{
    mz_uint i = 0;
    for (; i + 32 <= max_len; i += 32)
    {
        __m256i a = _mm256_loadu_si256((const __m256i *)(const void *)(p + i));
        __m256i b = _mm256_loadu_si256((const __m256i *)(const void *)(q + i));
        unsigned m = (unsigned)_mm256_movemask_epi8(_mm256_cmpeq_epi8(a, b));
        if (m != 0xFFFFFFFFu)
            return i + (mz_uint)__builtin_ctz(~m);
    }
    for (; i < max_len; i++)
        if (p[i] != q[i])
            break;
    return i;
}
#endif

static MZ_FORCEINLINE mz_uint mz_match_len(const mz_uint8 *p, const mz_uint8 *q, mz_uint max_len)
{
#if MZ_SIMD_AVX2_TARGET
#if defined(MINIZ_FORCE_AVX2)
    return mz_match_len_avx2(p, q, max_len);
#else
    if (mz_cpu_flags() & MZ_CPU_AVX2)
        return mz_match_len_avx2(p, q, max_len);
#endif
#endif
#if MZ_SIMD_SSE2
    return mz_match_len_sse2(p, q, max_len);
#else
    return mz_match_len_scalar(p, q, max_len);
#endif
}

/* ---- exact 16-byte non-overlapping copy (inflate) ------------------------ */
#if MZ_SIMD_SSE2
#if defined(__GNUC__) || defined(__clang__)
#define MZ_NOINLINE __attribute__((noinline))
#else
#define MZ_NOINLINE
#endif
MZ_NOINLINE static void mz_copy_match(mz_uint8 *dst, const mz_uint8 *src, mz_uint n)
{
    mz_uint i = 0;
    for (; i + 16 <= n; i += 16)
    {
        __m128i v = _mm_loadu_si128((const __m128i *)(const void *)(src + i));
        _mm_storeu_si128((__m128i *)(void *)(dst + i), v);
    }
    for (; i < n; i++)
        dst[i] = src[i];
}
#endif /* MZ_SIMD_SSE2 */

/* ---- CRC-32 slicing-by-8 (portable, exact) ------------------------------- */
static void mz_crc32_slice8_init(mz_uint32 t[8][256])
{
    mz_uint32 i, k, c;
    for (i = 0; i < 256; i++)
    {
        c = i;
        for (k = 0; k < 8; k++)
            c = (c & 1u) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
        t[0][i] = c;
    }
    for (k = 1; k < 8; k++)
        for (i = 0; i < 256; i++)
            t[k][i] = (t[k - 1][i] >> 8) ^ t[0][t[k - 1][i] & 0xFFu];
}

static mz_uint32 mz_crc32_slice8(const mz_uint8 *p, size_t len, mz_uint32 crc)
{
    static mz_uint32 t[8][256];
    static int init = 0;
    mz_uint32 c = crc ^ 0xFFFFFFFFu;
    if (!init)
    {
        mz_crc32_slice8_init(t);
        init = 1;
    }
    while (len >= 8)
    {
        mz_uint32 lo, hi;
        memcpy(&lo, p, 4);
        memcpy(&hi, p + 4, 4);
        c ^= lo;
        c = t[7][c & 0xFFu] ^ t[6][(c >> 8) & 0xFFu] ^ t[5][(c >> 16) & 0xFFu] ^ t[4][(c >> 24) & 0xFFu] ^
            t[3][hi & 0xFFu] ^ t[2][(hi >> 8) & 0xFFu] ^ t[1][(hi >> 16) & 0xFFu] ^ t[0][(hi >> 24) & 0xFFu];
        p += 8;
        len -= 8;
    }
    while (len--)
        c = (c >> 8) ^ t[0][(c ^ *p++) & 0xFFu];
    return c ^ 0xFFFFFFFFu;
}

/* ---- Adler-32 (SSSE3/SSE4.1 vectorized, exact) --------------------------- */
#if MZ_SIMD_X86 && defined(__SSSE3__) && defined(__SSE4_1__)
#define MZ_SIMD_ADLER32 1
#else
#define MZ_SIMD_ADLER32 0
#endif

static mz_uint32 mz_adler32_simd(mz_uint32 adler, const mz_uint8 *ptr, size_t buf_len)
{
    mz_uint32 s1 = adler & 0xFFFFu, s2 = (adler >> 16) & 0xFFFFu;
    const size_t NMAX = 5552;
    while (buf_len)
    {
        size_t block = (buf_len < NMAX) ? buf_len : NMAX;
        size_t i = 0;
#if MZ_SIMD_ADLER32
        {
            const __m128i zero = _mm_setzero_si128();
            const __m128i w = _mm_setr_epi8(16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1);
            const __m128i ones = _mm_set1_epi16(1);
            for (; i + 16 <= block; i += 16)
            {
                __m128i v = _mm_loadu_si128((const __m128i *)(const void *)(ptr + i));
                __m128i sad = _mm_sad_epu8(v, zero);
                __m128i ws = _mm_madd_epi16(_mm_maddubs_epi16(v, w), ones);
                mz_uint32 sum = (mz_uint32)_mm_cvtsi128_si32(sad) + (mz_uint32)_mm_extract_epi64(sad, 1);
                mz_uint32 wsum = (mz_uint32)_mm_cvtsi128_si32(ws);
                wsum += (mz_uint32)_mm_extract_epi32(ws, 1);
                wsum += (mz_uint32)_mm_extract_epi32(ws, 2);
                wsum += (mz_uint32)_mm_extract_epi32(ws, 3);
                s2 += 16u * s1 + wsum;
                s1 += sum;
            }
        }
#endif
        for (; i < block; ++i)
        {
            s1 += ptr[i];
            s2 += s1;
        }
        s1 %= 65521u;
        s2 %= 65521u;
        ptr += block;
        buf_len -= block;
    }
    return (s2 << 16) | s1;
}

#endif /* MINIZ_SIMD_H */
