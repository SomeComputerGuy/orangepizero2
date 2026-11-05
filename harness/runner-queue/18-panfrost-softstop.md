# Job 18-panfrost-softstop (TEST, ~65 min in 7 chunks of <= 15 min, resumable, fails fast on an Oops)
Package: harness/research/opencl-fixes/runner/ (script ocl-job.sh, HANDOFF.md, checks 1-9 there).
Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh timeout-fix`
Kernel: newest cumulative kernel, which must contain fix/sunxi-panfrost-softstop-resume at 0b7e3a208 (wt-panfrost-softstop;
e544ddb00 soft-stop/resume + 0b7e3a208 live-status wait = the fix for the panfrost_dequeue_job Oops of c14). Coordinator:
merge 0b7e3a208 into test-cumulative and build/serve it first (c18 or later; c17 is refused). The script blocks (exit 2) if the
installed kernel lacks it. The board must start on the stock image kernel.
Chunks: stress (Integer Ops long16 '/' '%' x2, Thread Dimensions quick_2d x1, the 7 Vulkan spirv_assembly vec4 frag long
jobs x2), then intops, tdim, math-a, math-b, reg, img3d. Exit 3 = Oops seen on the serial log or in dmesg: FAIL, stop,
report logs/runner-timeout-fix/OOPS.
Results: harness/research/opencl-fixes/logs/runner-timeout-fix/. Supersedes held/08-opencl-timeout-fix.md (same package,
old fix check). The held GPU jobs 08, 09, 14, 15 stay held until this job passes (user). Submitted by the panfrost-softstop
agent, 2026-11-05.
