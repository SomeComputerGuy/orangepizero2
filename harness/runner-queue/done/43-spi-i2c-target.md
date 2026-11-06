# Job 43-spi-i2c-target (DEV, ~12 min incl. three reboots) = job 31 rerun (I2C set + SPI sanity)
Package: harness/research/spi-i2c-target/runner/ (script sit-job.sh, board-sit.sh, *.py, HANDOFF.md).
Command: `bash harness/research/spi-i2c-target/runner/sit-job.sh`
Why again: job 31 (c27) SPI set all PASS; I2C set 3 FAIL with "no /dev/i2c-3". Root cause: the Zero2 DT has no i2cN
aliases, so TWI3 (enabled by the sit-i2c3-slave overlay) probed silently but got a dynamic bus number, not 3. Fix:
armbian-build c6ce58c59 (fix/sunxi-h616-zero-i2c-aliases, i2c0..i2c4 = TWI0..4, i2c5 = R_TWI, as the vendor BSP), merged
in test-cumulative 95fa41f2a = c36. board-sit.sh now finds the buses through sysfs and checks the numbering on its own
(W33-i2c-bus-number). The SPI set runs again unchanged as a sanity check.
Kernel: the newest cumulative kernel (c36 or later); it must contain 03961fad0, 85e6dcb38 and c6ce58c59 and its DTB must
have the i2c3 alias. Otherwise the script exits 2 + BLOCKED: report "not ready", not FAIL.
Jumpers optional: without them the loopback items are SKIP = NOT TESTED (never FAIL).
Checks: HANDOFF.md "Checks" (mechanical: 2 ROUND-DONE, every `CHECK <item> PASS|FAIL|SKIP` line verbatim, 0 FAIL overall,
`INFO adapters:` / `INFO 5002c00.i2c driver:` / `INFO evidence` lines verbatim, `restored:` line with the stock kernel,
the .stock DTB and 0 overlays).
Results: harness/research/spi-i2c-target/logs/runner/ (job 31's are in logs/job31/). Submitted 2026-11-06 by the W33 agent.
