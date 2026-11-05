#!/bin/bash
# Configure the aarch64 OpenCL-fix build (rusticl + panfrost) of the mesa-cl worktree (branch panfrost-opencl-fixes,
# based on mesa-26.2.4 = the image's Ubuntu Mesa). Usage: setup-cl.sh <builddir> [extra meson args]
set -e
. /home/aruni/orangepizero2/mesa-work/tools/env-cl.sh
B=$1; shift
cd $MW
meson setup $B mesa-cl --cross-file tools/cross-aarch64-cl.ini --native-file tools/native.ini \
  --prefix=/usr --libdir=lib/aarch64-linux-gnu -Dbuildtype=debugoptimized -Db_ndebug=true \
  -Dgallium-drivers=panfrost -Dvulkan-drivers= -Dplatforms=x11,wayland \
  -Degl=enabled -Dgbm=enabled -Dglvnd=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true -Dglx=dri \
  -Dllvm=enabled -Dshared-llvm=enabled -Dmesa-clc=system -Dprecomp-compiler=system -Dpanfrost-rust=false \
  -Dgallium-rusticl=true -Dvalgrind=disabled -Dlibunwind=disabled -Dbuild-tests=false -Dmesa-clc-bundle-headers=enabled "$@"
