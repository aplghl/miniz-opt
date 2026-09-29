/* tools/gen.c — deterministic corpus generator for miniz-opt.
 *
 * usage: gen <outdir>
 *
 * Produces reproducible files spanning the compression regimes the strategy
 * calls out (smooth / textured / random / repetitive), at several sizes, plus a
 * few synthetic "structured" streams. No RNG state depends on time or address.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static uint32_t s_rng = 0x12345678u;
static uint32_t rng(void)
{
    uint32_t x = s_rng;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    s_rng = x;
    return x;
}

static const char *k_words[] = {
    "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "compression",
    "deflate", "inflate", "dictionary", "huffman", "match", "distance", "literal",
    "block", "window", "checksum", "adler", "crc", "stream", "buffer", "archive"};

static void fill(unsigned char *p, size_t n, int regime)
{
    size_t i;
    switch (regime)
    {
    case 0: /* zeros: maximally compressible */
        memset(p, 0, n);
        break;
    case 1: /* repeating short pattern */
        for (i = 0; i < n; i++)
            p[i] = (unsigned char)(i & 3);
        break;
    case 2: /* smooth ramp */
        for (i = 0; i < n; i++)
            p[i] = (unsigned char)(i / 64);
        break;
    case 3: /* english-like text */
    {
        size_t o = 0;
        while (o < n)
        {
            const char *w = k_words[rng() % (sizeof(k_words) / sizeof(k_words[0]))];
            size_t l = strlen(w);
            if (o + l + 1 >= n)
                break;
            memcpy(p + o, w, l);
            o += l;
            p[o++] = (rng() & 7) ? ' ' : '\n';
        }
        if (o < n)
            memset(p + o, ' ', n - o);
        break;
    }
    case 4: /* source-like: repeated token soup with structure */
    {
        for (i = 0; i < n; i++)
        {
            uint32_t r = rng();
            p[i] = (r & 3) ? (unsigned char)("abcdefghijklmnopqrstuvwxyz_={}(); "[ (r >> 8) % 33])
                           : (unsigned char)('\n');
        }
        break;
    }
    case 5: /* random: incompressible */
        for (i = 0; i < n; i += 4)
        {
            uint32_t r = rng();
            memcpy(p + i, &r, (n - i < 4) ? (n - i) : 4);
        }
        break;
    case 6: /* semi-random: random bytes with runs (textured) */
        for (i = 0; i < n;)
        {
            uint32_t r = rng();
            size_t run = 1 + (r & 15);
            if (i + run > n)
                run = n - i;
            memset(p + i, (unsigned char)(r >> 8), run);
            i += run;
        }
        break;
    default: /* mixed: alternating regimes */
        for (i = 0; i < n; i++)
            p[i] = (unsigned char)((i % 4096 < 2048) ? (i & 0xFF) : (rng() & 0xFF));
        break;
    }
}

int main(int argc, char **argv)
{
    const char *dir = (argc > 1) ? argv[1] : "corpus";
    static const size_t sizes[] = {4096, 65536, 1048576, 4194304};
    static const char *rnames[] = {"zeros", "repeat", "ramp", "text", "source", "random", "runs", "mixed"};
    char path[1024];
    int r, si;
    (void)dir;

    for (r = 0; r < 8; r++)
    {
        for (si = 0; si < 4; si++)
        {
            size_t n = sizes[si];
            unsigned char *p = (unsigned char *)malloc(n);
            FILE *f;
            s_rng = 0x12345678u ^ (uint32_t)(r * 2654435761u) ^ (uint32_t)n;
            fill(p, n, r);
            snprintf(path, sizeof(path), "corpus/%s_%zu.bin", rnames[r], n);
            f = fopen(path, "wb");
            if (!f)
            {
                fprintf(stderr, "gen: cannot write %s\n", path);
                return 1;
            }
            fwrite(p, 1, n, f);
            fclose(f);
            free(p);
        }
    }
    printf("generated 32 corpus files in corpus/\n");
    return 0;
}
