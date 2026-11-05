# Job 09-opencl-mesa2 (TEST, ~2 h in 14 chunks of <= 15 min, resumable)
Package: harness/research/opencl-fixes/runner-mesa2/HANDOFF.md (command
`bash harness/research/opencl-fixes/runner-mesa2/ocl-mesa2.sh`, checks 1-8 there).
Kernel: any booted kernel (no install, no restore; stock image kernel expected). The script deploys the fork Mesa build
mesa-work/build-cl (panfrost-opencl-fixes a0a4534b14d) to /root/opiz2-mesa/cl2 itself.
Results: harness/research/opencl-fixes/logs/runner-mesa2/.
Submitted 2026-11-05 by the opencl-mesa2 agent (Mesa-side fixes: samplerless 1Dbuffer reads, enqueue_map_image 3D,
Images Kernel 2D float rerun + regression subset).
