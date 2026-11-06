# Runner job 20-spi-i2c-target: handoff (DEV, about 10 min incl. two reboots)

Command: `bash harness/research/spi-i2c-target/runner/sit-job.sh`

What it does: datasheet item W33, SPI target (slave) mode in spi-sun6i and I2C target (slave) mode in i2c-mv64xxx
(armbian-build branch `fix/sunxi-h616-spi-i2c-target`, commit title "sunxi-7.3: h616 SPI and TWI target (slave) modes").
1. Chunk `wiring`, on the STOCK kernel: `board-sit.sh wiring` drives one end of each loopback jumper position with
   gpiod and reads the other (both levels must follow). Result lines `WIRED_SPI=0|1`, `WIRED_I2C=0|1` in
   `logs/runner/wiring.txt`. No jumpers fitted = 0 = the loopback checks are reported as SKIP (NOT TESTED), never FAIL.
   The jumper positions (26-pin header): SPI 13->23, 11->19, 22<-21, 15->3; I2C 5<->8, 3<->10. They share pin 3, so
   the user fits one set at a time; the script copes with any combination.
2. Chunk `cumul`: installs the newest cumulative kernel (last line of kernel-check/cumulative-kernels.txt, via
   harness/research/vdec-perf/install-kernel.sh, vdec fallback armed). It must contain the fix commit (the script
   greps the cumulative history for the title above), else it exits 2 with `BLOCKED`: report "not ready", not FAIL.
   Four host-built overlays go to `/boot/overlay-user/` as `sit-spi1-target`, `sit-spi-gpio-pc`, `sit-i2c3-slave`,
   `sit-i2c2-ph` (from kernel-check/spi-i2c-target/dtbo) with a `user_overlays=` line in `/boot/armbianEnv.txt`;
   nothing under `/boot/dtb` is touched. After the reboot `board-sit.sh checks <spi> <i2c>` runs the checks below.
3. Chunk `restore`: removes the overlays and the trial kernel, reboots to the stock image kernel
   `vmlinuz-7.3.1-edge-sunxi64`.
The script handles the board lock (owner `runner-sit-<epoch>`), a stall watchdog (300 s) and is resumable (chunks in
`logs/runner/state` are skipped). It needs the HTTP server 10.56.0.1:8643 (kernel-check/vdec-serve, used by
install-kernel.sh/ship.sh). No monitor, no other servers. Board tools used: python3, i2c-tools, gpiod (all in the image).

Results: `harness/research/spi-i2c-target/logs/runner/`: `runner.log`, `wiring.txt`, `checks.txt` (all CHECK/INFO
lines), `dmesg.txt`, `board/*` (raw outputs), `BLOCKED` (only when blocked).

Exit codes: 0 = ran and the board is back on the stock kernel (judge with the checks below); 2 = blocked (report
`BLOCKED` + the last 10 lines of runner.log as "not ready"); 1 = setup or lock error.

## Checks (all in checks.txt)
- PASS if `grep -c ROUND-DONE checks.txt` = 1.
- Every line `CHECK <item> PASS|FAIL|SKIP <value>` is one result; the summary lists ALL of them verbatim (8 to 13
  lines). PASS/FAIL is decided on the line. `SKIP` lines are NOT TESTED (no jumpers), reported as such, never FAIL.
- Overall: PASS if `grep -c 'CHECK .* FAIL' checks.txt` = 0.
- Items without jumpers (always decided): W33-i2c-target-func, W33-i2c-slave-eeprom-bind, W33-i2c-host-with-target,
  W33-spi-target-probe, W33-spi-target-spidev, W33-spi-target-abort, W33-spi-target-unregister.
- Items that need jumpers (PASS/FAIL only when wiring.txt says WIRED_*=1, else SKIP): W33-i2c-loopback-16,
  W33-i2c-loopback-200, W33-i2c-slave-eeprom-content, W33-i2c-loopback-i2cset, W33-spi-loopback-16, W33-spi-loopback-100.
- dmesg.txt: copy any line containing `Oops`, `BUG:`, `WARNING`, `Call trace` or `timed out` exactly; none expected.
- runner.log: the line starting with `restored:` must show `vmlinuz-7.3.1-edge-sunxi64` and `0` (no sit- overlay left).

The summary must list: the `WIRED_SPI`/`WIRED_I2C` lines, the `kernel:` and `overlays:` lines from checks.txt, every
CHECK line, the `INFO dmesg spi/i2c:` line, the `restored:` line, and the dmesg lines above.
