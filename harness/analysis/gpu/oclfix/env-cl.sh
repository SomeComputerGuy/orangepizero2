# source me: env for the 26.2.4-based OpenCL fix build (build-cl, worktree mesa-cl)
. /home/aruni/orangepizero2/mesa-work/tools/env.sh
export PATH=$MW/host-tools-cl/bin:$PATH
export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$MW/sysroot"
