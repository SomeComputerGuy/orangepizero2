# Job 70-vk11-fix (TEST, ~1.5-2.5 h in rounds of <= 16 min (part-01: <= 30 min), pausable and resumable)
Package: harness/research/vk11/runner/HANDOFF-fix.md (command `bash harness/research/vk11/runner/vk11-fix.sh`, then
`bash harness/research/vk11/runner/vk11-fix.sh --check` prints checks 1-11 as PASS/FAIL plus INFO lines).
Kernel: the script installs the newest cumulative kernel itself (c48 b82264f81 or newer, must contain e544ddb00) with
the fallback armed and restores the stock image kernel at the end, at every lock hand-over and on pause/block; the
board must start on the stock kernel.
Mesa: fork mesa-cl panfrost-opencl-fixes 4800173ec22 from mesa-work/build-cl, deployed by the script to
/root/opiz2-mesa/vk4 and checked by md5. Nothing is installed into the system.
Pause: `touch harness/research/vk11/logs/runner-fix/PAUSE` (exit 4); resume = same command.
Results: harness/research/vk11/logs/runner-fix/ (per-case results git-ignored).
Submitted 2026-11-07 by the vk11 coding agent (Vulkan step 2, after job 68): reruns every job 68 non-pass case on the
fixed build plus a regression sample (the fix-touched groups, the vk-main 1/100 sample, vk-subset).
