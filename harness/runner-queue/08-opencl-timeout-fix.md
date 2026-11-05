# Job 06-opencl-timeout-fix
Package: harness/research/opencl-fixes/runner/ (script ocl-job.sh, HANDOFF.md, checks 1-8 there).
Command: `bash harness/research/opencl-fixes/runner/ocl-job.sh timeout-fix`
Kernel: newest cumulative kernel, which must contain fix/sunxi-panfrost-softstop-resume (wt-panfrost-softstop
e544ddb00; coordinator: merge into test-cumulative and build/serve it first, c11 or later). The script blocks (exit 2)
if the installed panfrost module lacks the fix. TEST, ~55 min in 6 chunks of <= 15 min, resumable.
Results: harness/research/opencl-fixes/logs/runner-timeout-fix/. Submitted by the opencl-fixes agent, 2026-11-05.
