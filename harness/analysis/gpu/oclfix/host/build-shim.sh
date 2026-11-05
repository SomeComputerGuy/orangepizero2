#!/bin/bash
# host: native x86_64 build of the fork (mesa-cl) with rusticl + panfrost + drm-shim, asserts ON, for offline
# shader compiles with the real rusticl pipeline (PAN_GPU_ID=7093 panfrost_noop drm-shim). No board needed.
set -e
. /home/aruni/orangepizero2/mesa-work/tools/env-cl.sh
cd $MW; unset BINDGEN_EXTRA_CLANG_ARGS
B=build-host-shim
[ -f $B/build.ninja ] || meson setup $B mesa-cl --native-file tools/native.ini -Dbuildtype=debugoptimized -Db_ndebug=false \
  -Dgallium-drivers=panfrost -Dvulkan-drivers= -Dplatforms= -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false \
  -Dgles1=disabled -Dgles2=disabled -Dllvm=enabled -Dshared-llvm=enabled -Dmesa-clc=system -Dprecomp-compiler=system \
  -Dgallium-rusticl=true -Dtools=drm-shim -Dpanfrost-rust=false -Dvalgrind=disabled -Dlibunwind=disabled \
  -Dbuild-tests=false -Dzstd=disabled -Dexpat=disabled -Dmesa-clc-bundle-headers=enabled
ninja -C $B src/gallium/targets/rusticl/libRusticlOpenCL.so.1.0.0 src/panfrost/drm-shim/libpanfrost_noop_drm_shim.so
echo BUILD-SHIM-DONE
