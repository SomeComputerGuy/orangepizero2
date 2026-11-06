# Job 48-gles-advblend (TEST, ~45-60 min in 8 chunks of <= 15 min, resumable; requeue of the blocked job 15)
Package: harness/research/gles-advblend/runner/HANDOFF.md (command
`bash harness/research/gles-advblend/runner/gles-advblend.sh`, checks 1-6 there).
Kernel: any booted kernel (no install, no restore). The script deploys mesa-work/build-cl (fork, contains dc7266d584b)
to /root/opiz2-mesa/gl1. Job 15 was blocked by the deploy check: it looked for lib/dri/libgallium-26.2.4.so, but meson
installs libgallium in lib/ (lib/libgallium-26.2.4.so); the check now uses that path.
Results: harness/research/gles-advblend/logs/runner/. Requeued 2026-11-06.
