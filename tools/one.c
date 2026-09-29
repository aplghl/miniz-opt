/* tools/one.c — compress one (file, level, strategy, window) and dump bytes.
 *   usage: one <file> <level> <strategy 0-4> <window 0|15>
 * Used to localize exactness differences per configuration.
 */
#include "miniz.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned char *read_file(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    unsigned char *b;
    size_t cap = 1 << 20, n = 0;
    if (!f) return NULL;
    b = (unsigned char *)malloc(cap);
    for (;;)
    {
        size_t got;
        if (n == cap) { cap *= 2; b = (unsigned char *)realloc(b, cap); }
        got = fread(b + n, 1, cap - n, f);
        n += got;
        if (!got) break;
    }
    fclose(f);
    *len = n;
    return b;
}

int main(int argc, char **argv)
{
    size_t inlen = 0, cap, n;
    unsigned char *in, *out;
    int level, strat, window;
    mz_uint flags;
    if (argc < 5) { fprintf(stderr, "usage: one <file> <level> <strategy> <window>\n"); return 2; }
    in = read_file(argv[1], &inlen);
    if (!in) return 2;
    level = atoi(argv[2]);
    strat = atoi(argv[3]);
    window = atoi(argv[4]);
    cap = inlen * 2 + 4096;
    out = (unsigned char *)malloc(cap);
    flags = tdefl_create_comp_flags_from_zip_params(level, window, strat);
    n = tdefl_compress_mem_to_mem(out, cap, in, inlen, (int)flags);
    fwrite(out, 1, n, stdout);
    return 0;
}
