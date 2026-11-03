# Small board-specific gaps (datasheet W-items, size S/easy M) + netboot reflash tool

Date: 2026-11-03. Branch `fix/sunxi-h616-small-gaps` on `stonking-orangepizero2` cf62ac65a (worktree `wt-small`,
pushed to `fork`, not merged). One commit per item. Kernel scratch/build tree: `kernel-check/work-small/`.
Sources: `docs/datasheet-checklist.md` (W-numbers), H616 User Manual v1.0 (text dump
`kernel-check/work-small/docs/um.txt`), H616 datasheet, Zero2 schematic v1.3 (`kernel-check/scratch/zero2-sch/sch3.txt`),
vendor BSP trees in `kernel-check/dl-upstream/linux-orangepi/` (4.9/5.4/6.1 sun50iw9).

Board use was read-only (no reboot, no kernel install, no driver reload): `/sys`, `/proc`, debugfs reads, a
`sha256sum /dev/mtd0ro` read.

## Summary

| # | Item (W) | Result | Commit | Board test |
|---|---|---|---|---|
| 1 | `CONFIG_COMPAT=y` (W6) | done (config) | `400c85da1` | **pending** board time (static armhf binary) |
| 2 | High-speed timer (W3) | done: Kconfig prompt + config | `c82a0745c` | **pending** (`available_clocksource` lists `hstimer`) |
| 3 | CE PRNG (W4) | **not done on purpose**: upstream removed the crypto_rng PRNG (CVE-2026-80834) | — | done (read-only) |
| 4 | SDIO UHS (W10) | done: DT, Zero2 only | `37a01e7b3` | **pending** (ios timing + WiFi iperf) |
| 5 | SPI dual/quad (W5) | done: spi-sun6i H616 cfg + Zero2 NOR dual read | `b01cc7712` | **pending** (mtd0 sha256 + speed) |
| 6 | S/PDIF + I2S3 overlays (W19/W18) | done, fdtoverlay-checked | `79ef2101f` | **pending user wiring** |
| 7 | Codec DRC controls (W17) | done: switches/enum, default off | `28e0e7bbd` | build-only (needs 13-pin board) |
| 8a | WiFi 32 kHz clock (found here) | done: DT fix | `f58edf3ad` | **pending** (clk_summary) |
| 8b | EMAC jumbo (W31) | max MTU 3712 measured; >3712 needs stmmac work. Jumbo test needs host sudo | — | partial (read-only) |
| 8c | EMAC half duplex (W31) | pending (bounces the link) | — | pending |
| 8d | UART 4 Mbit/s (W32) | not reachable with the clock tree: 1.5 Mbit/s max at APB2 24 MHz, 64 MHz impossible from the APB2 parents | — | pending loopback wiring |
| 8e | RTC osc32k source (W14) | answered: calibrated internal RC (`iosc-32k`), no 32k crystal | — | done (read-only) |

## Item 1: CONFIG_COMPAT (W6)

`linux-sunxi64-edge.config` (and `-current`) are the only Armbian arm64 family configs without `CONFIG_COMPAT=y`:
rockchip64, meson64, mvebu64, uefi-arm64, qcs6490, sophgo-arm64, wdk2023 and sunxi64-legacy all have it, and the
rockchip64/meson64/mvebu64/uefi-arm64 configs also enable `ARMV8_DEPRECATED` + SWP/CP15-barrier/SETEND emulation. No
history of an intentional removal (`git log -S` finds nothing). So Armbian's policy is "on", and sunxi64 looks like
an accidental outlier. The commit adds the same five lines as rockchip64-edge.

Cost: compat syscall/ioctl layers, `KUSER_HELPERS`, signal frames for AArch32. `COMPAT_VDSO` stays off because
Armbian passes no `CROSS_COMPILE_COMPAT` (same as the other families), so 32-bit `clock_gettime` uses the syscall.
Image size delta: see "Build verification". Acceptance test (pending): `file` + run a static armhf busybox
(`busybox-static:armhf` from the Ubuntu archive) on the board: `./busybox uname -m` should print `armv8l`.

## Item 2: high-speed timer (W3)

