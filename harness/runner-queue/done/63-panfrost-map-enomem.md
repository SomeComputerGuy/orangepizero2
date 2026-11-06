# Job 63-panfrost-map-enomem (TEST, ~25-35 min + 2 reboots, 5 chunks of <= 15 min, resumable)
Package: harness/research/panfrost-map-enomem/runner/HANDOFF.md (command
`bash harness/research/panfrost-map-enomem/runner/map-enomem.sh`, checks 1-10 there).
Kernel: the script installs the NEWEST cumulative tag (c48 or later, must contain a524d09da =
fix/sunxi-panfrost-mmu-map-enomem) and restores the stock kernel itself; the board must be on the stock kernel at
start. It deploys the fork Mesa build mesa-work/build-cl to /root/opiz2-mesa/pme for the OpenCL chunk (md5 checked).
Why: work-list item 7: the 2 dEQP-GLES31 drawelements 1000x1000 drawcount_5000 cases under the memcg limit printed
`WARN panfrost_mmu_map+0xcc` 5x on stock #17; this checks 0 WARN/oops, an error/OOM instead of a hang, and a short
GLES 3.1 + OpenCL regression subset.
Results: harness/research/panfrost-map-enomem/logs/runner/. Queued 2026-11-06.
