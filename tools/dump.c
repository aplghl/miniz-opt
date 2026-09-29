/* tools/dump.c — deterministic differential driver for miniz codec-pair.
 *
 * Reads one input file (or stdin with "-") and emits a deterministic binary
 * record stream on stdout covering:
 *   - adler32 / crc32 over the whole input (several seeds)
 *   - raw DEFLATE + zlib streams at levels 0..10 x strategies
 *     (default, filtered, huffman-only, rle, fixed), single-shot
 *   - decompression of every produced stream (raw and zlib), verified against
 *     the input and re-emitted
 *   - a chunked streaming deflate/inflate round trip through the zlib API
 *
 * The same binary is built against the pristine oracle and the candidate; a
 * byte-for-byte `cmp` of the two outputs is the exact-tier gate. Record layout
 * is little-endian and identical in both builds:
 *     [char tag[4]][u32 payload_len][payload bytes...]
 */
#include "miniz.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static void emit(const char *tag, const void *p, size_t n)
{
    uint32_t len = (uint32_t)n;
    fwrite(tag, 1, 4, stdout);
    fwrite(&len, 1, 4, stdout);
    if (n && p)
        fwrite(p, 1, n, stdout);
}

static unsigned char *read_file(const char *path, size_t *out_len)
{
    FILE *f = (strcmp(path, "-") == 0) ? stdin : fopen(path, "rb");
    size_t cap = 1 << 16, len = 0;
    unsigned char *buf;
    if (!f)
    {
        fprintf(stderr, "dump: cannot open %s\n", path);
        return NULL;
    }
    buf = (unsigned char *)malloc(cap);
    for (;;)
    {
        size_t got;
        if (len == cap)
        {
            cap *= 2;
            buf = (unsigned char *)realloc(buf, cap);
            if (!buf)
            {
                fclose(f);
                return NULL;
            }
        }
        got = fread(buf + len, 1, cap - len, f);
        len += got;
        if (got == 0)
            break;
    }
    if (f != stdin)
        fclose(f);
    *out_len = len;
    return buf;
}

