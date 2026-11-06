#!/bin/bash
# Build h264enc-test for the board (static aarch64) against the uAPI headers of the patched kernel tree,
# which carry the stateless H.264 encode controls (not in the host's headers yet).
# Usage: build.sh [kernel tree]   (default: kernel-check/work-venc/linux-7.3.1)
set -e
T=$(cd "$(dirname "$0")" && pwd); H=/home/aruni/orangepizero2
K=${1:-$H/kernel-check/work-venc/linux-7.3.1}
INC=$T/out/include; rm -rf "$INC"; mkdir -p "$INC/linux" "$T/out"
for f in videodev2.h v4l2-controls.h v4l2-common.h media.h; do cp "$K/include/uapi/linux/$f" "$INC/linux/"; done
# What headers_install would do for these: no kernel compiler annotations.
printf '#ifndef _STUB_COMPILER_H\n#define _STUB_COMPILER_H\n#define __user\n#define __force\n#endif\n' > "$INC/linux/compiler.h"
sed -i 's/__attribute_const__//; s/ __user / /g; s/__user //g' "$INC"/linux/*.h
aarch64-linux-gnu-gcc -O2 -Wall -static -I "$INC" -o "$T/out/h264enc-test" "$T/h264enc-test.c"
sha256sum "$T/out/h264enc-test"
