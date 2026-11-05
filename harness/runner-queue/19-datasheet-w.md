# Job 19-datasheet-w (DEV, ~12 min incl. two reboots)
Package: harness/research/datasheet-w/runner/ (script dsw-job.sh, HANDOFF.md).
Command: `bash harness/research/datasheet-w/runner/dsw-job.sh`
Kernel: newest cumulative kernel (kernel-check/cumulative-kernels.txt, c19 or newer; the script exits 2 + BLOCKED if it predates
the UM-review merges: report "not ready", not FAIL), installed with the vdec fallback armed; the stock kernel is restored at the
end. Three host-built user overlays (kernel-check/datasheet-w/dtbo) go to /boot/overlay-user for the test boot and are removed.
No debs, no wiring, no monitor; HTTP server 10.56.0.1:8643 must be up.
Checks: HANDOFF.md "Checks" (mechanical: ROUND-DONE, every `CHECK <item> PASS|FAIL|SKIP` line, 0 FAIL overall, hd.txt,
`restored:` line). Results: harness/research/datasheet-w/logs/runner/. Submitted 2026-11-05 by the datasheet-w agent.
