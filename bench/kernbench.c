/* bench/kernbench.c — isolated kernel microbenchmarks.
 *
 * Build twice: candidate SIMD and baseline (candidate with -DMINIZ_NO_SIMD).
 * Emits CSV: kernel,case,ns_per,MBps
 */
#include "miniz.h"
#include "miniz_simd.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_ns(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

static unsigned char A[1 << 16];
static unsigned char B[1 << 16];
static unsigned char C[1 << 16];
static volatile unsigned g_sink;

int main(void)
{
    size_t i;
    const int K = 20000;
    printf("kernel,case,ns_per,MBps\n");

    for (i = 0; i < sizeof(A); i++)
    {
        A[i] = (unsigned char)(i * 31u + (i >> 3));
        B[i] = A[i];
    }

    /* match scan: mismatch at increasing offsets (and a full 258-byte match) */
    {
        static const int poss[] = {3, 7, 15, 31, 63, 127, 255};
        int pi;
        for (pi = 0; pi < (int)(sizeof(poss) / sizeof(poss[0])); pi++)
        {
            int pos = poss[pi];
            int k;
            double t0, dt;
            mz_uint n = (mz_uint)(pos + 1);
            memcpy(B, A, sizeof(A));
            B[0] = (unsigned char)(A[0] ^ 0xFF); /* ensure mismatch reachable */
            memcpy(B, A, (size_t)pos);
            B[pos] = (unsigned char)(A[pos] ^ 0xFF);
            /* warm */
            g_sink += mz_match_len(A, B, n);
            t0 = now_ns();
            for (k = 0; k < K; k++)
                g_sink += mz_match_len(A, B, n);
            dt = now_ns() - t0;
            printf("match_scan,mm%03d,%.4f,%.1f\n", pos, dt / K, (double)pos * K / dt * 1e3);
        }
        {
            int k;
            double t0, dt;
            memcpy(C, A, sizeof(A)); /* distinct pointer, runtime-equal contents */
            g_sink += mz_match_len(A, C, 258);
            t0 = now_ns();
            for (k = 0; k < K; k++)
                g_sink += mz_match_len(A, C, 258);
            dt = now_ns() - t0;
            printf("match_scan,full258,%.4f,%.1f\n", dt / K, 258.0 * K / dt * 1e3);
        }
    }

    /* checksums over 64 KiB */
    {
        int k;
        double t0, dt;
        mz_uint32 a = 0, c = 0;
        g_sink += (unsigned)mz_adler32(1, A, sizeof(A));
        t0 = now_ns();
        for (k = 0; k < 2000; k++)
        {
            a = (mz_uint32)mz_adler32(a | 1u, A, sizeof(A));
            g_sink += a;
        }
        dt = now_ns() - t0;
        printf("adler32,64K,%.4f,%.1f\n", dt / 2000, (double)sizeof(A) * 2000 / dt * 1e3);

        g_sink += (unsigned)mz_crc32(0, A, sizeof(A));
        t0 = now_ns();
        for (k = 0; k < 2000; k++)
        {
            c = (mz_uint32)mz_crc32(c, A, sizeof(A));
            g_sink += c;
        }
        dt = now_ns() - t0;
        printf("crc32,64K,%.4f,%.1f\n", dt / 2000, (double)sizeof(A) * 2000 / dt * 1e3);
    }
    return (int)(g_sink & 1);
}
