# Job 28-panfrost-softstop2 (TEST, 60-100 min in 9 chunks of <= 15 min, resumable, fails fast on an Oops)
Package: harness/research/opencl-fixes/runner/ (script ocl-job.sh, HANDOFF.md, checks 1-11 there).
Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh softstop2`
Kernel: newest cumulative kernel, which must contain fix/sunxi-panfrost-softstop-budget at e17629bba (wt-panfrost-softstop2;
third patch of the panfrost soft-stop series: 5 s soft-stop budget as in kbase, hard stop, no resume across a GPU reset,
AS leak fix). Coordinator: merge e17629bba into test-cumulative and build/serve it first (c26 or later; c25 is refused). The
script blocks (exit 2) if the installed kernel lacks it. The board must start on the stock image kernel.
Chunks: stress (compute long jobs: Integer Ops long16 '/' '%' x2, Thread Dimensions quick_2d x1), vk (5 short Vulkan frag
long jobs x2, 80 s each), vklong (the 2 count64 frag cases x1, 400 s each), then intops, tdim (quick_2d quick_3d), math-a,
math-b (recip -> half_recip), reg, img3d. Each chunk kills the previous chunk's leftovers, traces panfrost_job_timedout;
dmesg + trace are collected by the host after the chunk. Exit 3 = Oops seen on the serial log or in dmesg: FAIL, stop,
report logs/runner-softstop2/OOPS.
Results: harness/research/opencl-fixes/logs/runner-softstop2/. Supersedes done/18-panfrost-softstop (c25: FAIL, analysed in
impl-opencl-fixes.md). The held GPU jobs 08, 09, 14, 15 stay held until this job passes (user). Submitted by the
panfrost-softstop2 agent, 2026-11-06.
