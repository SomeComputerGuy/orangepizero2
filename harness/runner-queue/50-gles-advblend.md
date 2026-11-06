# Job 50-gles-advblend (TEST, ~15-25 min + 2 reboots, 8 chunks of <= 15 min, resumable; follow-up of job 48)
Package: harness/research/gles-advblend/runner/HANDOFF.md (command
`bash harness/research/gles-advblend/runner/gles-advblend.sh`, checks 1-7 there).
Kernel: installs the NEWEST cumulative tag (c38 or later, carries the panfrost soft-stop/resume series) and restores
the stock kernel itself; board must be on the stock kernel at start.
Why: job 48 showed mixedSequence fails because its fragment job outlives the 500 ms watchdog on the stock kernel (the
GPU is reset mid-frame); this job checks it on the kernel that resumes long jobs. The version check of job 48 (literal
git-dc7266d584) is replaced by the commit-ancestry check (`fork: ... (contains dc7266d584b)`).
Results: harness/research/gles-advblend/logs/runner2/. Queued 2026-11-06.