Why it can't be selected: `drivers/clocksource/Kconfig` has `bool "Sun5i timer driver" if COMPILE_TEST`. Only
`arch/arm/mach-sunxi/Kconfig` (MACH_SUN5I/SUN7I/…) selects it, and `arch/arm64/Kconfig.platforms` `ARCH_SUNXI` selects only
`SUN4I_TIMER`. The driver (`timer-sun5i.c`) already matches `allwinner,sun20i-d1-hstimer`, which the H616 DTSI
node `hstimer@3005000` uses as its fallback, so the node exists and would bind.

Fix, upstream style (new patch `clocksource-sun5i-hstimer-allow-enabling-on-64-bit-sunxi.patch`): make the prompt
visible with `if COMPILE_TEST || ARCH_SUNXI`. This adds no select on arm64, which the arm64 maintainers avoid for
non-essential drivers. Then `CONFIG_SUN5I_HSTIMER=y` in sunxi64-edge. It is harmless as a second time base: clocksource and
clockevent rating 340, below `arch_sys_counter` 400 / arch timer clockevent 450 and the sun4i timer (`sun4i_tick`,
350, which stays the broadcast device). Note: the driver uses only the low 32 bits of the 56-bit counter (mask 32)
and is clocked from `bus-hstimer`. It is not needed for timekeeping (arch timer); it exists to meet the datasheet row.
Acceptance (pending): `cat /sys/devices/system/clocksource/clocksource0/available_clocksource` lists `hstimer`.

## Item 3: crypto engine PRNG (W4): not added

