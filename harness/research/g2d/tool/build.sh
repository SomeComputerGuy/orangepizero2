#!/bin/bash
# Build g2dconv for the host (reference generation) and statically for the board (aarch64).
set -e
cd "$(dirname "$0")"; mkdir -p out
gcc -O2 -Wall -Wextra -o out/g2dconv-host g2dconv.c -lm
aarch64-linux-gnu-gcc -O2 -Wall -Wextra -static -o out/g2dconv g2dconv.c -lm
ls -la out/
