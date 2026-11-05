#!/usr/bin/env bash
# Host-side, idempotent: cross-build deqp-vk for the Zero2 from the *Vulkan* CTS release and strip it into
# harness/research/gpu-src/stage-deqp-vk (then run cts-restage.sh).
#
# Why: the first deqp-vk was built from the GLES tag opengl-es-cts-3.2.14.1. In the GL/GLES release branches
# framework/platform/lnx/tcuLnxPlatform.cpp has no getVulkanPlatform(), so tcu::Platform's default throws
# "Vulkan is not supported" (tcuPlatform.cpp:54) before libvulkan is ever dlopen()ed, whatever DEQP_TARGET says.
# Mesa CI builds deqp-vk from vulkan-cts-$DEQP_VK_VERSION (.gitlab-ci/container/build-deqp.sh), same here.
# Target vulkan_headless = Linux platform + VK_EXT_headless_surface WSI (no X11/Wayland libs on the board).
set -euo pipefail
G=$(cd "$(dirname "$0")/../../research/gpu-src" && pwd)
VER=1.4.6.2                                     # Mesa main build-deqp.sh DEQP_VK_VERSION
S=$G/dl-vulkan-cts-$VER/VK-GL-CTS
B=$G/build-deqp-vk-$VER
ST=$G/stage-deqp-vk
export TMPDIR=$G/tmp-build; mkdir -p "$TMPDIR"     # /tmp is a shared tmpfs; gcc temp files go to disk
CMAKE=$G/dl-cmake-4.3.4/root/usr/bin/cmake      # Ubuntu 26.10 cmake debs, unpacked (no sudo)
export LD_LIBRARY_PATH=$G/dl-cmake-4.3.4/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
# Mesa CI vk_cts_commits_to_backport (build-deqp.sh, Mesa main 15bd751e896)
BACKPORTS=(6368ee8503dd9ca46eabfa2df293075d9034a214 541ed0874565d642069c59fe3b31fc42f495a470
	ded32883bf36e5bdf7ac6b0512d5314adc0849d4 b1a2490aaa2cc0429dca4f8efcce7e0d4a9e619f)