- Hardware: the H616 datasheet/UM lists a 160-bit PRNG in the CE, and the H6 variant had `.prng = CE_ALG_PRNG_V2`.
- Mainline 7.3 no longer has `sun8i-ce-prng.c`, `CRYPTO_DEV_SUN8I_CE_PRNG` or the `.prng` field for any variant
  (the 6.18 BSP and Jernej's 7.2 tree still have it). Eric Biggers, "[PATCH 5/7] crypto: sun8i-ce - Remove
  crypto_rng interface" (series "Finish removing crypto_rng from drivers/crypto/", June 2026,
  https://lkml.iu.edu/2606.1/15890.html) removed it as unused and redundant with hwrng. Its `->generate()` also had
  a use-after-free (interruptible wait without stopping the DMA), and the patch is tagged Fixes/Cc stable
  (CVE-2026-80834). Re-adding it would re-add a removed, CVE-fixed interface that nothing consumes. The
  entropy path that matters is hwrng, which is present (`rng_current = sun8i Crypto Engine TRNG`).
- Verdict: PRNG row = N/A by upstream decision (the hardware has it, Linux deliberately has no crypto_rng user
  interface). Suggest changing the W4 status to "OK (TRNG via hwrng); PRNG intentionally not exposed upstream".
- Missing cipher modes etc. (W29, larger, listed only): AES CTS/CTR/CFB/OFB/CBC-MAC/XTS, DES/3DES CTR and CBC-MAC,
  HMAC-SHA1/SHA256, RSA 512–4096, ECC 160–521. sun8i-ce implements ECB/CBC only (`op_mode`) and plain hashes.

## Item 4: SDIO UHS for the UWE5622 (W10)

- Rail: schematic v1.3 "VCC-PG, WIFI-IO … 1.8V" from BLDO1 (the module's IO is strapped for 1.8 V: "IOa1.8V"
  resistor options). The DT models it as the fixed 1.8 V `vcc-wifi-io` vqmmc. Board now: `ios` = 50 MHz, 4-bit,
  `sd high-speed`, `1.80 V` (read-only check).
- Vendor: the 4.9 BSP Zero2 DT `sdc1` has `max-frequency = 150000000`, `sd-uhs-sdr50; sd-uhs-ddr50; sd-uhs-sdr104;`
  `sdio-used-1v8; sunxi-dis-signal-vol-sw;` plus per-speed delay tables. So the vendor runs this module at UHS.
- Mainline behaviour on a fixed 1.8 V rail: `mmc_sdio_init_card()` asks for S18R. A compliant SDIO 3.0 card that is
  already at 1.8 V answers S18A=0, so no CMD11 is sent, and `sdio_read_cccr()` still reads the UHS bus-speed bits and
  `mmc_sdio_init_uhs_card()` picks SDR104/DDR50/SDR50. If the card reports none, it stays at high speed. sunxi-mmc
  has no `execute_tuning` (the core then skips tuning), which is the risk at 150 MHz.
- Change: Zero2 DT `&mmc1 { max-frequency = <150000000>; sd-uhs-sdr50; sd-uhs-ddr50; sd-uhs-sdr104; }` (Zero2
  only; Zero3 untouched). Commit is marked UNTESTED: acceptance = `ios` shows a UHS timing, WiFi scan +
  iperf3 (impl-wifi-5g.md method) without errors. If unstable, fall back to `max-frequency = <100000000>` or
  drop the commit.

## Item 5: SPI dual/quad (W5)

- H616 UM 9.3.3.7/9.3.3.8 + SPI_BCC (0x38): bit 29 Quad_EN, bit 28 DRM ("dual read mode"), the same bits that
  spi-sun6i programs for R329/D1 (`SUN6I_BURST_CTL_CNT_DRM`/`QUAD_EN`). The H616 also has the H3-style SPI_CCR
  (0x24), so it needs `has_clk_ctl` (R329's cfg has none). Kiselev's 2023 series (R329/D1/T113 dual/quad) says it
  "may also work" on H6/H616 but added no H616 entry.
- Patch `spi-sun6i-add-h616-dual-and-quad-mode-support.patch`: `sun50i_h616_spi_cfg` = H3 cfg + `SPI_RX_DUAL |
  SPI_TX_DUAL | SPI_RX_QUAD | SPI_TX_QUAD`, matched on `allwinner,sun50i-h616-spi`. The DT already carries it with the
  h3 fallback, and the binding already lists it.
- Board: schematic shows only SPI0_CLK/CS0/MOSI/MISO (PC0/PC3/PC2/PC4) on the flash. WP#/HOLD# are not on
  SPI0_WP/SPI0_HOLD (PC15/PC16, PC16 = USB1 VBUS switch). So quad is N/A and dual 1-1-2 works:
  `spi-rx-bus-width = <2>` on the Zero2 flash node (patch `…-orangepi-zero2-spi-nor-dual-read.patch`).
- Side finding: the flash is Macronix `c22015` (SFDP, "generic" name) and spi-nor currently uses opcode **0x03
  READ at 40 MHz** (debugfs `params`: read 0x03, 0 dummy, 1S-1S-1S). Standard READ on this part family is specified
  for a lower clock than FAST_READ (about 33 MHz on the MX25L1606E; check the exact part's datasheet), so
  the dual-read change also moves reads to an SFDP fast opcode with dummy cycles.
- Baseline for the board test: `/dev/mtd0ro` sha256 `711306f6434bee747ab96f911e5de251f87e5442e6ed33b2350cffa5522ee933`,
  2 MiB in 0.52 s (single line). Acceptance (pending): same sha256, `params` shows `1S-1S-2S`, read time about half.

## Item 6: header audio overlays (W19, W18)

New overlays in `overlay_64/` (+ Makefile entries): `sun50i-h616-spdif-out.dtso`, `sun50i-h616-i2s3-ph.dtso`.

| Overlay | Pins (Zero2 26-pin header) | What it enables | Conflicts |
|---|---|---|---|
| `spdif-out` | PH4 = pin 5 (TWI3-SCK net) | mainline `spdif@5093000` (sun4i-spdif, `CONFIG_SND_SUN4I_SPDIF=y`) + simple-audio-card "SPDIF" with `linux,spdif-dit` | `i2c3-ph` (PH4/PH5) |
| `i2s3-ph` | PH5 MCLK = pin 3, PH6 BCLK = 23, PH7 LRCK = 19, PH8 DOUT0 = 21, PH9 DIN0 = 24 | vendor AHUB (`CONFIG_SND_SOC_SUNXI_AHUB=y`) `ahub3_plat` (APBIF2, DMA DRQ 5, tdm_num 3, tx/rx pin 0) + `ahub3_mach` "ahubi2s3", I2S master, 2×32-bit slots, mclk 256 fs, dummy codec. Same values as the vendor 5.4 Zero3 DT | SPI1 / `spidev1_*` (PH6–PH9), `uart2-ph`, `uart2-ph-rts-cts` (PH5–PH8), `i2c3-ph` (PH5), `i2c4-ph` (PH6/PH7) |

Notes: the mainline pinctrl names PH8/PH9 `i2s3_dout0`/`i2s3_din0` (not `i2s3` as in the vendor 6.1 DT), so
the overlay uses three groups. The AHUB plat driver needs a "sleep" pinctrl state, so `gpio_in` is used for that. The AHUB register block is owned by
`ahub_dam_plat` (already okay on the Zero2 for HDMI audio). Header pin numbers per the linux-sunxi Zero2 page
(pin 3 = PH5, pin 24 = PH9), consistent with the schematic nets TWI3/SPI1. S/PDIF and the AHUB share PLL_AUDIO with
HDMI audio, so playing 44.1 kHz and 48 kHz families on two cards at once may be refused (rate constraint).
fdtoverlay results: see "Build verification". Functional tests **pending user hardware**: an S/PDIF optical/coax
transmitter or a logic analyser on pin 5; an I2S DAC, or a DOUT0→DIN0 loopback (pin 21 → pin 24) with
`arecord`/`aplay` on card `ahubi2s3`.

## Item 7: codec DRC controls (W17)

H616 UM 8.4.3.8 + registers 0xF0 (DAC_DAP_CTRL: DDAP_EN 31, DRC_EN 29, HPF_EN 28), 0x108 (DRC_CTRL) and 0x100–0x1BC
(coefficients). The UM reset defaults of the coefficient registers are the same values the vendor 4.9 driver
writes in `dacdrc_config()` (CT 0x06A4D3C0 = −40 dB, Kc 0x00800000 = 2:1, LT 0x01A934F0, ET 0x0BA07291, attack
0x000B77BF, release 0x00FFE1F8, smooth 0x00025600/0x00000F04, …). (The vendor 4.9 code also writes the peak-filter
attack registers twice where the second pair was meant for the RMS registers. Those reset to 0x00012BAF anyway.) The
vendor 5.4 driver just writes DAP_CTL = 0, i.e. it never enables DRC.

Patch `ASoC-sun4i-codec-h616-add-DRC-and-HPF-controls.patch` (H616 component only):
`DAC DRC Playback Switch`, `DAC HPF Playback Switch` (custom put keeps DDAP_EN set while either is on),
`DAC DRC {Limiter,Expander,Noise Detect,Max Gain Limit,Min Gain Limit} Playback Switch`, enum `DAC DRC Level
Detector` (RMS/Peak). Component probe arms the vendor's stage set (DRC_CTRL bits 6,5,4,1,0). DRC and HPF stay off,
so default playback is unchanged. Not done (larger, listed): numeric curve controls. The UM gives T = −dB/6.0206 and
K = 1/n in 8.24 format, but the O (offset) terms must be recomputed together with them, and the UM text does not
give that formula. Build-tested only; a listening test needs the 13-pin expansion board (line-out).

## Item 8: other size-S rows that need no user hardware

**8a. WiFi 32 kHz LPO clock (new finding, fixed).** The orangepi-zero dtsi (Armbian WiFi patch) passes
`clocks = <&rtc 1>; clock-names = "osc32k-out";` to `mmc-pwrseq-simple`, which only requests `"ext_clock"` and
treats -ENOENT as "no clock". On the board, `osc32k-fanout` has enable count 0, so the module never gets the clock.
Schematic: PG10/X32KFOUT = net `AP-CK32KO` to the module. The vendor 4.9 Zero2 DT routes `x32kfout` to the wlan
node. Fix: `ext_clock` + `CLK_OSC32K_FANOUT` in the shared dtsi (also fixes `dtbs_check` for the binding) and
`pinctrl-0 = <&x32clk_fanout_pin>` on the Zero2 only. Upstream `sun50i-h618-orangepi-zero2w.dts` and Armbian's
`sun50i-h313-x96q-lpddr3.dts` have the same `osc32k-out` mistake (not touched). Acceptance (pending): `clk_summary`
shows `osc32k-fanout` enable 1, WiFi/BT up, `verify-board.sh` clean.

**8b. Jumbo frames (W31).** `ip -d link show end0`: `maxmtu 3712`. stmmac sets `max_mtu = JUMBO_LEN` (9000) only
for enhanced descriptors / GMAC4+. dwmac-sun8i is neither, so it gets `SKB_MAX_HEAD(NET_SKB_PAD + NET_IP_ALIGN)`
≈ 3712 with 4 KiB pages, and `plat->maxmtu` can only lower that. Datasheet "up to 16 KB" therefore needs stmmac
multi-buffer RX for the sun8i descriptor format (size M/L, not done). A test of MTU 3712 needs `ip link set end0 mtu`
(bounces the link the other agents use) and the host side `enx68da73af6279` raised from 1500 (sudo). **Pending**:
user runs `sudo ip link set enx68da73af6279 mtu 3712` and grants a board slot, then `ping -M do -s 3684 10.56.0.107`
and iperf3 at MTU 3712.

**8c. Half duplex (W31).** `ethtool end0`: 10/100 Half advertised and supported by the PHY/MAC. A forced
`ethtool -s end0 speed 100 duplex half autoneg off` bounces the link, so it is **pending** a board slot (with the tracked
10/100 test).

**8d. UART 4 Mbit/s (W32).** UARTs are clocked from APB2 = 24 MHz (`clk_summary`). Baud = SCLK/(16·div), so the
maximum today is 1.5 Mbit/s. UM table 9-5 reaches 4 Mbit/s only with SCLK = 64 MHz. APB2_CFG_REG (0x524) parents
are OSC24M, RTC_32K, PSI (200 MHz) and PLL_PERI0(1X) (600 MHz) with M ∈ 1..4 and N ∈ {1,2,4,8}, and no combination
gives 64 MHz (or 48 MHz for 3 Mbit/s). PSI/3 = 66.7 MHz would give 4.17 Mbit/s (+4.2 %, outside UART tolerance).
So 4 Mbit/s needs a non-default PLL_PERI0, which every peripheral shares: N/A in practice, 1.5 Mbit/s max. (James
Hilliard's "clk: sunxi-ng: h616: export the APB2 clock" series only exports the ID for DT `assigned-clocks`.) The
UART5↔UART2 loopback at 1.5 Mbit/s and RS-485 are **pending user wiring** (header pins 8/10 ↔ UART2 on PH5/PH6).

**8e. RTC 32 kHz source (W14).** `clk_summary`: `osc32k` parent `iosc-32k` at exactly 32768 Hz. The schematic has no
32.768 kHz crystal, and `ccu-sun6i-rtc` reports 32768 only when the HOSC calibration (`IOSC_CLK_CALI_SRC_SEL`) is on.
So the datasheet row "32.768 kHz from HOSC-calibrated RC" is in use: OK.

## Build verification

`kernel-check/build-kernel.sh` with `ARMBIAN=wt-small`, `STAGE=all`, ccache (incremental, `work-small/`):
- Patching: `patches applied: 755, failed: 0`.
- `Image modules` and the Zero2 dtb: exit 0, **0 C warnings** (`build.log`).
- `make dtbs`: exit 0. The 17 dtc warnings are all pre-existing (`sun50i-a64-pine64-7inch-lcd.dtso`,
  `sun50i-h5-nanopi-r1s-h5.dts`) and none come from touched files. 57 h616 overlays are built, including the two
  new ones.
- DT_CHECK in the built Zero2 DTB: `spi-rx-bus-width`, `sd-uhs-sdr104`, `ext_clock`, `hstimer@3005000` all present.
- `W=1` rebuild of `drivers/spi/spi-sun6i.o`, `sound/soc/sunxi/sun4i-codec.o`, `drivers/clocksource/timer-sun5i.o`:
  no warnings. checkpatch: clean on the C patches.
- `.config`: `COMPAT=y`, `KUSER_HELPERS=y`, `ARMV8_DEPRECATED=y`, `SWP_EMULATION=y`, `SUN5I_HSTIMER=y`. The build
  includes all vendor/out-of-tree drivers with COMPAT on (no compat_ioctl build errors).
- Image size: 37538304 bytes vs 37321216 for the current board kernel tree (`work-board`): **+212 KiB** (COMPAT +
  hstimer + the rest).
- fdtoverlay against the built `sun50i-h616-orangepi-zero2.dtb` (it has `__symbols__`): `spdif-out` OK
  (`spdif@5093000` okay, `/sound-spdif` + `/spdif-out` nodes), `i2s3-ph` OK (`ahub3_plat` okay, `ahub3_mach`
  `allwinner,sunxi-snd-mach`, `i2s3-ph-pins` PH5/6/7).
- PG10 has exactly one pinctrl user in the Zero2 DTB (`x32clk-fanout-pin`), so the WiFi 32k change conflicts with nothing.

Board tests needing a slot with this kernel (no wiring needed), in one boot:
1. `available_clocksource` lists `hstimer`;
2. `/dev/mtd0ro` sha256 = `711306f6…e933`, debugfs spi-nor params `1S-1S-2S`, read time under 0.52 s;
3. `/sys/kernel/debug/mmc1/ios` timing UHS (SDR104/DDR50/SDR50), WiFi scan + iperf3 clean;
4. `clk_summary` `osc32k-fanout` enable 1, WiFi/BT up;
5. a static armhf busybox runs (`uname -m` → armv8l);
6. `amixer -c H616 Audio Codec controls | grep DRC` lists the new controls;
7. `verify-board.sh` clean.

## Part 2: hands-off reflash over netboot

Files (project repo): `harness/reflash.sh`, `harness/serialcon.py`, `harness/flasher/{init,udhcpc.script,
build-flasher.sh,serve-image.py,selftest.sh}`. Generated files live under `kernel-check/work-flasher/` (git-ignored).

**Flasher** (`build-flasher.sh`, no root): kernel `Image` + `sun50i-h616-orangepi-zero2.dtb` from the newest
`linux-image/dtb-edge-sunxi64` debs. `vmlinuz-*` is a raw arm64 Image, so `booti` takes it as is. The gzip newc
initramfs (about 1 MB) holds busybox + `/init` + `dwmac-sun8i.ko`. That is the only module needed: MMC_SUNXI,
MMC_BLOCK, STMMAC_PLATFORM, REALTEK_PHY, DEVTMPFS, PACKET and RD_GZIP are built in. The script checks `modules.dep`
and fails if a dependency appears.
BusyBox: `busybox-static 1:1.38.0-3ubuntu4` arm64 from `ports.ubuntu.com stonking universe`, fetched by
`apt-get download` with a private apt config (foreign arch not configured on the host, no root). apt checks it
against the signed InRelease (deb sha512 `ccc6a540…ce303` = index). deb sha256
`6a0259f8e963c34245db20235964dfb8dffe92562a65f6722422b1b43c9b1d37`, binary sha256
`a9f8f14d8c306efb255fa7e77f9a408c41f9c90ffc9f05a6915de97ab2bd6123`. Recorded per build in `out/PROVENANCE`.

**/init**: mount proc/sys/devtmpfs, insmod, find the NIC whose device is `5020000.ethernet` (the kernel name is
eth0 without udev, not end0), `udhcpc` (client-id 01:MAC, the same lease identity as U-Boot, so .107), fetch
`/manifest` (IMAGE, uncompressed SHA256, SIZE) and run the target checks. Then `wget | xz -dc | dd of=/dev/mmcblk0 bs=1M
conv=fsync` under `pipefail`, `sync`, `blockdev --flushbufs`, `drop_caches`, `head -c SIZE /dev/mmcblk0 | sha256sum`
== manifest. Then "FLASHER: RESULT OK", `/report?status=ok` to the host, `reboot -f`. Any failure prints
"FLASHER: FAIL …", reports, and drops to a console shell **without rebooting**. `flasher.dryrun=1` does the full
download + decompress + checksum without writing.

**Target safety** (all must pass before a byte is written): the target is the hard-coded `/dev/mmcblk0`, and any
`mtd` path is refused (the SPI NOR is never opened). The sysfs path must go through `4020000.mmc` (SMHC0, the SD
slot). Card type must be `SD`, which counts as the removable check: the MMC core never sets the block
`removable` flag, see `drivers/mmc/core/block.c`, and the board reads `removable=0` for the SD card. The device
must be major 179:0. Size must be 2–256 GiB and exactly `flasher.sectors` (reflash.sh reads it over ssh first:
62333952). The device must not be mounted, and the image must fit.

**Host side**: `serve-image.py` serves only `/manifest`, the one image and `/report` (everything else is 404),
bound to 10.56.0.1:8080. The uncompressed sha256 is cached per image (newest image: SHA256
`ddb10b51009a384eb65dbcf71eccca5948603790ef7de630722b3c646c7a3e6d`, SIZE 3074424832, computed in 19 s).

**reflash.sh real run**: preconditions (TFTP root writable, `/dev/ttyOPIZ2` → ttyUSB1, our `serial-log.py`
running, no stale backup) → build flasher → manifest → SD sectors via ssh → stage `TFTP_ROOT/flasher/*` and write
`pxelinux.cfg/default-arm-sunxi` (old one backed up) → start HTTP server → `systemctl reboot` over ssh (board-power
cycle only with `--power-cycle` when ssh+serial are dead) → `serialcon.py uboot-pxe`: on the U-Boot banner, send
Ctrl-C/space until `=>` (bootdelay is 1 s), then `setenv autoload no; dhcp; setenv serverip 10.56.0.1; setenv
bootfile; pxe get; pxe boot`, and wait for "Starting kernel" → **restore the pxelinux.cfg immediately** (a later
reboot can never re-enter the flasher, even if the SD ends up unbootable; boot order SD→USB→PXE) →
`wait-flasher` → `firstlogin` (local.env credentials, user and password masked in every printed line) →
over the serial root shell: harness pubkey into `/root/.ssh/authorized_keys`, `timedatectl set-timezone Etc/UTC` →
`ssh-keygen -R 10.56.0.107 -f harness/known_hosts` → wait for ssh → `verify-board.sh`.

**Found while writing it (affects netboot-stage.sh too):** U-Boot's `pxe_setup_ctx()` takes its path prefix
from the `bootfile` env (everything up to the last `/`). The networkd hint `BootFilename=pxelinux.cfg/default-arm-sunxi`
from netboot-setup.sh therefore makes `pxe get` fetch `pxelinux.cfg/pxelinux.cfg/…` and the kernel
`pxelinux.cfg/Image`. reflash.sh clears `bootfile` after `dhcp`. Suggested host fix: drop `BootFilename=` from the
drop-in, or have netboot-stage.sh users clear `bootfile` too.

**Recovery**: a failure before the write leaves the SD untouched (reboot = old system). A failure during or after
the write leaves the board in the flasher shell: re-run `reflash.sh` (U-Boot on the SPI NOR is never touched,
and PXE always works). If U-Boot is not interrupted, the board simply boots the old SD system, and the trap restores
the pxelinux.cfg.

**Tests run (no board):**
- `selftest.sh` (real arm64 BusyBox via qemu-aarch64 binfmt, fake sysfs, file as SD, real HTTP server): 17/17.
  Covers write + verify (the written bytes are byte-identical), dry-run writes nothing, refusals (mtd0, mtdblock0,
  eMMC slot 4022000, type SDIO, major 31, too small, too large, sector mismatch, no sysfs, https url) with the target
  unchanged, sha mismatch detected, and host reports received.
- `FULL=1 selftest.sh`: 18/18. The dry run of the real 3.07 GB Armbian image through BusyBox `wget | xz -dc |
  sha256sum` gives RESULT OK sha256 `ddb10b51…3e6d` (= manifest) in 632 s. That time is under qemu user-mode
  emulation; the board runs natively, and there the SD write speed is the limit.
- `reflash.sh --dry-run`: all steps. TFTP fetch of Image/DTB/initrd from the host via `curl tftp://10.56.0.1/`
  gives identical bytes, the HTTP manifest and image (xz magic) are served, and the serial U-Boot sequence and
  first-login rules are printed. The log parser was tested against replayed `serial.log` U-Boot output (banner, `=>`,
  FLASHER lines). The HTTP server binds on 10.56.0.1:8080 (manifest, report, 404 for other paths).
- No qemu-system-aarch64 on the host (and no root to install it), so the initramfs was not booted under full
  system emulation. The cpio was checked by listing it.
- **Not run**: a real reflash (as instructed).
