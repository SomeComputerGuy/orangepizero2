#!/usr/bin/env bash
# Host-side, idempotent: (re)stage the GPU conformance suites onto the Zero2 at /root/cts and verify them.
#   harness/analysis/gpu/cts-restage.sh            # stage + verify only (starts nothing)
#   harness/analysis/gpu/cts-restage.sh --start    # ...then start the memory-gated `cts` queue unit
# Safe to rerun: a tree is copied only if its sha256 manifest does not verify on the board, and
# apt runs only if a package is missing. Every write is followed by sync, because the board can be
# power-cycled by other agents. Never run this while another agent owns the board.
set -euo pipefail
H=$(cd "$(dirname "$0")/../.." && pwd)            # .../harness
G=$H/research/gpu-src
A=$H/analysis/gpu
SSH="$H/ssh.sh"
STAGE_TREES=(deqp-gles:$G/stage-deqp-gles opencl-cts:$G/stage-opencl-cts deqp-vk:$G/stage-deqp-vk)
LIBCLC=$G/dl-mesa-libclc-22.1.8.3/spirv64-mesa3d-.spv
LIBCLC_SHA=728cdfa747a1857829c104291984964971783a301a62e9468a3d5a4f1750c949

say() { printf '== %s\n' "$*"; }

# 0. Host side: refresh the runner scripts in the stage trees, then build manifests.
[[ -x $G/stage-deqp-vk/deqp-vk ]] || { echo "missing $G/stage-deqp-vk/deqp-vk (run harness/analysis/gpu/build-deqp-vk.sh)"; exit 1; }
echo "$LIBCLC_SHA  $LIBCLC" | sha256sum -c --quiet
install -m 0644 "$A/deqp-run.py" "$G/stage-deqp-gles/deqp-run.py"
install -m 0644 "$A/deqp-run.py" "$G/stage-deqp-vk/deqp-run.py"
install -m 0644 "$A/clcts-run.py" "$G/stage-opencl-cts/clcts-run.py"
for t in "${STAGE_TREES[@]}"; do
	d=${t#*:}
	(cd "$d" && find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256)
done

$SSH 'uname -r; uptime; grep MemAvailable /proc/meminfo; df -h /root | tail -1'
$SSH 'mkdir -p /root/cts/lib /root/cts/mesa-libclc /root/cts/results'

# 1. Suite trees: copy only when the board copy does not verify.
for t in "${STAGE_TREES[@]}"; do
	name=${t%%:*}; d=${t#*:}
	if $SSH "cd /root/cts/$name 2>/dev/null && cmp -s MANIFEST.sha256 - && sha256sum -c --quiet MANIFEST.sha256" < "$d/MANIFEST.sha256" 2>/dev/null; then
		say "$name: already staged and verified"
		continue
	fi
	say "$name: copying $(du -sh "$d" | cut -f1)"
	(cd "$d" && tar -czf - .) | $SSH "rm -rf /root/cts/$name.new && mkdir -p /root/cts/$name.new && tar -xzf - -C /root/cts/$name.new && cd /root/cts/$name.new && sha256sum -c --quiet MANIFEST.sha256 && cd /root/cts && rm -rf /root/cts/$name && mv /root/cts/$name.new /root/cts/$name && sync"
	say "$name: verified on board"
done

# 2. Fixed libclc (bind-mounted into the cts unit only) and the queue script.
if ! $SSH "echo '$LIBCLC_SHA  /root/cts/mesa-libclc/spirv64-mesa3d-.spv' | sha256sum -c --quiet" 2>/dev/null; then
	$SSH 'cat > /root/cts/mesa-libclc/spirv64-mesa3d-.spv.new' < "$LIBCLC"
	$SSH "cd /root/cts/mesa-libclc && echo '$LIBCLC_SHA  spirv64-mesa3d-.spv.new' | sha256sum -c --quiet && mv spirv64-mesa3d-.spv.new spirv64-mesa3d-.spv && sync"
fi
say "libclc: verified"
q_sha=$(sha256sum "$A/run-cts-queue.sh" | cut -d' ' -f1)
$SSH "cat > /root/cts/run-cts-queue.sh && echo '$q_sha  /root/cts/run-cts-queue.sh' | sha256sum -c --quiet && sync" < "$A/run-cts-queue.sh"
say "run-cts-queue.sh: verified"
v_sha=$(sha256sum "$A/run-vk-subset.sh" | cut -d' ' -f1)
$SSH "cat > /root/cts/run-vk-subset.sh && echo '$v_sha  /root/cts/run-vk-subset.sh' | sha256sum -c --quiet && sync" < "$A/run-vk-subset.sh"
say "run-vk-subset.sh: verified"

# 3. Unversioned symlinks that dEQP dlopen()s (the image has no -dev packages).
$SSH 'cd /root/cts/lib && ln -sf /usr/lib/aarch64-linux-gnu/libEGL.so.1 libEGL.so && ln -sf /usr/lib/aarch64-linux-gnu/libGLESv2.so.2 libGLESv2.so && ln -sf /usr/lib/aarch64-linux-gnu/libvulkan.so.1 libvulkan.so && ls -L libEGL.so libGLESv2.so >/dev/null'

# 4. Vulkan packages (in the image from project commit 005aa71; install only if missing).
$SSH 'for p in mesa-vulkan-drivers vulkan-tools; do dpkg -s $p >/dev/null 2>&1 || m="$m $p"; done
	if [ -n "${m:-}" ]; then echo "installing:$m"; DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $m >/dev/null && sync; fi
	test -e /usr/share/vulkan/icd.d/panfrost_icd.json && test -e /usr/lib/aarch64-linux-gnu/libvulkan.so.1'
say "vulkan packages: present"

# 5. Sanity: one short run per API, memory-capped (seconds, not minutes).
$SSH 'export LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless
	cd /root/cts/deqp-gles/gles2 && timeout 60 ./deqp-gles2 --deqp-case="dEQP-GLES2.info.*" --deqp-surface-type=pbuffer --deqp-gl-config-name=rgba8888d24s8ms0 --deqp-surface-width=256 --deqp-surface-height=256 --deqp-visibility=hidden --deqp-log-filename=/tmp/restage.qpa | grep -E "^  Passed"
	cd /root/cts/deqp-vk && VK_DRIVER_FILES=/usr/share/vulkan/icd.d/panfrost_icd.json PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 timeout 60 ./deqp-vk --deqp-case="dEQP-VK.api.smoke.*" --deqp-log-filename=/tmp/restage.qpa | grep -E "^  Passed"
	systemd-run --wait --pipe --collect -q -p MemoryMax=150M -p BindReadOnlyPaths=/root/cts/mesa-libclc/spirv64-mesa3d-.spv:/usr/lib/clc/spirv64-mesa3d-.spv --setenv=RUSTICL_ENABLE=panfrost --working-directory=/root/cts/opencl-cts/test_conformance/basic /root/cts/opencl-cts/test_conformance/basic/test_basic hostptr 2>&1 | grep -E "^(PASSED|FAILED) .* tests"
	rm -f /tmp/restage.qpa'
say "sanity runs: done"

if [[ ${1:-} == --start ]]; then
	$SSH 'systemctl is-active -q cts && { echo "cts already running"; exit 0; }
	systemd-run --unit=cts --collect -p MemoryMax=600M -p MemorySwapMax=64M -p OOMPolicy=continue \
		-p BindReadOnlyPaths=/root/cts/mesa-libclc/spirv64-mesa3d-.spv:/usr/lib/clc/spirv64-mesa3d-.spv \
		sh /root/cts/run-cts-queue.sh'
	say "cts queue started (journalctl -u cts; results in /root/cts/results)"
else
	say "staged; not started (rerun with --start)"
fi