static const int k_levels[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
static const int k_strats[] = {MZ_DEFAULT_STRATEGY, MZ_FILTERED, MZ_HUFFMAN_ONLY, MZ_RLE, MZ_FIXED};
static const char *k_strat_names[] = {"def", "flt", "huf", "rle", "fix"};

static void tag4(char *t, char a, char b, char c, char d)
{
    t[0] = a;
    t[1] = b;
    t[2] = c;
    t[3] = d;
}

int main(int argc, char **argv)
{
    size_t inlen = 0;
    unsigned char *in;
    size_t cap_out, cap_dec;
    unsigned char *out, *dec;
    size_t i, si, li;
    int lv;

    if (argc < 2)
    {
        fprintf(stderr, "usage: dump <file|->\n");
        return 2;
    }
    in = read_file(argv[1], &inlen);
    if (!in)
        return 2;

    cap_out = inlen * 2 + 4096;
    cap_dec = inlen + 64;
    out = (unsigned char *)malloc(cap_out);
    dec = (unsigned char *)malloc(cap_dec);
    if (!out || !dec)
        return 2;

    /* ---- checksums (several seeds) ---- */
    {
        char t[4];
        uint32_t a, c;
        uint32_t seeds[3] = {1u, 0u, 0x12345678u};
        for (i = 0; i < 3; i++)
        {
            a = (uint32_t)mz_adler32((mz_ulong)seeds[i], in, inlen);
            c = (uint32_t)mz_crc32((mz_ulong)seeds[i], in, inlen);
            tag4(t, 'a', 'd', (char)('0' + (int)i), 0);
            emit(t, &a, 4);
            tag4(t, 'c', 'r', (char)('0' + (int)i), 0);
            emit(t, &c, 4);
        }
    }

    /* ---- raw deflate + inflate, by level and strategy ---- */
    for (li = 0; li < sizeof(k_levels) / sizeof(k_levels[0]); li++)
    {
        lv = k_levels[li];
        for (si = 0; si < sizeof(k_strats) / sizeof(k_strats[0]); si++)
        {
            mz_uint flags = tdefl_create_comp_flags_from_zip_params(lv, 0, k_strats[si]);
            size_t n = tdefl_compress_mem_to_mem(out, cap_out, in, inlen, (int)flags);
            char t[4];
            tag4(t, 'r', (char)('A' + lv), k_strat_names[si][0], k_strat_names[si][1]);
            emit(t, out, n);
            if (n)
            {
                size_t d = tinfl_decompress_mem_to_mem(dec, cap_dec, out, n, 0);
                tag4(t, 'D', (char)('A' + lv), k_strat_names[si][0], k_strat_names[si][1]);
                emit(t, dec, d);
            }
        }
    }

    /* ---- zlib-wrapped, by level and strategy (adler inside stream) ---- */
    for (li = 0; li < sizeof(k_levels) / sizeof(k_levels[0]); li++)
    {
        lv = k_levels[li];
        for (si = 0; si < sizeof(k_strats) / sizeof(k_strats[0]); si++)
        {
            mz_uint flags = tdefl_create_comp_flags_from_zip_params(lv, 15, k_strats[si]);
            size_t n = tdefl_compress_mem_to_mem(out, cap_out, in, inlen, (int)flags);
            char t[4];
            tag4(t, 'z', (char)('A' + lv), k_strat_names[si][0], k_strat_names[si][1]);
            emit(t, out, n);
            if (n)
            {
                size_t d = tinfl_decompress_mem_to_mem(dec, cap_dec, out, n, TINFL_FLAG_PARSE_ZLIB_HEADER);
                tag4(t, 'Z', (char)('A' + lv), k_strat_names[si][0], k_strat_names[si][1]);
                emit(t, dec, d);
            }
        }
    }

    /* ---- mz_compress2 / mz_uncompress single-shot zlib API ---- */
    for (li = 0; li < sizeof(k_levels) / sizeof(k_levels[0]); li++)
    {
        mz_ulong clen = (mz_ulong)cap_out, dlen = (mz_ulong)cap_dec;
        int st;
        char t[4];
        lv = k_levels[li];
        memset(out, 0, cap_out);
        st = mz_compress2(out, &clen, in, (mz_ulong)inlen, lv);
        tag4(t, 'm', (char)('A' + lv), 0, 0);
        emit(t, out, (st == MZ_OK) ? (size_t)clen : 0);
        if (st == MZ_OK)
        {
            st = mz_uncompress(dec, &dlen, out, clen);
            tag4(t, 'M', (char)('A' + lv), 0, 0);
            emit(t, dec, (st == MZ_OK) ? (size_t)dlen : 0);
        }
    }

    /* ---- chunked streaming deflate followed by chunked streaming inflate ---- */
    {
        mz_stream s;
        unsigned char cbuf[4096];
        size_t in_ofs = 0, clen = 0;
        int flush, st;
        memset(&s, 0, sizeof(s));
        st = mz_deflateInit2(&s, 6, MZ_DEFLATED, 15, 9, MZ_DEFAULT_STRATEGY);
        if (st == MZ_OK)
        {
            do
            {
                size_t chunk = inlen - in_ofs;
                if (chunk > 777)
                    chunk = 777;
                s.next_in = in + in_ofs;
                s.avail_in = (unsigned int)chunk;
                in_ofs += chunk;
                flush = (in_ofs == inlen) ? MZ_FINISH : MZ_NO_FLUSH;
                do
                {
                    s.next_out = cbuf;
                    s.avail_out = sizeof(cbuf);
                    st = mz_deflate(&s, flush);
                    if (st != MZ_OK && st != MZ_STREAM_END)
                        break;
                    {
                        size_t got = sizeof(cbuf) - s.avail_out;
                        if (clen + got > cap_out)
                            break;
                        memcpy(out + clen, cbuf, got);
                        clen += got;
                    }
                } while (s.avail_out == 0 && st != MZ_STREAM_END);
            } while (in_ofs < inlen && st != MZ_STREAM_END);
            mz_deflateEnd(&s);
        }
        emit("SDL6", out, clen);

        if (clen)
        {
            unsigned char dbuf[4096];
            size_t dlen = 0, ofs = 0;
            memset(&s, 0, sizeof(s));
            st = mz_inflateInit2(&s, 15);
            if (st == MZ_OK)
            {
                do
                {
                    size_t chunk = clen - ofs;
                    if (chunk > 555)
                        chunk = 555;
                    s.next_in = out + ofs;
                    s.avail_in = (unsigned int)chunk;
                    ofs += chunk;
                    do
                    {
                        s.next_out = dbuf;
                        s.avail_out = sizeof(dbuf);
                        st = mz_inflate(&s, MZ_NO_FLUSH);
                        if (st != MZ_OK && st != MZ_STREAM_END && st != MZ_BUF_ERROR)
                            break;
                        {
                            size_t got = sizeof(dbuf) - s.avail_out;
                            if (dlen + got > cap_dec)
                                break;
                            memcpy(dec + dlen, dbuf, got);
                            dlen += got;
                        }
                    } while (s.avail_out == 0 && st != MZ_STREAM_END);
                } while (ofs < clen && st != MZ_STREAM_END);
                mz_inflateEnd(&s);
            }
            emit("SDLd", dec, dlen);
        }
    }

    fflush(stdout);
    free(in);
    free(out);
    free(dec);
    return 0;
}
