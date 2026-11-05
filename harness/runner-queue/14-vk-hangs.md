# Job 14-vk-hangs (TEST, ~40 min in 10 chunks of <= 15 min, resumable)
Package: harness/research/vk-hangs/runner/HANDOFF.md (command `bash harness/research/vk-hangs/runner/vk-hangs.sh`,
checks 1-9 there).
Kernel: the script installs the newest cumulative kernel itself (install-kernel.sh with the fallback armed, as
ocl-job.sh does; it must carry the panfrost soft-stop/resume patch e544ddb00, c15+; the board must start on the stock
kernel) and restores the stock image kernel at the end and before every lock hand-over; `uname -v` is recorded. The script deploys the fork Mesa build mesa-work/build-cl
(panfrost-opencl-fixes a516f2c3ddc, with b7a705442bd) to /root/opiz2-mesa/vk1 itself, side by side with the system Mesa.
Results: harness/research/vk-hangs/logs/runner/.
Submitted 2026-11-05 by the vk-hangs agent (dEQP-VK subgroupelect / ballot_broadcast "Incomplete job" diagnosis with a
Vulkan compute probe matrix, the 7 spirv_assembly vec4 frag long jobs on the fixed kernel, vk-subset + OpenCL + GLES
regression of the fork).
