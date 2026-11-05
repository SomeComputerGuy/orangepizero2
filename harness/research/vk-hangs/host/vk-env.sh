# source me: host panvk (fork build-host-shim, asserts on) on the fake G31 (panfrost noop drm-shim), no GPU needed.
. /home/aruni/orangepizero2/mesa-work/tools/env.sh
export LD_PRELOAD=$MW/build-host-shim/src/panfrost/drm-shim/libpanfrost_noop_drm_shim.so
export PAN_GPU_ID=7093
export VK_DRIVER_FILES=/home/aruni/orangepizero2/harness/research/vk-hangs/host/panfrost_icd.json
export VK_ICD_FILENAMES=$VK_DRIVER_FILES
export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 MESA_VK_VERSION_OVERRIDE=1.3
export MESA_SHADER_CACHE_DISABLE=true
