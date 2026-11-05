# source me: run host rusticl on the fake G31 (panfrost drm-shim), no GPU needed
. /home/aruni/orangepizero2/mesa-work/tools/env.sh
export LD_PRELOAD=$MW/build-host-shim/src/panfrost/drm-shim/libpanfrost_noop_drm_shim.so
export PAN_GPU_ID=7093
export OCL_ICD_FILENAMES=$MW/build-host-shim/src/gallium/targets/rusticl/libRusticlOpenCL.so.1
export RUSTICL_ENABLE=panfrost
export MESA_SHADER_CACHE_DISABLE=true
