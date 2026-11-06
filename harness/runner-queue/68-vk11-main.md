# Job 68-vk11-main (TEST, long: ~16-22 h in rounds of <= 16 min, pausable and resumable)
Package: harness/research/vk11/runner/HANDOFF.md (command `bash harness/research/vk11/runner/vk11-main.sh`, then
`bash harness/research/vk11/runner/vk11-main.sh --check` prints checks 1-9 as PASS/FAIL plus INFO lines).
Kernel: the script installs the newest cumulative kernel itself (c48 b82264f81 at submission, must contain e544ddb00)
with the fallback armed and restores the stock image kernel at the end, at every lock hand-over (automatic when
another session waits, and every 3.5 h) and on pause/block; the board must start on the stock kernel.
Mesa: fork mesa-cl panfrost-opencl-fixes ded6ccea0bc (Vulkan 1.1 on the G31) from mesa-work/build-cl, deployed by the
script to /root/opiz2-mesa/vk3 and checked by md5. Nothing is installed into the system.
Pause: `touch harness/research/vk11/logs/runner/PAUSE` (stops after the current round, exit 4); resume = same command.
Dev turns of other sessions go first automatically (hand-over between rounds).
Results: harness/research/vk11/logs/runner/ (per-case results git-ignored).
Submitted 2026-11-06 by the vk11 coding agent (Vulkan step 2: panvk Vulkan 1.1 on the G31, full vk-main + regression
comparison against job 52 and the 26.2.4 baselines).
