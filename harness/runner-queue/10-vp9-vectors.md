# Job 10-vp9-vectors (TEST, ~20-30 min, 5 chunks of <= 8 min, resumable)
Package: harness/vp9-vectors/HANDOFF.md (command `bash harness/vp9-vectors/run-job.sh`, checks 0-6 there).
Kernel: newest cumulative (c14 0324a5d4b or later; contains f8be54bac = fix/sunxi-cedrus-vp9-inter-resize since c10),
installed and restored by the script. Pre-flight: one known-good vector must decode or the script exits 2 with
logs/runner/BLOCKED (report it verbatim, no checks then). Results: harness/vp9-vectors/logs/runner/.
Rerun of job 04 (its FAIL was the package: result tokens + stall watchdog, see HANDOFF "History"; logs/job04-c13/).
Submitted 2026-11-05 by the vp9-vectors-rerun agent.
