#!/bin/bash
# host: add panvk (+ panfrost tools) to the native fork build build-host-shim (rusticl + drm-shim stay), asserts ON.
set -e
. /home/aruni/orangepizero2/mesa-work/tools/env-cl.sh
cd $MW; unset BINDGEN_EXTRA_CLANG_ARGS
B=build-host-shim
meson configure $B -Dvulkan-drivers=panfrost -Dtools=drm-shim,panfrost
ninja -C $B
echo BUILD-HOST-VK-DONE
