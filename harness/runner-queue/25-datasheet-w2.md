# Job 25-datasheet-w2 (DEV, ~12 min incl. two reboots)
Package: harness/research/datasheet-w/runner/ (script dsw-job.sh, HANDOFF.md).
Command: `bash harness/research/datasheet-w/runner/dsw-job.sh`
Rerun of 19-datasheet-w. W6 and W31 were test bugs (fixed: an armhf binary reports `uname -m` aarch64 without the
linux32 personality; the autoneg line is now read after link-up and printed whole). W18 "no ahubdam card" was a real
bug: the ahub-dam overlay applied, but the card's probe failed with -22 ("has no playback, no capture"); fixed on
armbian-build fix/sunxi-h616-ahub-dam-aux-card 61fb5e0e2 (fork, for the coordinator to merge into test-cumulative).
Kernel: the newest cumulative kernel; the script exits 2 + BLOCKED unless it contains 61fb5e0e2: report "not ready",
not FAIL. Three host-built user overlays go to /boot/overlay-user for the test boot and are removed; the stock kernel
is restored. HTTP server 10.56.0.1:8643 must be up. Checks: HANDOFF.md "Checks" (ROUND-DONE, every `CHECK <item>
PASS|FAIL|SKIP` line verbatim, 0 FAIL overall, `restored:` line). Results: harness/research/datasheet-w/logs/runner/
(job 19's kept as logs/runner-job19/). Submitted 2026-11-06 by the runner-failures agent.
