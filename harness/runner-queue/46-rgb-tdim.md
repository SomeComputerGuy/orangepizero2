# Job 46-rgb-tdim (TEST, 1.5-2.5 h in 12 chunks, resumable, fails fast on an Oops)
Package: harness/research/opencl-fixes/runner/ (script ocl-job.sh, checks in HANDOFF-rgbtdim.md).
Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh rgbtdim`
Kernel: newest cumulative (c38+, must contain fa9d166f6; the script checks, installs and restores the stock kernel).
Mesa: deploys mesa-work/build-cl (fork 02df5721016) as /root/opiz2-mesa/cl3 itself; needs job 09's /root/opiz2-mesa/cl2.
Chunks: edgeA edgeB edgeA2 edgeB2 (RGB last-texel repro, old vs new Mesa), ctsA ctsB ctsA2 ctsB2 (CTS 2Darray RGB8 reads),
s32B (CTS 3D RGB32I on the new Mesa), tdim2x tdim3e tdim3i (Thread Dimensions with scheduler tracepoints; the two 3D
chunks may each take up to 32 min).
Results: harness/research/opencl-fixes/logs/runner-rgbtdim/. Follows done/45-panfrost-img3d and done/09-opencl-mesa2.
Submitted by the opencl-rgb agent, 2026-11-06.
