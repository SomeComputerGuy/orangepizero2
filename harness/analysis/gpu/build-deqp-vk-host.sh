#!/usr/bin/env bash
# Host-side, idempotent: NATIVE x86_64 deqp-vk from the same vulkan-cts-1.4.6.2 tree that build-deqp-vk.sh cross-builds
# for the board (same externals, same backports). Used with panvk under the panfrost drm-shim (fake G31) to reproduce
# board failures on the host: shader dumps (BIFROST_MESA_DEBUG=shaders), pandecode traces (PANVK_DEBUG=trace), no GPU.
# Run build-deqp-vk.sh first (it fetches the sources); this only configures and builds into build-deqp-vk-host.
set -euo pipefail
G=$(cd "$(dirname "$0")/../../research/gpu-src" && pwd)
VER=1.4.6.2
S=$G/dl-vulkan-cts-$VER/VK-GL-CTS
B=$G/build-deqp-vk-host
export TMPDIR=$G/tmp-build; mkdir -p "$TMPDIR"
CMAKE=$G/dl-cmake-4.3.4/root/usr/bin/cmake
export LD_LIBRARY_PATH=$G/dl-cmake-4.3.4/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
[[ -d $S/.git && -L $S/external/glslang/src ]] || { echo "run build-deqp-vk.sh first (sources)"; exit 1; }
"$CMAKE" -S "$S" -B "$B" -G "Unix Makefiles" -DDEQP_TARGET=vulkan_headless -DCMAKE_BUILD_TYPE=Release \
	-DSELECTED_BUILD_TARGETS=deqp-vk -DDEQP_DISABLE_VK_VIDEO_TESTS=ON \
	-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache > "$B.cmake.log" 2>&1 || { tail -30 "$B.cmake.log"; exit 1; }
make -C "$B" -j"${JOBS:-14}" deqp-vk > "$B.build.log" 2>&1 || { tail -40 "$B.build.log"; exit 1; }
ls -la "$B/external/vulkancts/modules/vulkan/deqp-vk"
echo BUILD-DEQP-VK-HOST-DONE
