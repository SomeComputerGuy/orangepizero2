# Runner job 44-spi-i2c-target: handoff (DEV, about 12 min incl. three reboots)

Command: `bash harness/research/spi-i2c-target/runner/sit-job.sh`

What it does: datasheet item W33, SPI target (slave) mode in spi-sun6i and I2C target (slave) mode in i2c-mv64xxx.
Job 20 reworked after its two root causes (harness/research/spi-i2c-target/RESULTS.md "Job 20"): (a) the four overlays
were applied in one boot and spi1-target (CS0) and i2c3 (SDA) both use PH5 = header pin 3, so i2c3 lost the pin and
never probed; (b) `echo spidev > .../slave` registers a device the spidev driver never binds (its id table has
"spi-dev", not "spidev"). Now the SPI and the I2C overlay sets boot separately and the spi1-target overlay carries the
spidev handler as its "slave" child (armbian-build commit 85e6dcb38, branch fix/sunxi-h616-spi1-target-spidev).
Job 31 (c27): SPI set all PASS; I2C set 3 FAIL because TWI3 probed but was not /dev/i2c-3: the Zero2 DT had no
i2cN aliases, so overlay-enabled TWIs got dynamic bus numbers. Fixed by armbian-build c6ce58c59
(fix/sunxi-h616-zero-i2c-aliases, i2c0..i2c5 aliases, in c36+). board-sit.sh now reads the bus numbers from sysfs
(adapter under 5002c00.i2c / 5002800.i2c) and checks the numbering separately (W33-i2c-bus-number).
Job 43 (c36): all always-decided items PASS except W33-i2c-slave-eeprom-bind: the overlay's slave-24c02 client 3-1064
existed but stayed unbound. Its uevent is an of: modalias and i2c-slave-eeprom (=m) had only i2c: aliases, so udev never
loaded it. Fixed by armbian-build b7b01b931 (fix/sunxi-i2c-slave-eeprom-of-autoload, OF match table, in c37+; module-only
change, so the c37 Image is byte-identical to c36 and `uname -v` still says #36: that is expected). On a bind FAIL
board-sit.sh now prints `INFO eeprom evidence:` lines (modalias, lsmod, a manual modprobe); the verdict stays FAIL.
Job 44 runs the I2C set first (mandatory) and the SPI set after it as a short sanity check.
Kernel requirement: the newest cumulative kernel (kernel-check/cumulative-kernels.txt last line) must contain BOTH the
commit titled "h616 SPI and TWI target" (03961fad0, in c22+) AND 85e6dcb38 (the overlay fix) AND c6ce58c59 (i2c aliases; its DTB must have
`i2c3 = "/soc/i2c@5002c00"` in /aliases) AND b7b01b931 (its modules-<tag>.tgz must have an `of:` alias for
i2c_slave_eeprom); otherwise the script exits 2 with BLOCKED naming the missing one: report "not ready", not FAIL. Also
required: install-kernel.sh with the DTB step (project repo, this commit) and kernel-check/vdec-serve/
sun50i-h616-orangepi-zero2.dtb.<tag> for that tag (cumul-build.sh stages it).
1. Chunk `wiring`, on the STOCK kernel: `board-sit.sh wiring` drives one end of each loopback jumper position with
   gpiod and reads the other (both levels must follow). Result lines `WIRED_SPI=0|1`, `WIRED_I2C=0|1` in
   `logs/runner/wiring.txt`. No jumpers fitted = 0 = the loopback checks are reported as SKIP (NOT TESTED), never FAIL.
   The jumper positions (26-pin header): SPI 13->23, 11->19, 22<-21, 15->3; I2C 5<->8, 3<->10. They share pin 3, so
   the user fits one set at a time; the script copes with any combination.
2. Chunk `i2c` (mandatory): installs the newest cumulative kernel (harness/research/vdec-perf/install-kernel.sh: Image,
   modules, Zero2 DTB, vdec fallback armed), copies the four host-built overlays (kernel-check/spi-i2c-target/dtbo) to
   `/boot/overlay-user/` as `sit-spi1-target`, `sit-spi-gpio-pc`, `sit-i2c3-slave`, `sit-i2c2-ph`, boots with
   `user_overlays=sit-i2c3-slave sit-i2c2-ph`, verifies the Image and DTB md5, runs `board-sit.sh checks-i2c <i2c>`.
3. Chunk `spi` (short sanity, about 1 min of checks): reboots the trial kernel with
   `user_overlays=sit-spi1-target sit-spi-gpio-pc`, runs `board-sit.sh checks-spi <spi>`.
4. Chunk `restore`: removes the overlays, restores Image/DTB/modules (harness/research/vdec-perf/restore-kernel.sh),
   reboots to the stock image kernel `vmlinuz-7.3.1-edge-sunxi64`.
The script handles the board lock (owner `runner-sit-<epoch>`), a stall watchdog (300 s) and is resumable (chunks in
`logs/runner/state` are skipped). It needs the HTTP server 10.56.0.1:8643 (kernel-check/vdec-serve, used by
install-kernel.sh/ship.sh). No monitor, no other servers. Board tools used: python3, i2c-tools, gpiod (all in the image).

Results: `harness/research/spi-i2c-target/logs/runner/`: `runner.log`, `wiring.txt`, `checks.txt` (all CHECK/INFO
lines of both sets; also `checks-spi.txt`, `checks-i2c.txt`), `dmesg-spi.txt`, `dmesg-i2c.txt`, `board/*` (raw
outputs), `BLOCKED` (only when blocked). Jobs 20/31/43 results are in `logs/job20/`, `logs/job31/`, `logs/job43/`.

Exit codes: 0 = ran and the board is back on the stock kernel (judge with the checks below); 2 = blocked (report
`BLOCKED` + the last 10 lines of runner.log as "not ready"); 1 = setup or lock error.

## Checks (all in checks.txt)
- PASS if `grep -c ROUND-DONE checks.txt` = 2 (one per set).
- Every line `CHECK <item> PASS|FAIL|SKIP <value>` is one result; the summary lists ALL of them verbatim. Exactly 15
  CHECK lines are expected (8 I2C + 7 SPI, one per item below): `grep -c '^CHECK ' checks.txt` must be 15, else
  report the count and the missing item names (a package bug). PASS/FAIL is decided on the line. `SKIP` lines are NOT TESTED (no jumpers), reported as such, never FAIL.
- Overall: PASS if `grep -c 'CHECK .* FAIL' checks.txt` = 0.
- Items without jumpers (always decided): W33-i2c-bus-number, W33-i2c-target-func, W33-i2c-slave-eeprom-bind, W33-i2c-host-with-target,
  W33-spi-target-probe, W33-spi-target-spidev, W33-spi-target-abort, W33-spi-target-unregister,
  W33-spi-target-reregister.
- Items that need jumpers (PASS/FAIL only when wiring.txt says WIRED_*=1, else SKIP): W33-i2c-loopback-16,
  W33-i2c-loopback-200, W33-i2c-slave-eeprom-content, W33-i2c-loopback-i2cset, W33-spi-loopback-16, W33-spi-loopback-100.
- `INFO evidence ...` and `INFO eeprom evidence:` lines (only printed on a failure): copy them exactly into the summary.
- dmesg-spi.txt and dmesg-i2c.txt: copy any line containing `Oops`, `BUG:`, `WARNING`, `Call trace`, `timed out` or
  `already requested` exactly; none expected.
- runner.log: the line starting with `restored:` must show `vmlinuz-7.3.1-edge-sunxi64`, `sun50i-h616-orangepi-zero2.dtb.stock`
  and end with `0` (no sit- overlay left).

The summary must list: the `WIRED_SPI`/`WIRED_I2C` lines, the two `kernel:` and `overlays:` lines from checks.txt (one
per set), every CHECK line, the `INFO adapters:` and `INFO 5002c00.i2c driver:` lines, the `INFO dmesg spi:` and `INFO dmesg i2c:` lines, any `INFO evidence` and `INFO eeprom evidence:` lines, the `restored:`
line, and the dmesg lines above.
