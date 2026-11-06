#!/bin/bash
# Host simulation: run gles32probe + the Arm blob under qemu-aarch64 against kbfake (no GPU), traced by kbtrace.
# Usage: run-sim.sh <workdir> [KBFAKE_SET string] [probe args...]; then kbdecode <workdir>/kbtrace.bin <workdir>/dec
set -u
H=$(cd "$(dirname "$0")/.." && pwd)
R=$(cd "$H/../.." && pwd)
W=$1; SET=${2:-}; shift; shift || true
rm -rf "$W"; mkdir -p "$W/out"
cd "$W"
timeout -k 5 ${SIM_TIMEOUT:-120} env QEMU_LD_PREFIX=/usr/aarch64-linux-gnu LD_LIBRARY_PATH=$R/research/arm-blob/lib \
	QEMU_SET_ENV=LD_PRELOAD=$H/kbtrace.so:$H/hostsim/kbfake.so:$H/blobopt.so \
	KBTRACE_DEV=/dev/null KBTRACE_OUT=$W/kbtrace.bin KBFAKE_SET="$SET" BLOBOPT="${BLOBOPT:-}" BLOBOPT_DEBUG="${BLOBOPT_DEBUG:-}" \
	KBFAKE_GPUPROPS=${KBFAKE_GPUPROPS:-$R/research/arm-blob/traces/runner-j66/files/trace/decoded/gpuprops.bin} \
	PROBE_FB="${PROBE_FB:-}" qemu-aarch64 $H/gles32probe "$W/out" "$@" > "$W/run.log" 2>&1
echo "rc $?" >> "$W/run.log"
