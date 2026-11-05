# source me: run a host GLES program on the fake G31 (panfrost drm-shim), no GPU: descriptors + shader compiles only
. /home/aruni/orangepizero2/mesa-work/tools/env.sh
B=$MW/build-host-shim
export LD_PRELOAD=$B/src/panfrost/drm-shim/libpanfrost_noop_drm_shim.so
export PAN_GPU_ID=7093
export EGL_PLATFORM=surfaceless
export LIBGL_DRIVERS_PATH=$B/src/gallium/targets/dri
export LD_LIBRARY_PATH=$B/src/egl:$B/src/mesa/glapi/es2api:$B/src/mesa/glapi/shared-glapi:$LD_LIBRARY_PATH
export MESA_SHADER_CACHE_DISABLE=true
