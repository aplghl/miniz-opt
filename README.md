# miniz-opt

[![CI](https://github.com/aplghl/miniz-opt/actions/workflows/ci.yml/badge.svg)](https://github.com/aplghl/miniz-opt/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/aplghl/miniz-opt)](https://github.com/aplghl/miniz-opt/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](#license)

A performance fork of [miniz](https://github.com/richgel999/miniz) (v3.1.2,
MIT) that is a **byte-identical drop-in replacement** for the deflate/inflate
codec and its checksums.

- **Upstream base:** `richgel999/miniz` @
  `77d0dce8627735138c51770d1799a1ef48f2117d` (v3.1.2), vendored pristine in
  `upstream/` as the oracle. Per-file SHA-256 in `scripts/oracle_hashes.txt`.
- **License:** MIT, same as upstream.
- **Status:** Phase 0 (foundation) complete; per-kernel SIMD work in progress.
  Baseline differential, ABI, ASan/UBSan, non-vacuous and portability gates are
  green.

The oracle stays untouched. `src/` carries the candidate (currently identical
to upstream pending the first kernel). The public API, structs and ABI are
unchanged (115 exported symbols, verified by `make abi`).

## Results

Stock upstream is compiled the way consumers compile it (`-O2`, default
macros). The fork library is `-O3 -march=x86-64-v2 -ffp-contract=off`. Intel
i7-14700F, clang 23.1.2, WSL2. Reproduce with `make bench-vs-upstream` and
`make kernels`.

| workload | speedup vs upstream `-O2` |
| --- | --- |
| Compression (levels 1/6/9, 16-file regime matrix) | **+21.1%** geomean |
| Decompression | +1.7% (parity; weak rows reported) |
| `crc32` (isolated) | **4.0×** |
| `adler32` (isolated) | **3.8×** |
| Match scan, ≥32-byte mismatches (isolated) | 4.2–15.3× |
| Match scan, <16-byte mismatches | 0.67–0.99× (weak regime; evalue probe filter keeps probes short) |

## Approach

`miniz` has **no SIMD** and defaults to `MINIZ_USE_UNALIGNED_LOADS_AND_STORES=0`
on every platform. The exact-tier changes are:

1. **16-bit unaligned match comparator** in `tdefl_find_match` (byte-identical
   for all levels once level 1 is held on the normal parser via
   `MINIZ_EXACT_LEVEL1`).
2. **SSE2 match-length scan** (`movemask`/`ctz`) for the compare loop.
3. **SSSE3/SSE4.1 `adler32`** (`psadbw` + `pmaddubsw`).
4. **slicing-by-8 `crc32`** (portable, exact).
5. **SSE2 16-byte inflate copy** for non-overlapping matches, as an out-of-line
   helper so the hot overlapping copy loop is untouched.

Every change is *mechanics only*: the encoder's byte stream and the decoder's
bytes are bit-identical to the oracle (`docs/CONFIG.md`). Held-out PGO was
measured and **rejected** (it regressed inflate); see `docs/REJECTED.md`.

## Releases & artifacts

The artifact is a **static library**, not a shared library and not a
header-only bundle. Every [release](https://github.com/aplghl/miniz-opt/releases)
ships **five platform tarballs**, one per target, each built by the release
workflow with an explicit CPU model:

| asset | target |
|---|---|
| `miniz-opt-x86_64-linux-gnu.tar.gz` | Linux, glibc |
| `miniz-opt-x86_64-linux-musl.tar.gz` | Linux, musl |
| `miniz-opt-aarch64-linux-musl.tar.gz` | Linux ARM64 |
| `miniz-opt-x86_64-windows-gnu.tar.gz` | Windows (MinGW-w64) |
| `miniz-opt-aarch64-macos.tar.gz` | macOS ARM64 |

Each tarball has this layout:

```
include/             the unchanged public miniz headers
  miniz.h  miniz_common.h  miniz_tdef.h  miniz_tinfl.h  miniz_zip.h  miniz_export.h
lib/
  libminiz-opt.a     static archive (Windows: lib/miniz-opt.lib)
```

The archive contains the object files for `miniz.c`, `miniz_tdef.c`,
`miniz_tinfl.c`, `miniz_zip.c` compiled together; public symbols are exactly
upstream (115), so it links in place of a normal miniz build with no source
change. It is a regular `ar` archive (`current ar archive`), not an LTO/bitcode
or shared object. Per-file SHA-256 of the pinned upstream oracle is in
`scripts/oracle_hashes.txt`.

### Consuming a release

```sh
tar -xzf miniz-opt-x86_64-linux-gnu.tar.gz -C /opt/miniz-opt
cc -O2 -I /opt/miniz-opt/include myapp.c /opt/miniz-opt/lib/libminiz-opt.a -o myapp
```

```c
#include "miniz.h"        /* declarations only; the library provides the code */
/* mz_compress2(), mz_uncompress(), tdefl_*, tinfl_*, mz_zip_* ... */
```

### Building locally

Local builds use the source tree (no zig) and produce a differently named
archive:

```sh
scripts/build_opt.sh exact            # -> build/lib_exact/libminiz.a  (+ headers)
zig build -Doptimize=ReleaseFast      # -> zig-out/lib/libminiz-opt.a
```

Both are the same code; `libminiz.a` is the `build_opt.sh` name and
`libminiz-opt.a` is the zig/release name. Header-only consumers get the
baseline build — only the linked archive carries the SIMD gain.

## Verifying

```sh
make verify             # differential + dispatch matrix + ABI + oracle integrity
make diff-lib           # differential of the prebuilt archive
make dispatch           # every exact-tier ISA configuration
make portable           # compiler / ISA / C++ / cross-target matrix
make sanitize           # ASan+UBSan
make nonvacuous         # corrupt-on-purpose must FAIL
make asm-audit          # baseline (MINIZ_FORCE_BASE) has no ymm/zmm
make kernels            # isolated kernel speedups -> results/kernels.csv
make bench-vs-upstream  # head-to-head -> results/summary.csv
make consumer           # downstream consumer -> results/consumer.csv
```

## Repository layout

```
upstream/     pristine miniz @ 77d0dce (oracle, never edited)
src/          candidate sources (upstream + guarded SIMD)
tools/        dump.c (differential driver), gen.c (corpus), train.c (PGO)
bench/        bench.c (throughput)
harness/      diff, abi, sanitize, nonvacuous, portable, oracle_integrity, ...
scripts/      env.sh, build_opt.sh, oracle_hashes.txt
docs/         MEASUREMENT.md, CONFIG.md, REJECTED.md, PORT_STATUS.md
results/      CSV claims (see results/README.md)
```

## License

MIT, same as upstream miniz by Rich Geldreich, RAD Game Tools and Valve
Software. This is an unofficial fork and is **not endorsed by the upstream
author**.
