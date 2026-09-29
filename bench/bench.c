/* bench/bench.c — throughput of the miniz codec, min-of-repeats, ratios only.
 *
 *   usage: bench <file>...
 *   env:   LEVELS=1,6,9  REPS=5  CSV=1
 *
 * Emits CSV rows: file,op,level,in_bytes,out_bytes,ns_best,MBps
 * The same binary is built against the oracle and the candidate; the harness
 * joins the two on (file,op,level) to form speedup ratios. Absolute times are
 * nanoseconds; we never label them cycles.
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

int main(int argc, char **argv)
{
    int levels[16], nlev = 0;
    int reps = 5;
    const char *env;
    int fi;

    env = getenv("REPS");
    if (env)
        reps = atoi(env);
    env = getenv("LEVELS");
    {
        char tmp[128];
        const char *p = env ? env : "1,6,9";
        snprintf(tmp, sizeof(tmp), "%s", p);
        for (char *t = strtok(tmp, ","); t && nlev < 16; t = strtok(NULL, ","))
            levels[nlev++] = atoi(t);
    }
    if (nlev == 0)
    {
        levels[0] = 1; levels[1] = 6; levels[2] = 9; nlev = 3;
    }
    if (argc < 2)
    {
        fprintf(stderr, "usage: bench <file>...\n");
        return 2;
    }

    printf("file,op,level,in_bytes,out_bytes,ns_best,MBps\n");
    for (fi = 1; fi < argc; fi++)
    {
        size_t inlen = 0;
        unsigned char *in = read_file(argv[fi], &inlen);
        size_t cap = inlen * 2 + 4096, dcap = inlen + 64;
        unsigned char *out, *dec;
        int li;
        if (!in)
        {
            fprintf(stderr, "bench: cannot read %s\n", argv[fi]);
            continue;
        }
        out = (unsigned char *)malloc(cap);
        dec = (unsigned char *)malloc(dcap);
        for (li = 0; li < nlev; li++)
        {
            int lv = levels[li];
            mz_uint flags = tdefl_create_comp_flags_from_zip_params(lv, 0, MZ_DEFAULT_STRATEGY);
            size_t clen = 0, dlen = 0;
            double best = 1e30, bestd = 1e30;
            int r;

            for (r = 0; r < reps + 1; r++)
            {
                double t0 = now_ns();
                size_t n = tdefl_compress_mem_to_mem(out, cap, in, inlen, (int)flags);
                double dt = now_ns() - t0;
                if (r == 0)
                    clen = n;
                else if (dt < best)
                    best = dt;
            }
            printf("%s,compress,%d,%zu,%zu,%.1f,%.2f\n", argv[fi], lv, inlen, clen, best,
                   (double)inlen / best * 1e3);

            for (r = 0; r < reps + 1; r++)
            {
                double t0 = now_ns();
                size_t n = tinfl_decompress_mem_to_mem(dec, dcap, out, clen, 0);
                double dt = now_ns() - t0;
                if (r == 0)
                    dlen = n;
                else if (dt < bestd)
                    bestd = dt;
            }
            printf("%s,decompress,%d,%zu,%zu,%.1f,%.2f\n", argv[fi], lv, inlen, dlen, bestd,
                   (double)inlen / bestd * 1e3);
        }

        /* checksum micro-ops (whole buffer) */
        {
            int r;
            double besta = 1e30, bestc = 1e30;
            uint32_t a = 0, c = 0;
            for (r = 0; r < reps + 1; r++)
            {
                double t0 = now_ns();
                a = (uint32_t)mz_adler32(1, in, inlen);
                double dt = now_ns() - t0;
                if (r && dt < besta)
                    besta = dt;
            }
            for (r = 0; r < reps + 1; r++)
            {
                double t0 = now_ns();
                c = (uint32_t)mz_crc32(0, in, inlen);
                double dt = now_ns() - t0;
                if (r && dt < bestc)
                    bestc = dt;
            }
            printf("%s,adler32,0,%zu,%u,%.1f,%.2f\n", argv[fi], inlen, a, besta, (double)inlen / besta * 1e3);
            printf("%s,crc32,0,%zu,%u,%.1f,%.2f\n", argv[fi], inlen, c, bestc, (double)inlen / bestc * 1e3);
        }
        free(in);
        free(out);
        free(dec);
    }
    return 0;
}
