#!/bin/bash
# host: native glslang (standalone binary) from the CTS-pinned glslang source, for the diagnostic GLSL -> SPIR-V shaders.
set -e
G=/home/aruni/orangepizero2/harness/research/gpu-src
CMAKE=$G/dl-cmake-4.3.4/root/usr/bin/cmake
export LD_LIBRARY_PATH=$G/dl-cmake-4.3.4/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export TMPDIR=$G/tmp-build
S=$G/dl-vkcts-glslang-715c8500e7cd/src; B=$G/build-glslang-host
"$CMAKE" -S $S -B $B -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release -DENABLE_OPT=OFF -DENABLE_GLSLANG_BINARIES=ON \
  -DENABLE_SPVREMAPPER=OFF -DBUILD_SHARED_LIBS=OFF -DGLSLANG_TESTS=OFF -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DALLOW_EXTERNAL_SPIRV_TOOLS=OFF > $B.cmake.log 2>&1 || { tail -20 $B.cmake.log; exit 1; }
make -C $B -j6 glslang-standalone > $B.build.log 2>&1 || { tail -20 $B.build.log; exit 1; }
ls -la $B/StandAlone/glslang; echo BUILD-GLSLANG-DONE
