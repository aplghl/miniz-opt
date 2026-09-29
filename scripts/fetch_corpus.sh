#!/bin/bash
# scripts/fetch_corpus.sh — download and curate a real compression corpus.
#
# Uses the same kernel tarball as upstream's test.sh, then selects a diverse,
# bounded subset (source, headers, docs, binaries, tables) into corpus/real/.
# Idempotent; safe to re-run.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DL="$ROOT/build/downloads"
TAR="$DL/linux-4.8.11.tar.xz"
KROOT="$DL/linux-4.8.11"
DEST="$ROOT/corpus/real"
URL=${KERNEL_URL:-https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.8.11.tar.xz}

mkdir -p "$DL" "$DEST"
if [ ! -f "$TAR" ]; then
    echo "fetching $URL"
    curl -fL --retry 3 -o "$TAR.part" "$URL"
    mv "$TAR.part" "$TAR"
fi
if [ ! -d "$KROOT" ]; then
    echo "extracting..."
    tar -C "$DL" -xf "$TAR"
fi

# Curated diverse picks (relative to the kernel root). Adapted to survive
# minor path differences across kernel versions.
PICKS=(
    "README"
    "COPYING"
    "CREDITS"
    "MAINTAINERS"
    "Makefile"
    "fs/ext4/ext4.h"
    "fs/ext4/inode.c"
    "fs/ext4/namei.c"
    "fs/btrfs/ctree.c"
    "fs/proc/base.c"
    "mm/memory.c"
    "mm/slub.c"
    "kernel/sched/fair.c"
    "kernel/time/timekeeping.c"
    "net/ipv4/tcp_input.c"
    "net/ipv4/tcp_output.c"
    "net/core/skbuff.c"
    "drivers/net/ethernet/intel/e1000e/netdev.c"
    "drivers/gpu/drm/i915/i915_gem.c"
    "crypto/sha256_generic.c"
    "lib/string.c"
    "include/linux/sched.h"
    "include/uapi/linux/if_ether.h"
    "arch/x86/kernel/setup.c"
    "arch/x86/include/asm/processor.h"
    "Documentation/kernel-parameters.txt"
    "Documentation/filesystems/ext4.txt"
    "sound/soc/codecs/wm8994.c"
    "tools/perf/util/symbol.c"
    "scripts/kconfig/menu.c"
)
n=0
for p in "${PICKS[@]}"; do
    if [ -f "$KROOT/$p" ]; then
        flat=$(echo "$p" | tr '/' '_')
        cp "$KROOT/$p" "$DEST/kernel_$flat"
        n=$((n + 1))
    fi
done
echo "curated $n real files into corpus/real/"
du -sh "$DEST" 2>/dev/null || true
