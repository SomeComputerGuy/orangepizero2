#!/usr/bin/env bash
# Build the xvidcore 1.3.7 reference decoder (host only, local prefix) for the legacy-decode Xvid GMC checks.
set -euo pipefail
T=/home/aruni/orangepizero2/kernel-check/dl-legacy/xvidcore-1.3.7/xvidcore-1.3.7.tar.gz
B=/home/aruni/orangepizero2/kernel-check/xvidcore-build
echo "abbdcbd39555691dd1c9b4d08f0a031376a3b211652c0d8b3b8aa9be1303ce2d  $T" | sha256sum -c -
rm -rf "$B" && mkdir -p "$B" && tar -xzf "$T" -C "$B"
cd "$B/xvidcore/build/generic"
CC="ccache gcc" ./configure --prefix="$B/prefix" --disable-assembly
make -j"$(nproc)"
make install
ls -l "$B/prefix/lib"/libxvidcore.* && echo "xvidcore built into $B/prefix"
