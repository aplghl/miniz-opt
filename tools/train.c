/* tools/train.c — PGO training driver.
 *
 *   usage: train <file>...
 *
 * Runs a broad, realistic compress/decompress/checksum workload over every
 * input so the instrumented profile covers the hot paths. Deliberately trained
 * on a corpus disjoint from the benchmark rows (see scripts/build_opt.sh), and
 * on both dispatch paths (via MINIZ_CPU).
 */
#include "miniz.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char *read_file(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    unsigned char *buf;
    size_t cap = 1 << 20, n = 0;
    if (!f)
        return NULL;
    buf = (unsigned char *)malloc(cap);
    for (;;)
    {
        size_t got;
        if (n == cap)
        {
            cap *= 2;
            buf = (unsigned char *)realloc(buf, cap);
        }
        got = fread(buf + n, 1, cap - n, f);
        n += got;
        if (!got)
            break;
    }
    fclose(f);
    *len = n;
    return buf;
}

static volatile unsigned g_sink;

int main(int argc, char **argv)
{
    static const int levels[] = {1, 3, 6, 9};
    static const int strats[] = {MZ_DEFAULT_STRATEGY, MZ_FILTERED, MZ_RLE, MZ_HUFFMAN_ONLY};
    int fi;
    for (fi = 1; fi < argc; fi++)
    {
        size_t inlen = 0;
        unsigned char *in = read_file(argv[fi], &inlen);
        size_t cap, dcap;
        unsigned char *out, *dec;
        int li, si, rep;
        if (!in)
            continue;
        cap = inlen * 2 + 4096;
        dcap = inlen + 64;
        out = (unsigned char *)malloc(cap);
        dec = (unsigned char *)malloc(dcap);
        for (li = 0; li < 4; li++)
        {
            for (si = 0; si < 4; si++)
            {
                mz_uint flags = tdefl_create_comp_flags_from_zip_params(levels[li], 0, strats[si]);
                size_t n = tdefl_compress_mem_to_mem(out, cap, in, inlen, (int)flags);
                if (n)
                {
                    size_t d = tinfl_decompress_mem_to_mem(dec, dcap, out, n, 0);
                    g_sink += (unsigned)d;
                }
            }
            /* zlib wrapper path (adler32 inside) */
            {
                mz_uint flags = tdefl_create_comp_flags_from_zip_params(levels[li], 15, MZ_DEFAULT_STRATEGY);
                size_t n = tdefl_compress_mem_to_mem(out, cap, in, inlen, (int)flags);
                if (n)
                {
                    size_t d = tinfl_decompress_mem_to_mem(dec, dcap, out, n, TINFL_FLAG_PARSE_ZLIB_HEADER);
                    g_sink += (unsigned)d;
                }
            }
        }
        /* repeat chunks to weight the hot parse path like a real compressor */
        for (rep = 0; rep < 3; rep++)
        {
            mz_uint flags = tdefl_create_comp_flags_from_zip_params(6, 0, MZ_DEFAULT_STRATEGY);
            size_t n = tdefl_compress_mem_to_mem(out, cap, in, inlen, (int)flags);
            if (n)
            {
                g_sink += (unsigned)tinfl_decompress_mem_to_mem(dec, dcap, out, n, 0);
            }
        }
        g_sink += (unsigned)mz_adler32(1, in, inlen);
        g_sink += (unsigned)mz_crc32(0, in, inlen);
        free(in);
        free(out);
        free(dec);
    }
    return (int)(g_sink & 1);
}
