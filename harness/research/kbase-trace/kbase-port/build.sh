#!/bin/bash
# Build bifrost_kbase.ko out of tree against the cumulative test kernel tree (kernel-check/work-cumul, per AGENT-RULES).
# Override with KDIR=<tree> LOCALVERSION=<suffix> for another kernel.
set -e
T=/home/aruni/orangepizero2/kernel-check/kbase-trial
export TMPDIR=$T/tmp; mkdir -p $TMPDIR
K=${KDIR:-/home/aruni/orangepizero2/kernel-check/work-cumul/linux-7.3.1}
cd $T/src/drivers/gpu/arm/bifrost
# Out-of-tree (M=) builds do not depend on vmlinux, so a rebuilt kernel would leave the .ko with BTF distilled from
# the old vmlinux: remove it so modfinal always relinks it and regenerates .BTF/.BTF.base against this tree.
rm -f bifrost_kbase.ko
make KDIR=$K ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CC="ccache aarch64-linux-gnu-gcc" LOCALVERSION=${LOCALVERSION:-} \
     CONFIG_MALI_BIFROST_DEVFREQ=n -j16 "$@" > $T/build.log 2>&1 || { grep -E "error:|ERROR" $T/build.log | head -20; exit 1; }
grep -E "warning:" $T/build.log | grep -v "MIN\|MAX" | head
modinfo -F vermagic bifrost_kbase.ko; ls -la bifrost_kbase.ko
