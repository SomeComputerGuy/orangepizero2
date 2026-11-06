# Job 31-spi-i2c-target (DEV, ~12 min incl. three reboots) = job 20 reworked
Package: harness/research/spi-i2c-target/runner/ (script sit-job.sh, board-sit.sh, *.py, HANDOFF.md).
Command: `bash harness/research/spi-i2c-target/runner/sit-job.sh`
Why again: job 20 had 4 FAILs with two root causes, both in the package/overlay, not in the drivers: (a) all four overlays
were applied in one boot and spi1-target (CS0) and i2c3 (SDA) both use PH5 = header pin 3, so i2c3 lost the pin ("pin PH5
already requested by 5011000.spi; cannot claim for 5002c00.i2c") and /dev/i2c-3 never existed (3 FAILs); (b) `echo spidev >
/sys/class/spi_slave/spi1/slave` registers spi1.0 with a modalias the spidev driver does not match (its id table has
"spi-dev"), so /dev/spidev1.0 never appeared (1 FAIL). Now the SPI and I2C overlay sets boot one after the other, and the
spi1-target overlay has the spidev handler as its "slave" child (armbian-build commit 85e6dcb38 on
fix/sunxi-h616-spi1-target-spidev, pushed to fork, unmerged); the host-built dtbo in kernel-check/spi-i2c-target/dtbo was
rebuilt from it with the kernel dtc. The job also uses the new install-kernel.sh (DTB) and restore-kernel.sh.
Kernel: the newest cumulative kernel, which must contain the commit "sunxi-7.3: h616 SPI and TWI target (slave) modes"
(03961fad0, c22+) AND 85e6dcb38 (coordinator: merge fix/sunxi-h616-spi1-target-spidev into test-cumulative and build/serve
the next kernel first). Blocked check (exit 2 + BLOCKED, report "not ready", not FAIL): either commit missing from the newest
cumulative kernel, no Image/DTB for the tag in kernel-check/vdec-serve, dtbo missing or lacking the armbian,spi-dev child, DTB
md5 mismatch after the install.
Jumpers are optional: detected on the stock kernel first; without them the loopback items are SKIP = NOT TESTED (never FAIL).
Checks: HANDOFF.md "Checks" (mechanical: 2 ROUND-DONE, every `CHECK <item> PASS|FAIL|SKIP` line, 0 FAIL overall, `INFO
evidence` lines verbatim, `restored:` line with the stock kernel, the .stock DTB and 0 overlays).
Results: harness/research/spi-i2c-target/logs/runner/ (job 20's are in logs/job20/). Submitted 2026-11-06 by the driver-bringup agent.
