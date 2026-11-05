#!/bin/bash
# Build bifrost_kbase.ko out of tree against the image kernel headers (linux-headers-edge-sunxi64 P7cdd).
set -e
T=/home/aruni/orangepizero2/kernel-check/kbase-trial
export TMPDIR=$T/tmp; mkdir -p $TMPDIR
K=$T/hdr/usr/src/linux-headers-7.3.1-edge-sunxi64
cd $T/src/drivers/gpu/arm/bifrost
make KDIR=$K ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache aarch64-linux-gnu-gcc" LOCALVERSION=-edge-sunxi64 \
     CONFIG_MALI_BIFROST_DEVFREQ=n -j16 "$@" > $T/build.log 2>&1 || { grep -E "error:|ERROR" $T/build.log | head -20; exit 1; }
grep -E "warning:" $T/build.log | grep -v "MIN\|MAX" | head
modinfo -F vermagic bifrost_kbase.ko; ls -la bifrost_kbase.ko
