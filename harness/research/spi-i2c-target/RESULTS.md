# W33: SPI target mode (spi-sun6i) and I2C target mode (i2c-mv64xxx) on the H616

Task state file (AGENT-RULES "Continuity"). Date 2026-11-06. Branch `fix/sunxi-h616-spi-i2c-target`, **commit 03961fad0** on test-cumulative c21
b04527be4 (developed on c20, rebased), pushed to `fork` only. Sources: H616 user manual v1.0 §9.3 (SPI: 9.3.3.5 master/slave, 9.3.6.1 GCR.MODE,
9.3.6.2 TCR, 9.3.6.3-9.3.6.6 IER/ISR/FCR/FSR) and §9.1 (TWI: 9.1.3.5, 9.1.4.1 step 6, 9.1.6.1 TWI_ADDR, 9.1.6.2
TWI_XADDR, 9.1.6.4 TWI_CNTR, 9.1.6.5 status codes 0x60-0xC8). No vendor SPI/TWI driver sources are fetched under
harness/research/*/dl (only cedar/mbus files), so the manual was the reference; the register model is the Marvell one
mv64xxx already drives.

## What changed (armbian-build branch `fix/sunxi-h616-spi-i2c-target`, pushed to `fork`, NOT merged)
One commit "sunxi-7.3: h616 SPI and TWI target (slave) modes" with
- `patches.armbian/spi-sun6i-add-spi-target-mode.patch` (series.conf after the sample-mode patch): `spi-slave` in the
  node -> `devm_spi_alloc_target`; target transfer = PIO, TX FIFO preloaded (zeros for RX only) and refilled on TF_ERQ,
  RX ready level = min(rest, 3/4 FIFO), complete when len bytes are in (full duplex), -EIO on FIFO under/overrun,
  interruptible wait + `target_abort`; set_cs only picks SS_SEL; mclk >= 4x spi-max-frequency (<= 200 MHz);
  GCR written without MASTER/TP at runtime resume; no DMA, no dual/quad for a target. Host mode byte-for-byte the same
  paths (the only host-side changes: `sspi->host` is set before the IRQ is requested, an `is_target` test in
  drain_fifo/set_cs/transfer_one/runtime_resume/probe).
- `patches.armbian/i2c-mv64xxx-add-i2c-target-mode-for-allwinner.patch` (series.conf AFTER
  `drv-i2c-busses-mv64xxx-pin-runtime-pm.patch`, it depends on its context): `has_target` for the sun4i/sun6i
  compatibles; `reg_target`/`unreg_target` (7- and 10-bit own address, TWSIEN|ACK|INTEN armed), target FSM for the
  0x60-0xC8 states driving `i2c_slave_event`, host transfers pre-empted by an own-address match fail with -EAGAIN,
  end-of-host-transfer and hw_init re-arm the listener, I2C_FUNC_SLAVE in functionality. Without a registered target
  nothing changes (INTEN still dropped after a transfer, ADDR/XADDR 0, Marvell variants untouched).
- Overlays (overlay_64 + Makefile): `sun50i-h616-spi1-target` (SPI1 target on PH6/PH7/PH8 + CS0 PH5 = header
  23/19/21/3, alias spi1, handler via `echo spidev > /sys/class/spi_slave/spi1/slave`), `sun50i-h616-spi-gpio-pc`
  (spi-gpio host on PC5/PC6/PC7/PC8 = header 13/11/22/15 with `armbian,spi-dev` spidev, alias spi2 -> /dev/spidev2.0),
  `sun50i-h616-i2c3-ph-slave-eeprom` (TWI3 PH4/PH5 = header 5/3, SoC pull-ups, `slave-24c02` at 0x64).
  SPI0 is the NOR flash (PC0-PC4, not on the header), so there is no second hardware SPI host on the Zero2: the
  loopback host is the bit-banged spi-gpio. Both loopbacks use pin 3 (PH5), so only one set of jumpers at a time.
- Checks: both drivers compile with W=1 (0 warnings) in the configured c20 tree; checkpatch --strict 0/0/0 for both
  patches; dtc (kernel default and -W strict set: only the usual `__overlay__` name notes), fdtoverlay of all three plus
  i2c2-ph on the c20 Zero2 DTB OK; `STAGE=dtbs` of build-kernel.sh with this branch: all patches applied, dtbs exit 0,
  0 dtc warnings, 62 h616 overlays (logs kernel-check/run-spi-i2c-target-{dtbs,patch}.log).
- Kernel config: nothing to change (I2C_SLAVE=y, I2C_SLAVE_EEPROM=m, SPI_SLAVE=y, SPI_SLAVE_TIME/SYSTEM_CONTROL=m,
  SPI_GPIO=y, SPIDEV=y already in linux-sunxi64-edge.config).

## Runner job 20 (harness/runner-queue/20-spi-i2c-target.md -> runner/{sit-job.sh, board-sit.sh, *.py, HANDOFF.md})
Chunk `wiring` on the stock kernel probes the jumper positions with gpiod (drive one end, read the other with the
opposite bias, both levels must follow) -> WIRED_SPI/WIRED_I2C. Chunk `cumul` boots the newest cumulative kernel (must
contain the commit title above, else BLOCKED = not ready) with the four overlays (host-built dtbo in
kernel-check/spi-i2c-target/dtbo, incl. i2c2-ph as the I2C loopback host) and runs: I2C_FUNC_SLAVE on i2c-3,
`3-1064` bound to i2c-slave-eeprom (256 bytes), `i2cdetect -y -r 3` returns with the target armed, SPI target
registered as `/sys/class/spi_slave/spi1`, `echo spidev` gives /dev/spidev1.0, a blocked target transfer ends on
SIGINT, `(null)` removes it. With jumpers: I2C 16/200-byte round trips i2c-2 -> 0x64 + sysfs content + i2cset/i2cget;
SPI 16- and 100-byte full-duplex exchanges spi-gpio <-> spi1 target (100 > 64-byte FIFO exercises refill/levels).
Without jumpers those are `SKIP NOT TESTED`, never FAIL.

## Open / next
- Coordinator: merge `fix/sunxi-h616-spi-i2c-target` into test-cumulative, build, then job 20 runs.
- After job 20: any FAIL names the item (fresh agent, fix on a fix/* branch). If the user fits the jumpers (SPI:
  13->23, 11->19, 22<-21, 15->3; or I2C: 5<->8, 3<->10), rerun the job for the loopback items.
- Not done (out of W33's scope): mv64xxx host-mode DMA; SPI target DMA; general-call address (no Linux consumer).
- Risk notes for the board run: the slave-mode module-clock margin (4x) and the RF_RDY level semantics (assumed level,
  re-checked after re-arming) are from the manual, not vendor code; the loopback test is what verifies them.

## Job 20 (2026-11-06, c24): 4 FAIL, two root causes, both outside the drivers (logs/job20/)
- I2C (3 FAILs: no /dev/i2c-3, no 3-1064, i2cdetect): dmesg `sun50i-h616-pinctrl 300b000.pinctrl: pin PH5 already requested
  by 5011000.spi; cannot claim for 5002c00.i2c` -> `mv64xxx_i2c 5002c00.i2c: error -EINVAL: Error applying setting`. The job
  applied all four overlays in ONE boot, but spi1-target (CS0 = PH5) and i2c3-ph-slave-eeprom (SDA = PH5) share header pin 3
  (documented as "one set of jumpers at a time", yet the package booted both). spi1 probed first and i2c3 lost the pin. Fix:
  sit-job.sh boots the SPI set (sit-spi1-target + sit-spi-gpio-pc) and the I2C set (sit-i2c3-slave + sit-i2c2-ph) separately
  (chunks `spi`, `i2c`); board-sit.sh has `checks-spi` / `checks-i2c` and prints `INFO evidence` lines (dmesg, DT status,
  devices_deferred) when a controller is missing.
- SPI (1 FAIL: no /dev/spidev1.0 after `echo spidev > slave`; spi1.0 was registered, dmesg "registered child spi1.0", no
  error): spi_match_device() uses the driver's spi_device_id table when it has one and never falls back to the driver name;
  spidev_spi_ids has no "spidev" entry (Armbian's is "spi-dev"), so nothing bound. Fix: armbian-build commit **85e6dcb38**
  (branch fix/sunxi-h616-spi1-target-spidev off test-cumulative c26 e64ca7aa2, pushed to fork, NOT merged): the spi1-target
  overlay carries a `slave { compatible = "armbian,spi-dev"; }` child (spi-controller.yaml form for spi-slave controllers;
  the SPI core registers it without reg) so /dev/spidev1.0 exists at boot; the unnecessary #address-cells/#size-cells of the
  fragment dropped; header documents `echo spi-dev` for the sysfs path. dtc default and strict sets clean, fdtoverlay with
  the c26 Zero2 DTB + spi-gpio-pc + the two I2C overlays OK. kernel-check/spi-i2c-target/dtbo/sun50i-h616-spi1-target.dtbo
  rebuilt with the kernel dtc (`scripts/dtc/dtc -@ -I dts -O dtb`, byte-identical method to the kernel build).
  board-sit.sh now checks: spidev1.0 at boot, abort, loopback (or SKIP), `(null)` removes it, `echo spi-dev` brings it back.
- Also: install-kernel.sh now installs the tag's DTB (found by jobs 21/26) and the restore goes through restore-kernel.sh;
  the two sets each verify the DTB md5.
- Re-queued as harness/runner-queue/31-spi-i2c-target.md: requires 03961fad0 AND 85e6dcb38 in the newest cumulative kernel.
