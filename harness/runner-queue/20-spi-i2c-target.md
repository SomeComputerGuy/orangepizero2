# Job 20-spi-i2c-target (DEV, ~10 min incl. two reboots)
Package: harness/research/spi-i2c-target/runner/ (script sit-job.sh, HANDOFF.md).
Command: `bash harness/research/spi-i2c-target/runner/sit-job.sh`
Kernel: newest cumulative kernel (kernel-check/cumulative-kernels.txt) that contains the commit "sunxi-7.3: h616 SPI and TWI
target (slave) modes" (branch fix/sunxi-h616-spi-i2c-target, to be merged by the coordinator first); the script exits 2 +
BLOCKED if it is missing: report "not ready", not FAIL. Installed with the vdec fallback armed; the stock kernel is restored
at the end. Four host-built user overlays (kernel-check/spi-i2c-target/dtbo) go to /boot/overlay-user for the test boot
and are removed. No debs, no monitor; HTTP server 10.56.0.1:8643 must be up. Jumpers are optional: the script detects
them on the stock kernel first; without them the loopback items are SKIP = NOT TESTED (never FAIL).
Checks: HANDOFF.md "Checks" (mechanical: ROUND-DONE, every `CHECK <item> PASS|FAIL|SKIP` line, 0 FAIL overall,
`restored:` line). Results: harness/research/spi-i2c-target/logs/runner/. Submitted 2026-11-06 by the spi-i2c-target agent.
