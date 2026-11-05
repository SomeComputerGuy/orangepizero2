#!/bin/bash
# Build the patched v4l2-compliance (patches/v4l-utils on v4l-utils 1.32.0) natively on the board
# with g++ (no meson there) into /root/v4l2c/v4l2-compliance. Usage: build-v4l2c-board.sh <src.tgz>
# src.tgz: config.h include utils/common utils/v4l2-compliance/*.{cpp,h} of the patched tree.
set -e
H=/home/aruni/orangepizero2
base64 -w0 "$1" | $H/harness/ssh.sh 'rm -rf /root/v4l2c; mkdir -p /root/v4l2c; cd /root/v4l2c; base64 -d | tar xz
g++ -O1 -std=gnu++17 -DNO_LIBV4L2 -include config.h -I. -Iinclude -Iutils/common -Iutils/v4l2-compliance \
    -o v4l2-compliance utils/v4l2-compliance/*.cpp -lpthread -lrt && ./v4l2-compliance --version | head -2'
