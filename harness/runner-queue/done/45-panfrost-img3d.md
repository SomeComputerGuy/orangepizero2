# Job 45-panfrost-img3d (TEST, 30-120 min in 10 chunks of <= 14.5 min, resumable, fails fast on an Oops)
Package: harness/research/opencl-fixes/runner/ (script ocl-job.sh, checks in HANDOFF-img3d.md).
Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh img3d`
Kernel: newest cumulative kernel, which must contain fa9d166f6 (fix/sunxi-panfrost-fault-bo-info, merged in
test-cumulative 76bd27766 = c38). The script blocks (exit 2) if the installed kernel lacks it. Board starts on the stock
image kernel; the script restores it.
Chunks: tdim2 / tdim3 (Thread Dimensions quick 2D / 3D under their real names), s32-1..4 (OpenCL-CTS 3D image read
CL_RGB SIGNED_INT32 x4: the job 28 page fault), u32-1..2 (CL_RGB UNSIGNED_INT32), f32-1 (CL_RGB FLOAT), ctl (CL_RGBA
SIGNED_INT32 control). A fault is reported as FAULT with the chunk's dmesg verbatim (`fault bo:` lines).
Results: harness/research/opencl-fixes/logs/runner-img3d/. Follows done/28-panfrost-softstop2. Submitted by the
panfrost-img3d agent, 2026-11-06.
