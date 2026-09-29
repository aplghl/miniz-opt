/* harness/consumer/consumer.c — downstream consumer benchmark.
 *
 * Uses the zlib-style API the way a real program would: generate a text-like
 * buffer, compress with mz_compress2, decompress with mz_uncompress, verify.
 * Built once against pristine upstream and once against the prebuilt library;
 * the speedup bounds the drop-in claim.
 */
#include "miniz.h"

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

static const char *k_words[] = {"the", "quick", "brown", "fox", "deflate", "inflate",
                                "miniz", "window", "match", "huffman", "checksum", "stream"};

static void gen(unsigned char *p, size_t n)
{
    uint32_t x = 0x9e3779b9u;
    size_t o = 0;
    while (o < n)
    {
        x ^= x << 13; x ^= x >> 17; x ^= x << 5;
        const char *w = k_words[x % (sizeof(k_words) / sizeof(k_words[0]))];
        size_t l = strlen(w);
        if (o + l + 1 >= n) break;
        memcpy(p + o, w, l);
        o += l;
        p[o++] = (x & 7) ? ' ' : '\n';
    }
    if (o < n) memset(p + o, ' ', n - o);
}

int main(void)
{
    const size_t N = 2u << 20; /* 2 MiB */
    unsigned char *in = malloc(N), *comp = malloc(N * 2), *dec = malloc(N + 64);
    mz_ulong clen = (mz_ulong)(N * 2), dlen = (mz_ulong)(N + 64);
    double t0, dc, dd, bestc = 1e30, bestd = 1e30;
    int r, st;
    gen(in, N);

    for (r = 0; r < 8; r++)
    {
        clen = (mz_ulong)(N * 2);
        t0 = now_ns();
        st = mz_compress2(comp, &clen, in, (mz_ulong)N, 6);
        dc = now_ns() - t0;
        if (st != MZ_OK) { fprintf(stderr, "compress failed\n"); return 1; }
        if (r && dc < bestc) bestc = dc;
    }
    for (r = 0; r < 8; r++)
    {
        dlen = (mz_ulong)(N + 64);
        t0 = now_ns();
        st = mz_uncompress(dec, &dlen, comp, clen);
        dd = now_ns() - t0;
        if (st != MZ_OK || dlen != N || memcmp(dec, in, N) != 0) { fprintf(stderr, "roundtrip failed\n"); return 1; }
        if (r && dd < bestd) bestd = dd;
    }
    printf("consumer,compress,6,%zu,%.1f,%.1f\n", (size_t)clen, bestc, (double)N / bestc * 1e3);
    printf("consumer,decompress,6,%zu,%.1f,%.1f\n", N, bestd, (double)N / bestd * 1e3);
    free(in); free(comp); free(dec);
    return 0;
}