# external/fetch_sources.py pins of vulkan-cts-1.4.6.2 (fetched shallow by sha, symlinked as external/<name>/src)
DEPS=(spirv-tools:https://github.com/KhronosGroup/SPIRV-Tools.git:2d14d2e76aa7de72404b17078eda15c20a6a0389
	glslang:https://github.com/KhronosGroup/glslang.git:715c8500e7cd67f2eba9e60e98852a1ed49d2f15
	spirv-headers:https://github.com/KhronosGroup/SPIRV-Headers.git:6dd7ba990830f7c15ac1345ff3b43ef6ffdad216
	amber:https://github.com/google/amber.git:53a4c8934bf7335d27c694e9fdac9ae1b180c0d2
	jsoncpp:https://github.com/open-source-parsers/jsoncpp.git:9059f5cad030ba11d37818847443a53918c327b1)

if [[ ! -d $S/.git ]]; then
	mkdir -p "$S" && git init -q "$S" && git -C "$S" remote add origin https://github.com/KhronosGroup/VK-GL-CTS.git
	git -C "$S" fetch -q --depth 1 origin "vulkan-cts-$VER" && git -C "$S" checkout -q FETCH_HEAD
	git -C "$S" config user.email ci@example.com; git -C "$S" config user.name ci
	mkdir -p "$S/../patches"
	for c in "${BACKPORTS[@]}"; do
		curl -sfL -o "$S/../patches/$c.patch" "https://github.com/KhronosGroup/VK-GL-CTS/commit/$c.patch"
		git -C "$S" am -q --3way "$S/../patches/$c.patch"
	done
fi
for d in "${DEPS[@]}"; do
	IFS=: read -r name proto rest rev <<<"$d"; url=$proto:$rest
	dd=$G/dl-vkcts-$name-${rev:0:12}
	if [[ ! -d $dd/src/.git ]]; then
		mkdir -p "$dd" && git init -q "$dd/src" && git -C "$dd/src" fetch -q --depth 1 "$url" "$rev" && git -C "$dd/src" checkout -q FETCH_HEAD
	fi
	[[ $(git -C "$dd/src" rev-parse HEAD) == "$rev" ]]
	mkdir -p "$S/external/$name" && ln -sfn "$dd/src" "$S/external/$name/src"
done
# zlib 1.2.13 / libpng 1.6.50: same pins (and sha256s) as the GLES tree, already extracted there.
GL=$G/dl-vk-gl-cts-opengl-es-cts-3.2.14.1/VK-GL-CTS/external
for p in zlib libpng; do [[ -d $S/external/$p/src ]] || cp -a "$GL/$p/src" "$S/external/$p/"; done
R=$S/external/renderdoc/src/renderdoc_app.h
[[ -f $R ]] || { mkdir -p "${R%/*}"; curl -sfL -o "$R" https://raw.githubusercontent.com/baldurk/renderdoc/v1.1/renderdoc/api/app/renderdoc_app.h; }
echo "e7b5f0aa5b1b0eadc63a1c624c0ca7f5af133aa857d6a4271b0ef3d0bdb6868e  $R" | sha256sum -c --quiet

"$CMAKE" -S "$S" -B "$B" -G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE="$G/tools/aarch64-board.cmake" \
	-DDEQP_TARGET=vulkan_headless -DCMAKE_BUILD_TYPE=Release -DSELECTED_BUILD_TARGETS=deqp-vk \
	-DDEQP_DISABLE_VK_VIDEO_TESTS=ON > "$B.cmake.log" 2>&1 || { tail -30 "$B.cmake.log"; exit 1; }
grep -q DEQP_SUPPORT_HEADLESS=1 "$B/external/vulkancts/modules/vulkan/CMakeFiles/deqp-vk.dir/flags.make" 2>/dev/null \
	|| grep -rqs DEQP_SUPPORT_HEADLESS=1 "$B/framework/platform/CMakeFiles" || { echo "headless WSI not enabled"; exit 1; }
make -C "$B" -j"$(nproc)" deqp-vk > "$B.build.log" 2>&1 || { tail -40 "$B.build.log"; exit 1; }

# Stage: binary + data the Mesa CI deqp-vk tree keeps (vulkan/ data dir next to the binary), plus the mustpass.
V=$B/external/vulkancts/modules/vulkan
STRIP=$(command -v aarch64-linux-gnu-strip || echo "$G/tools-cross-gxx-15.3.0/root/usr/aarch64-linux-gnu/bin/strip")
keep=$(mktemp -d); cp -a "$ST/mustpass" "$keep/" 2>/dev/null || true
rm -rf "$ST.new"; mkdir -p "$ST.new"
"$STRIP" -o "$ST.new/deqp-vk" "$V/deqp-vk"
cp -a "$V/vulkan" "$ST.new/vulkan" 2>/dev/null || cp -aL "$S/external/vulkancts/data/vulkan" "$ST.new/vulkan"
mkdir -p "$ST.new/mustpass" "$G/vk-mustpass-$VER"
for m in $(< "$S/external/vulkancts/mustpass/main/vk-default.txt"); do cat "$S/external/vulkancts/mustpass/main/$m"; done > "$G/vk-mustpass-$VER/vk-main.txt"   # 3.2 M cases / 416 MB: host only, not staged
# vk-subset: the previous subset restricted to cases that exist in this CTS version (names change between releases).
if [[ -f $keep/mustpass/vk-subset.txt ]]; then
	grep -Fxf "$keep/mustpass/vk-subset.txt" "$G/vk-mustpass-$VER/vk-main.txt" > "$ST.new/mustpass/vk-subset.txt" || true
	echo "vk-subset: $(wc -l < "$keep/mustpass/vk-subset.txt") -> $(wc -l < "$ST.new/mustpass/vk-subset.txt") cases present in $VER"
fi
awk 'NR%100==1' "$G/vk-mustpass-$VER/vk-main.txt" > "$ST.new/mustpass/vk-main-1in100.txt"   # broad deterministic sample
rm -rf "$keep" "$ST.old"; [[ -d $ST ]] && mv "$ST" "$ST.old"; mv "$ST.new" "$ST"; rm -rf "$ST.old"
echo "staged $ST: $(du -sh "$ST" | cut -f1); deqp-vk $(file -b "$ST/deqp-vk" | cut -d, -f1-2)"
