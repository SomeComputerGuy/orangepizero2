# Job 52-gpu-invalid-enc (TEST, ~30 min in 9 chunks of <= 15 min, resumable)
Package: harness/research/gpu-invalid-enc/runner/HANDOFF.md (command
`bash harness/research/gpu-invalid-enc/runner/invalid-enc.sh`, checks 1-9 there).
Kernel: the script installs the newest cumulative kernel itself (c38 or later, must contain e544ddb00; install-kernel.sh
with the fallback armed; the board must start on the stock kernel) and restores the stock image kernel at the end and
before every lock hand-over. It deploys the fork Mesa build mesa-work/build-cl (panfrost-opencl-fixes 0e274280595, with
ab1caa7378f) to /root/opiz2-mesa/vk2 itself and checks its md5.
Results: harness/research/gpu-invalid-enc/logs/runner/.
Submitted 2026-11-06 by the gpu-invalid-enc agent (G31 INSTR_INVALID_ENC: WMASK-free ballot for the job-14 subgroup
faults, no A8 texel buffers for the job-09 samplerless CL_A 1Dbuffer fault; probe matrix, subgroup CTS cases, OpenCL
samplerless suites, vk-subset + OpenCL + GLES regression).
