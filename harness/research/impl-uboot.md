# U-Boot (Orange Pi Zero2 / H616) — implementation report

Worktree `/home/aruni/orangepizero2/wt-uboot` (Armbian build framework, base `27a7f72`).
U-Boot v2026.10 + `patch/u-boot/v2026.10-sunxi64`, defconfig `orangepi_zero2_defconfig`,
TF-A `lts-v2.14.11` (`PLAT=sun50i_h616 DEBUG=1 bl31`). Nothing pushed. Board untouched.

## Branches (all from 27a7f72, one per item) and the linear integration branch

| branch | commit | content |
|---|---|---|
| `sunxi/uboot-host-tools-openssl4` | c2de4e6 | cherry-pick of 0f30781 (`tools-rsa-sign-openssl4-engine-stubs.patch`), prerequisite to build on this host |
| `sunxi/uboot-h616-spl-rsb` (item 1) | 1c66bd7 | `sunxi-h616-rsb-pmic-bus.patch` (generic H616 RSB support in SPL) + `board_orangepizero2/0001-…use-rsb-for-the-axp305-in-spl.patch` (defconfig) |
| `sunxi/uboot-env-nowhere` (item 2) | de8e092 | `board_orangepizero2/0002-…environment-is-nowhere.patch` |
| `sunxi/uboot-spi-nor` (item 3) | b2471dd | `board_orangepizero2/0003-…spi-nor-flash-ids.patch`, `write_uboot_platform_mtd()` in `sunxi64_common.inc`, README section |
| `sunxi/uboot-usb-boot` (items 3/4) | 2167a1d, facf2f2 | `board_orangepizero2/0004-…no-usb-ether-gadget.patch`, `0005-dts-…enable-expansion-board-usb-ports.patch`; then `usb-hub-yield-during-port-debounce.patch` + `0006-…scan-usb-buses-in-parallel.patch` (UTHREAD) |
| `sunxi/uboot-bootscript-recovery` (round 3) | cfc5f77 | `sunxi-export-boot-source-env.patch` (U-Boot exports `${boot_source}`), `config/bootscripts/boot-sun50i-next.cmd`: SoC-correct boot-source report + defaults for manual sourcing |
| `fix/uboot-sunxi-ce-rng-kaslr` (round 4) | 83ebfc1 | `clk-sunxi-add-h6-h616-ce-gates-and-reset.patch` (upstream v9 series, J. Hilliard), `rng-add-allwinner-sun8i-ce-trng-driver.patch` (new DM_RNG driver), `sunxi-board-rng-seed-from-dm-rng.patch`, `board_orangepizero2/0007-…enable-dm-rng-for-kaslr-seed.patch` |
| **`wt-uboot-integration`** | 27a7f72 → c2de4e6 → 6b7a803 → 24e11b8 → 31ec259 → 32692ca → 9394e96 → 3ac64a0 → fc0a8d8 | linear, all of the above |

Every topic branch applies standalone and the integration set applies in Armbian's
LC_ALL=C name order (`board_orangepizero2/000N-*` sort before the top-level `sunxi-*`
patches); verified with `STAGE=patch kernel-check/build-uboot.sh` per branch
(13/12/12/15/13/15 patches, 0 failures; integration 25/25).

## Build (rootless, cached): `kernel-check/build-uboot.sh`

Mirrors `lib/functions/compilation/uboot.sh`: shallow clone of U-Boot from the Armbian
bare cache (`cache/git-bare/u-boot`, root-owned, read via `-c safe.directory`), TF-A from
`cache/sources/arm-trusted-firmware/lts-v2.14.11`, patches applied exactly like
`patching.sh` (`patch --batch -p1 -N`, create-file cleanup, name order, failure report in
`work-uboot/patch-failures.txt`), defconfig + `BOOTDELAY=1` + LOCALVERSION tweaks,
`make BL31=… BINMAN_ALLOW_MISSING=1`, out-of-tree build dir so the source can be reset and
re-patched while objects stay incremental; everything through ccache. Options:
`STAGE=patch|all`, `CFG_CHECK="CONFIG_X=y …"`, `ARMBIAN=<tree>`, `ATF_REBUILD=1`.
Full build from cold ccache ≈ 70 s, repatched rebuild ≈ 30 s.

Baseline (base + OpenSSL patch) reproduces Armbian's artifact byte-for-byte in size:
`u-boot-sunxi-with-spl.bin` 904369 bytes (SPL 40960, BL31 53364).

Integration result (`kernel-check/work-uboot/out/`, sha256 in `.sha256` next to it):

| file | bytes |
|---|---|
| `spl/sunxi-spl.bin` | 40960 (SPL_MAX_SIZE 0xbfa0 = 49056) |
| `u-boot-nodtb.bin` | 763560 (was 772704; RNDIS gadget gone, uthread + CE TRNG driver added) |
| `u-boot.dtb` | 35336 |
| `bl31.bin` | 53364 |
| **`u-boot-sunxi-with-spl.bin`** | **895209 = 874 KiB** — fits the 2 MiB SPI NOR with 1.1 MiB spare; sha256 `44dffad841c50bc6f26c33f422a1ccb1c2eb38bab8507c160aa3ebf9f81dc7e6` (round 4, CE TRNG + kaslr/rng-seed; round 3 886609 B / 217b8926… boot_source export; round 2 e9776c2c… parallel USB scan; round 1 886377 B / ffa022a5…) |

`CFG_CHECK` confirmed in the final `.config`: `SYS_I2C_SUN8I_RSB=y`, `SPL_I2C=y`,
`R_I2C_ENABLE`/`SYS_I2C_MVTWSI` off, `DM_I2C=y`, `PMIC_AXP=y`, `ENV_IS_NOWHERE=y`,
`ENV_IS_IN_FAT`/`ENV_IS_IN_SPI_FLASH` off, `SPI_FLASH_XTX=y`, `USB_EHCI_HCD/USB_OHCI_HCD/
USB_STORAGE/USB_KEYBOARD=y`, `PREBOOT="usb start"`, `BOOTCOMMAND="run distro_bootcmd"`,
`SPL_SPI_SUNXI=y`, `CMD_SF/CMD_PXE/CMD_DHCP/CMD_BOOTI=y`, `USB_ETHER` off. SPL link map
contains `sun8i_rsb.o`, `pmic_bus.o`, `axp_spl.o` and no `mvtwsi.o`; the U-Boot map contains
`lib/uthread.o` (`CONFIG_UTHREAD=y`, `UTHREAD_STACK_SIZE=32768`), 20/20 patches applied.
13 compiler warnings, all the known OpenSSL ENGINE deprecation stubs in host tools.
`fdtget` on the built `u-boot.dtb`: `usb@5100000` (OTG) okay; `usb@5200000/5200400`
(on-board USB-A), `usb@5310000/5310400` and `usb@5311000/5311400` (expansion header)
okay; `usb@5101000/5101400` (OTG-port host side) disabled, as in the kernel DT.

## Item 1 — "Failed to set core voltage! Can't set CPU frequency" (SPL)

Root cause: a bus-mode mismatch between the SPL and everything after it. The Zero2 DT
(`sun50i-h616-orangepi-zero2.dts`) describes the AXP305 on **R_RSB** (`pmic@745`), and
the serial log confirms BL31 uses it (`Probing for PMIC on RSB: PMIC: found AXP305`). TF-A's
`sunxi_power.c` switches the PMIC into RSB mode (AXP mode register 0x3e = 0x7c) and Linux
talks RSB to it. The PMIC keeps that mode until it loses power. The SPL, however, uses
`CONFIG_R_I2C_ENABLE` + legacy `mvtwsi` (upstream defconfig): on every **warm** reboot the
I2C transfer to 0x36 is not acknowledged, `axp_init()` fails and `sunxi_board_init()`
(`board/sunxi/board.c`) skips `clock_set_pll1(get_board_sys_clk())` with that message.
Consistent with the log, which is a `reboot`. (U-Boot has no RSB support for the H6/H616
generation at all: `SUNXI_RSB_BASE` undefined, `rsb_init()` uses the sun6i PRCM layout.)

Effect: `clock_init_safe()` programs PLL_CPUX to **408 MHz**; nothing later raises it —
BL31 does not touch it, U-Boot proper has no cpufreq — so SPL (DRAM init, ~0.9 MiB FIT
load), BL31, U-Boot proper (`Core: 67 devices`, USB scan, boot.scr, 48 MiB kernel+initrd
copy/relocation) and the kernel up to the point where `cpufreq-dt` sets an OPP all run at
0.4 GHz instead of the intended 1008 MHz (`CONFIG_SYS_CLK_FREQ`). Measured in the log:
SPL→BL31 1.5 s, SPL→`Starting kernel` 8.05 s; the CPU-bound parts (FIT parsing, DT fixups,
`Moving Image`, decompression in the kernel) are ~2.5× slower than they should be.
(Even upstream never programs VDD-CPU on AXP305: `AXP_DCDC1_VOLT` is not offered for it;
the PMIC's power-on DCDCA default is what the 1008 MHz OPP relies on, as on every other
H616 board. Only DCDCD = VCC-DRAM 1.5 V is set by the SPL.)

Fix (proper, code + defconfig, upstreamable):
- `sunxi-h616-rsb-pmic-bus.patch`: `SUNXI_RSB_BASE 0x07083000` for the H6 generation;
  `rsb_init()` gates/un-resets the module through PRCM `0x1bc` (bit 0 / bit 16, same scheme
  as `clock_twi_onoff()`'s `0x19c`) on `SUN50I_GEN_H6` instead of `prcm_apb0_enable()`;
  PL0/PL1 pin function 2 is already right; `pmic_bus.c` uses the AXP305/805/806
  "secondary" RSB pair `0x745/0x3a` (fixed mapping, Linux `drivers/bus/sunxi-rsb.c`).
  `rsb_init()` issues the device-mode switch itself, so a cold boot (PMIC in I2C mode)
  works too, exactly like TF-A.
- `0001` defconfig: `CONFIG_SYS_I2C_SUN8I_RSB=y`, drop `R_I2C_ENABLE`,
  `SPL_SYS_I2C_LEGACY`, `SYS_I2C_MVTWSI`, `SYS_I2C_SLAVE/SPEED`; keep `SPL_I2C=y` (it
  pulls `drivers/i2c/` = the RSB driver into the SPL). U-Boot proper's DM path
  (`sun8i_rsb` driver on the DT `r_rsb` node, clk/reset from `clk_h6_r.c`, `s_rsb` pinmux,
  `axp` PMIC driver via the `x-powers,axp806` fallback compatible) is unchanged and now
  matches the bus the SPL used.

Expected: no "Failed to set core voltage" on cold or warm boot, SPL stage visibly faster
(the 1.5 s SPL→BL31 should drop to well under 1 s), U-Boot proper and early kernel faster.

## Item 2 — "Loading Environment from FAT... Unable to use mmc 0:1..."

Upstream default for sunxi+MMC is `ENV_IS_IN_FAT` (`mmc 0:auto`, `uboot.env`), plus
`ENV_IS_IN_SPI_FLASH` (64 KiB at 0xf0000) because `SPI=y`. Armbian never saves an env: the
boot flow is `boot.scr` + `/boot/armbianEnv.txt`; the historic ext4 `/boot/boot.env` hack
in `uboot.sh` is only applied to 2018/2019 U-Boots. On our single ext4 partition the FAT
probe can only fail and print that line; a saved env (stale `uboot.env` on a FAT card,
`saveenv` into the SPI flash we now boot from) would silently override the boot flow.
Decision: `CONFIG_ENV_IS_NOWHERE=y` (recore in the same patch dir does the same), FAT and
SPI env off. Default env only, `saveenv` unavailable, no probing line at all. The SPI
layout is therefore: 0x0 SPL (0xA000), FIT follows, nothing else — no env region to
collide with the ~865 KiB image.

## Item 3 — SPI NOR boot (recovery + netboot)

- Image: `u-boot-sunxi-with-spl.bin` **is** the SPI image. binman lays out
  `sunxi-spl.bin` (min 0x8000, actual 0xA000) followed by the FIT (U-Boot + BL31 + DTB);
  the SPL reads its own eGON header length and loads the FIT from `max(spl_size,
  SYS_SPI_U_BOOT_OFFS)` on SPI exactly as on MMC (`spl_spi_sunxi.c`,
  `sunxi_get_spl_size()`). 886377 bytes < 2 MiB. `CONFIG_SPL_SPI_SUNXI=y` was already in
  the defconfig; H616 SPI0 pins PC0/PC2/PC3/PC4 are handled in `spl_spi_sunxi.c`.
  The U-Boot DT already has the `spi0`/`flash@0` node (dts/upstream == Linux 7.3 here).
- `0003`: SPI NOR vendor tables (XTX = the XT25F16B usually on the Zero2, plus Winbond,
  GigaDevice, EON, Puya, XMC, Zbit, Macronix) so `sf probe` works at the prompt (the SPL
  does not need IDs; U-Boot proper does for `sf`).
- Armbian integration: `write_uboot_platform_mtd()` in `sunxi64_common.inc` (flashcp on
  `/dev/mtdN`, dd fallback) — the same hook rockchip64 uses, consumed by
  `armbian-install`'s "Install/Update the bootloader on SPI Flash" (armbian-config is a
  separate repo; it calls the function from `/usr/lib/u-boot/platform_install.sh`).
  Note: the BSP does not depend on `mtd-utils`; the board needs `apt install mtd-utils`.
- Boot order from SPI: `CONFIG_BOOTCOMMAND="run distro_bootcmd"`, `boot_targets =
  fel mmc0 usb0 pxe dhcp` (`sunxi-common.h`: FEL no-op, MMC_SUNXI_SLOT_EXTRA=-1 so only
  mmc0, USB because `USB_STORAGE`, PXE/DHCP because `CMD_PXE/CMD_DHCP`). So: SD if it has
  boot.scr/extlinux/EFI → USB stick → DHCP + TFTP PXE → `dhcp` script → prompt. Armbian's
  `boot.scr` reads the boot source byte at `0x10028` and prints `U-boot loaded from SPI`,
  then boots from `${devtype} ${devnum}` (mmc 0 or usb 0), so an SD or USB Armbian image
  boots unchanged under SPI U-Boot. BROM order is SD first, so with a valid SPL on the SD
  the SPI copy is only reached when the SD is absent/blank/corrupt — recovery semantics.

## Item 4 — USB / Ethernet init noise and boot time

Log timeline (warm reboot, `harness/serial.log` 21:24): SPL 13.340 → BL31 14.845 (1.5 s)
→ U-Boot banner 14.846 → `Core:` 15.348 → `starting USB...` 15.348 → USB done 17.858
(2.5 s: EHCI/OHCI init + 1 s hub debounce + storage scan) → autoboot prompt 18.360 (1 s
bootdelay) → boot.scr 18.881 → kernel+initrd read 2.0 s at 23 MiB/s → `Starting kernel`
21.390. **SPL→kernel 8.05 s.**

Kept (serves a function): USB host + storage + keyboard and `preboot=usb start` (USB boot
is a board feature; `0005` additionally enables ehci2/ohci2/ehci3/ohci3 for the two
expansion-board ports, mirroring Armbian's kernel DT patch — the previous DT only had the
on-board USB-A port `usb@5200000/5200400`), Ethernet (`sun8i_emac`, needed for netboot),
bootdelay 1 (Armbian policy), `WDT: Not starting watchdog` (informational, 0 cost).

Removed (serves nothing): `CONFIG_USB_ETHER` (RNDIS gadget on the power/peripheral-only
USB-C port) — the five lines `Allwinner mUSB OTG (Peripheral)` / `using musb-hdrc, OUT
ep1out IN ep1in STATUS ep2in` / `MAC de:ad:…` / `HOST MAC …` / `RNDIS ready` / `, eth1:
usb_ether`, plus 18 KB of image; and the FAT env probe line (item 2). The MUSB gadget
itself stays (fastboot/ums on demand).

Expected boot time: ≈ 8.0 s → ≈ 6.5–7 s (SPL ~0.7 s faster at 1 GHz, env probe gone,
U-Boot proper CPU-bound work ~2× faster; the USB scan's ~2.5 s stays and may grow by a few
hundred ms with four more host controllers). To be measured by the coordinator (timestamps
from the serial logger: SPL banner → `Starting kernel`).

### Board results round 1 (coordinator, integration 32692ca, sha ffa022a5…) and the USB scan regression

- T0 confirmed the root cause: old firmware, cold boot → no "Failed to set core voltage";
  warm reboot → message present.
- T1 PASS warm and cold: no core-voltage line, `Loading Environment from nowhere... OK`,
  no mUSB/RNDIS lines, BL31 still finds the AXP305 on RSB, Linux `sunxi-rsb 7083000.rsb`
  3 MHz with the AXP806 at `sunxi-rsb-745`. SPL→BL31 1.0 s warm (was 1.5 s).
  `/proc/mtd`: `mtd0 00200000 00001000 "spi0.0"`; dmesg prints no spi-nor chip name.
- Regression: `starting USB...` → `Bus …` took 7.0 s warm / 6.5 s cold (was 2.5 s), so
  SPL→`Starting kernel` 12.0 s (was 8.5 s). Nothing plugged in, six root hubs each
  "1 USB Device(s) found".

Where the time goes: `usb_init()` (drivers/usb/host/usb-uclass.c) scans the controllers
one after another; for every root hub `usb_hub_power_on()` sets `query_delay` (≥100 ms,
2×bPwrOn2PwrGood) and `connect_timeout = query_delay + CONFIG_USB_HUB_DEBOUNCE_TIMEOUT`
(1000 ms), and `usb_device_list_scan()`/`usb_scan_port()` keeps polling the port status
until a connection shows up or that timeout expires. An empty root hub therefore costs
~1.1 s, ×6 controllers (3 EHCI then 3 OHCI companions) = 6.6 s — exactly the measured
delta. Not VBUS/PHY/regulators (ports 2/3 have no vbus regulator and need none) and not
the OHCI handoff; it is purely the per-controller connect debounce, serialized.

Fix without dropping anything (commit facf2f2 on `sunxi/uboot-usb-boot`, 9394e96 on the
integration branch):
- v2026.10 already has the infrastructure to do this in parallel: `usb_init()` creates
  one uthread per controller for init and scan when `CONFIG_UTHREAD=y` (cooperative
  threads on `initjmp`/`setjmp`, arm64 supports it: `HAVE_INITJMP=y`; used by
  `imx93_frdm`, `qemu_arm`, sandbox). Threads only switch at `udelay()`/`schedule()`.
- But the hub scan loop never reaches either: root-hub port status requests are answered
  synchronously by EHCI/OHCI, so `usb_device_list_scan()` spins through the whole
  debounce and the threads serialize anyway. `usb-hub-yield-during-port-debounce.patch`
  adds one `schedule()` per pass over `usb_scan_list` (same call the EHCI transfer wait
  loop already makes; without UTHREAD it only runs the cyclic framework). The other
  controllers' threads then configure their root hubs and add their ports to the shared
  scan list while the first one debounces; the running loop scans all of them.
- `0006`: `CONFIG_UTHREAD=y` (32 KiB stack per thread from the 64 MiB malloc pool).
Expected: primaries (3 EHCI) debounce together ≈1.1 s, then companions (3 OHCI) ≈1.1 s,
plus controller init ≈0.2 s → "starting USB..." ≈2.3–2.6 s, i.e. back to the old
two-controller figure with all six ports still scanned and bootable. Kept as is:
`CONFIG_USB_HUB_DEBOUNCE_TIMEOUT=1000` (lowering it would risk missing slow-to-connect
sticks/HDD enclosures), `preboot=usb start`, all ports.

Sanity check on the host: sandbox64 (`CONFIG_UTHREAD=y`, emulated hubs/devices) built
from the same tree with the pristine and with the patched `usb_hub.c`
(`kernel-check/work-uboot/build-sandbox`, `./u-boot -T -c "ut dm usb_<t>"`): identical
pass/fail pattern (usb_base, usb_multi, usb_stop, usb_fdt_node pass in both; usb_flash and
usb_keyb fail identically in both when run outside the pytest harness, so pre-existing),
and the passing multi-bus tests got faster with the yield: usb_multi 7010 → 5975 ms,
usb_stop 8621 → 6924 ms, usb_fdt_node 7694 → 6221 ms — the debounce periods of the emulated
buses now overlap. (Host note: /tmp was 96 % full from other agents' mmdebstrap trees;
the build script runs are unaffected but set `TMPDIR` for LTO links of the sandbox.)

### Board results round 2 (binary e9776c2c, SD, warm): PASS
`starting USB...` → six `Bus … 1 USB Device(s) found` in 1.5 s (target ≤ 2.6 s, was 7.0 s),
SPL→`Starting kernel` 6.5 s (baseline 8.5 s, round 1 12 s), no core-voltage line. T2 (round-1
binary): flashcp + read-back cmp OK; with the SD's SPL header zeroed → `Trying to boot from
sunxi SPI` → Linux from SD; with `/boot/boot.scr` hidden: mmc0 → usb (0 storage) → pxe (all
pxelinux.cfg names, no TFTP server yet) → dhcp → `=>` in ~11 s. Three follow-ups:

### Round 3a — DHCP lease lock-out after a U-Boot netboot attempt (harness)
Root cause (systemd v261 `src/libsystemd-network/dhcp-server-request.c`,
`dhcp_server_process_discover()`): leases are keyed by client identifier — option 61 if sent,
else `01:<MAC>` from the header. U-Boot sends no option 61 and never renews/releases, so its
DISCOVER binds the static lease `.107` to `01:02:00:8a:27:57:7d` for `DefaultLeaseTimeSec`
(1 h when unset). Armbian's networkd client identifies as RFC 4361 `ff:<IAID>:<DUID>`; the
server still finds the MAC static lease (header fallback in `dhcp_server_get_static_lease()`)
but sees the address bound to another identity and returns `-EADDRINUSE`: no OFFER, no NAK,
for the rest of the hour and across reboots (`PersistLeases=yes`). Routers: ISC dhcpd matches
`fixed-address` by MAC and does not track it as a lease; dnsmasq lets a lease move between
client-ids with the same MAC; without a reservation they just hand out two pool addresses.
networkd's server is the strict one. Fixes (details `harness/netboot/README.md`):
1. Board (correct place): `dhcp-identifier: mac` (networkd `ClientIdentifier=mac`) so
   U-Boot, kernel `ip=dhcp` and the OS share one identity —
   `sudo netplan set ethernets.all-eth-interfaces.dhcp-identifier=mac && sudo netplan apply`
   (check the id with `cat /etc/netplan/*.yaml`; snippet `harness/netboot/opiz2-dhcp-identifier-mac.yaml`).
2. Host: `DefaultLeaseTimeSec=5min` added to `harness/06-opiz2-enx68da73af6279.network`
   (sudo: `install -m 0644 harness/06-opiz2-enx68da73af6279.network /etc/systemd/network/ && networkctl reload`);
   `netboot-setup.sh` now checks for it and prints the board-side step.
3. Unblock now: `sudo networkctl reconfigure enx68da73af6279`; if the stale lease is reloaded,
   `sudo systemctl stop systemd-networkd && sudo rm -f /var/lib/systemd/network/dhcp-server-lease/* && sudo systemctl start systemd-networkd`.
Not changed: U-Boot (no client-id option upstream; the kernel would still differ), the static
lease itself, `PersistLeases`.

### Round 3b — boot.scr said "U-boot loaded from SD" under SPI U-Boot
`boot-sun50i-next.cmd` read the SPL header's boot_media byte at the hard-coded A64/H5 address
`0x10028`; on H6/H616/H618 the SPL lives at `0x20000` (A523: `0x44000`,
`CONFIG_SUNXI_SRAM_ADDRESS`), so the byte read was unrelated memory. Fix (branch
`sunxi/uboot-bootscript-recovery`): U-Boot patch `sunxi-export-boot-source-env.patch` sets
`${boot_source}` = `fel|mmc0|mmc2|spi|nand` in `misc_init_r()` next to `fel_booted`/`mmc_bootdev`
(upstreamable); the script prefers it and, for U-Boots without it, derives the header address
from `${fdtfile}` (`sun50i-h6*`/`sun50i-a1*` → 0x20028, `sun55i-*` → 0x44028, else 0x10028)
and also recognises the `0x10/0x12` "high offset" MMC values. Verified in sandbox U-Boot by
sourcing the compiled script with planted header bytes: H616/SPI, A64/eMMC, A133/SD-high,
A523/SPI all report correctly; exported `boot_source` wins.

### Round 3c — sourcing boot.scr by hand from the `=>` prompt
Same branch: the script now defaults `devtype=mmc devnum=0` when `${devtype}` is unset or not
a block device type (`dhcp` after a failed network boot), and `distro_bootpart=1`,
`prefix=/boot/` when unset (sandbox-verified: `devtype=mmc devnum=0 part=1 prefix=/boot/`
after `setenv devtype dhcp`). Recovery one-liners at `=>`:
- `run bootcmd_mmc0` — normal case (boot.scr present on the SD), sets everything itself;
  `run bootcmd_usb0` for a stick.
- `load mmc 0:1 ${scriptaddr} /boot/boot.scr && source ${scriptaddr}` — direct, now works
  without the four setenvs (use `usb 0:1` for a stick).
Board test: compile the new script on the board (`mkimage -C none -A arm -T script -d
boot.cmd /boot/boot.scr`, or install the BSP from the integration branch), boot from SPI with
the SD in and boot.scr hidden → interrupt → `load mmc 0:1 ${scriptaddr} /boot/boot.scr.off;
source ${scriptaddr}` must print `U-boot loaded from SPI` and boot; normal SD boot must still
print `U-boot loaded from SD`.

### Round 4 — KASLR: /chosen/kaslr-seed and rng-seed from the H616 Crypto Engine TRNG
Linux: `KASLR disabled due to lack of seed` (arm64 `RANDOMIZE_BASE` reads `/chosen/kaslr-seed`,
which the bootloader must supply). U-Boot v2026.10 adds it automatically: `fdt_chosen()`
(boot/fdt_support.c, called from `image_setup_libfdt()` on the booti/bootm path that Armbian's
boot.scr uses) runs `fdt_kaslrseed()` whenever `CONFIG_DM_RNG` is enabled (and no measured
boot / ARMV8_SEC_FIRMWARE), reading 8 bytes from the first UCLASS_RNG device; with
`CONFIG_BOARD_RNG_SEED` it also adds `rng-seed` (64 bytes) via `board_rng_seed()`. The
`kaslrseed` command is obsolete for this ("automatically added … when booted via
booti/bootm/bootz"). What was missing is an RNG driver: upstream has none for sunxi
(main/next as of 2026-11-01: only a new airoha driver; patchwork: the pending
"crypto: allwinner: enable sun8i-ce FIT crypto" v9 series, 2026-10-17, adds AES/hash/ECDSA on
the Crypto Engine plus the CE clock gates/reset, but no TRNG).

Branch `fix/uboot-sunxi-ce-rng-kaslr` (83ebfc1):
- `clk-sunxi-add-h6-h616-ce-gates-and-reset.patch`: patch 13/17 of that series (James
  Hilliard, Reviewed-by Simon Glass), unchanged: `CLK_CE` 0x680/31, `CLK_BUS_CE` 0x68c/0,
  `CLK_MBUS_CE` 0x804/2, `RST_BUS_CE` 0x68c/16 for H6 and H616.
- `rng-add-allwinner-sun8i-ce-trng-driver.patch`: new `drivers/rng/sun8i_ce_rng.c`
  (`RNG_SUN8I_CE`, default y with DM_RNG on sunxi), bound to `allwinner,sun50i-h6-crypto` /
  `allwinner,sun50i-h616-crypto` (node `crypto@1904000` is in the U-Boot DTB). Per Linux
  `sun8i-ce-trng.c`: TRNG "V2" algorithm 0x1c, length in bytes, 32-byte granules, task
  descriptor on flow 3, completion polled in `CE_ISR`, 8-bit per-flow error field in
  `CE_ESR`; H616 uses word (>>2) addresses in the descriptor. Probe takes the DT clocks
  (bus/mod/ram from the CCU, trng = IOSC from the RTC clock driver) and reset, and programs
  the H616 CE module clock to PLL_PERI0(2X)/4 = 300 MHz through the CCU register exactly as
  the pending series does (the sunxi CCU driver has no set_rate). Cache maintenance:
  descriptor and buffer flushed before, buffer invalidated after the DMA; the output buffer
  is zeroed before free.
- `sunxi-board-rng-seed-from-dm-rng.patch`: `board_rng_seed()` in board/sunxi/board.c (64
  bytes from UCLASS_RNG, same as Xilinx/Rockchip), required by `BOARD_RNG_SEED`.
- `0007`: `CONFIG_DM_RNG=y`, `CONFIG_BOARD_RNG_SEED=y`, `CONFIG_CMD_RNG=y`.
Build: driver and `board_rng_seed`/`fdt_kaslrseed` linked (`u-boot.map`), +8.6 KB.
The series integration note: when the upstream sun8i-ce core lands, this TRNG should become a
child of its core driver (same compatible); the register handling is already identical.

Board test (round 4 binary 44dffad8…, SD at 8 KiB as before):
1. Stop autoboot: `rng` → 64 random bytes hexdump, different on each call; `rng 0 32`;
   no "sun8i-ce TRNG: …" error line. (`dm tree | grep -i rng` shows `sun8i-ce-rng` under
   `crypto@1904000`.)
2. Boot Linux twice: `dmesg | grep -i kaslr` must NOT show "KASLR disabled due to lack of seed";
   `sudo grep ' _stext\| _text$' /proc/kallsyms` (as root; kptr_restrict) gives a different
   address on the two boots; `cat /proc/device-tree/chosen/kaslr-seed | xxd` is all zero
   (the kernel wipes it after use) and `/proc/device-tree/chosen/rng-seed` is 64 bytes;
   `dmesg | grep -i 'random:'` should show the CRNG seeded early ("crng init done" before
   userspace) rather than waiting for entropy.
3. Sanity: boot time unchanged within noise (one TRNG task ≈ microseconds).

## Item 5 — upstream check

U-Boot: GitHub `master` (ece349a, "Prepare v2026.07") is a stale mirror — the project
branch is now `main` on source.denx.de (ee9fc27, 2026-11-01) / `next` (ed86986). Fetched
both into the work clone (`upstream-main`, `upstream-next`) and diffed against v2026.10 in
`arch/arm/mach-sunxi`, `arch/arm/include/asm/arch-sunxi`, `board/sunxi`, `drivers/power/axp*`,
`drivers/power/pmic/axp.c`, `drivers/power/regulator/axp_regulator.c`, `drivers/i2c/
{sun8i_rsb,mvtwsi}.c`, `drivers/spi/spi-sunxi.c`, `drivers/mmc/sunxi_mmc.c`,
`drivers/usb/musb-new/sunxi.c`, `drivers/net/sun8i_emac.c`, `drivers/phy/allwinner`,
`drivers/clk/sunxi`, `include/configs/sunxi-common.h`, `configs/orangepi_zero2_defconfig`:
**no sunxi/H616/AXP/SPI changes** after v2026.10 (only a `board/sunxi/MAINTAINERS` cleanup);
`v2027.01-rc1` likewise. Nothing to backport. (The H616 RSB support above is therefore
new; worth sending upstream.)

TF-A: `lts-v2.14.11` (2026-10-16) already contains every `plat/allwinner` commit on
master (latest: `fix(allwinner): avoid crash when running without DTB`, 2025-10; A133
support 2025-05). `plat/allwinner/sun50i_h616/sunxi_idle_states.c` is empty (`{}`) on
master too and `platform.mk` has `SUNXI_PSCI_USE_NATIVE := 1`, i.e. only CPU_ON/CPU_OFF and
system off/reset — hence `PSCI: Suspend is unavailable` in BL31's log and no
`cpuidle-psci` states in Linux (WFI only). No upstream work on H616 CPU_SUSPEND or an SCP
(crust) port exists to pick up; implementing it would mean adding idle states plus a native
core power-down/wake path in `sunxi_native_pm.c` using the H616 CPU power controller. Not
done, as instructed.

## Board test steps (coordinator; expected serial output)

Artifact: `/home/aruni/orangepizero2/kernel-check/work-uboot/out/u-boot-sunxi-with-spl.bin`
(current: round 4, sha256 44dffad8…; file `…/out/u-boot-sunxi-with-spl.bin.sha256`; banner `U-Boot SPL
2026.10_armbian-check…`). The Armbian-built package from `wt-uboot-integration` yields the
same content with the `_armbian-<version>` banner.

### T0 — confirm the root cause with the *current* firmware (no flashing)
1. Cold boot: Meross off → 10 s → on. Expect SPL **without** `Failed to set core voltage`
   (PMIC lost power → back in I2C mode).
2. `sudo reboot` from Linux. Expect the message **present** (PMIC left in RSB mode by BL31).
   If (1) also shows it, report — the RSB fix still applies but there would be a second cause.

### T1 — new U-Boot on the SD card
On the board (same as Armbian's `write_uboot_platform`):
```
scp kernel-check/work-uboot/out/u-boot-sunxi-with-spl.bin aruni@10.56.0.107:/tmp/
sudo dd if=/tmp/u-boot-sunxi-with-spl.bin of=/dev/mmcblk0 bs=1024 seek=8 conv=fsync
sudo reboot
```
Expect (warm reboot):
```
U-Boot SPL 2026.10_armbian-check… 
DRAM: 1024 MiB
Trying to boot from MMC1                  <- no "Failed to set core voltage" line
NOTICE:  BL31: … INFO: Probing for PMIC on RSB: / PMIC: found AXP305 …   (unchanged)
U-Boot 2026.10_armbian-check… Allwinner Technology
CPU:   Allwinner H616 (SUN50I) / Model: OrangePi Zero2 / DRAM:  1 GiB / Core: …
MMC:   mmc@4020000: 0
In:    serial@5000000                      <- no "Loading Environment from FAT..." line
Net:   eth0: ethernet@5020000              <- no mUSB/RNDIS/usb_ether lines
starting USB...
USB EHCI 1.00 / USB OHCI 1.0 … (3 EHCI + 3 OHCI)
Bus usb@5200000: 1 USB Device(s) found     <- printer, plus usb@5200400, usb@5310000,
Bus usb@5310400 …, usb@5311000 …, usb@5311400 …
scanning usb for storage devices... 0 Storage Device(s) found
Hit any key to stop autoboot:  1 … Found U-Boot script /boot/boot.scr … U-boot loaded from SD … Starting kernel ...
```
Record SPL-banner→`Starting kernel` and SPL→BL31 times (were 8.05 s / 1.5 s; round 1
gave 1.0 s SPL→BL31 but 12.0 s to the kernel because of the 7 s USB scan). Round 2 target:
`starting USB...` → last `Bus …` line ≤ 2.6 s with nothing plugged in (six buses still
listed, each `1 USB Device(s) found`), SPL→`Starting kernel` ≈ 7.5 s. Then repeat with a
stick in the on-board port and in an expansion-board port: the stick must be found
(`1 Storage Device(s) found`) and the scan may take a little longer only for that bus. Then
cold boot once more (Meross) — same output expected. In Linux, `dmesg | grep -i rsb`
should show `sunxi-rsb 7083000.rsb` and the AXP as before.

### T2 — SPI NOR: write, verify, boot with SD removed, revert
```
sudo apt install -y mtd-utils
cat /proc/mtd                      # expect: mtd0: 00200000 00001000 "..."  (2 MiB, 4 KiB erase)
dmesg | grep -i spi-nor            # report the chip name/JEDEC id (expect xt25f16b or mx25l1606e)
sudo flashcp -v /tmp/u-boot-sunxi-with-spl.bin /dev/mtd0        # erases, writes, verifies
# independent read-back verify
n=$(stat -c %s /tmp/u-boot-sunxi-with-spl.bin)
sudo dd if=/dev/mtd0 bs=4096 count=$(( (n+4095)/4096 )) status=none | cmp -n $n - /tmp/u-boot-sunxi-with-spl.bin && echo SPI VERIFY OK
```
Also test the Armbian path: `armbian-install` → "Install/Update the bootloader on SPI
Flash" must now offer/complete (uses `write_uboot_platform_mtd`).
1. `sudo reboot` with the SD in: must still print `U-boot loaded from SD` (BROM prefers SD).
2. `sudo poweroff`, Meross off, **remove SD**, Meross on. Expect:
```
U-Boot SPL 2026.10_armbian-check…
DRAM: 1024 MiB
Trying to boot from SPI
… BL31 … U-Boot … MMC:   mmc@4020000: 0
starting USB... (as above) … 0 Storage Device(s) found
Hit any key to stop autoboot:  0
MMC: no card present      (or "Card did not respond to voltage select! : -110")
… USB target: nothing … BOOTP broadcast 1 … DHCP client bound to address 10.56.0.107
TFTP from server 10.56.0.1; … Filename 'pxelinux.cfg/default-arm-sunxi'   (before netboot-setup: T T T … Retry count exceeded)
=>                                        <- U-Boot prompt reached = recovery works
```
   At the prompt: `sf probe` → expects `SF: Detected xt25f16b with page size 256 Bytes,
   erase size 4 KiB, total 2 MiB` (chip name per dmesg); `mmc info` with no card → error.
3. Re-insert the SD (power off first), power on → boots from SD as before.
Revert/erase (returns to the factory blank state, BROM then skips SPI):
```
sudo flash_erase /dev/mtd0 0 0
sudo dd if=/dev/mtd0 bs=1M count=2 status=none | od -An -tx1 | grep -v -x ' ff\( ff\)*' | head -1   # no output = all 0xFF
```

### T3 — USB boot (SD removed, SPI U-Boot)
Write an Armbian Zero2 image to a USB stick (`dd` the .img, as for SD). With the SD removed,
plug the stick into (a) the on-board USB-A, (b) each expansion-board port; power on. Expect
`scanning usb for storage devices... 1 Storage Device(s) found`, `Scanning usb 0:1...`,
`Found U-Boot script /boot/boot.scr`, `U-boot loaded from SPI`, `Boot script loaded from
usb`, kernel boots with the stick's rootfs (armbianEnv.txt `rootdev=UUID=…`). Also with an
SD inserted that has no bootloader (blank card) the same must happen (BROM: SD invalid →
SPI; U-Boot: mmc0 has no boot.scr → usb0).

### T4 — netboot (development loop)
Host, once (lists every sudo step; `--dry-run` shows them):
```
harness/netboot-setup.sh          # installs dnsmasq (TFTP-only, port=0, bound to enx68da73af6279, root /srv/tftp/opiz2),
                                  # networkd drop-in: [DHCPServer] BootServerAddress=10.56.0.1 BootFilename=pxelinux.cfg/default-arm-sunxi,
                                  # networkctl reload, enables dnsmasq, self-tests TFTP with curl
harness/netboot-stage.sh          # Image + sun50i-h616-orangepi-zero2.dtb from kernel-check/work/linux-7.3.1 → TFTP root,
                                  # writes pxelinux.cfg/default-arm-sunxi (ROOTMODE=sd default; INITRD=, OVERLAYS=, EXTRAARGS=)
```
Board: U-Boot must reach the `pxe` target, i.e. nothing bootable on mmc0/usb0: run from
SPI with SD removed (then ROOTMODE must be `initrd`/`nfs`), or — the useful kernel-test
loop — keep the SD in as rootfs but rename its script: `sudo mv /boot/boot.scr
/boot/boot.scr.off` (restore with `mv` back). Expect after the USB scan:
```
BOOTP broadcast 1
DHCP client bound to address 10.56.0.107 (… ms)
Using ethernet@5020000 device
TFTP from server 10.56.0.1; our IP address is 10.56.0.107
Filename 'pxelinux.cfg/default-arm-sunxi'. … done
Retrieving file: pxelinux.cfg/01-02-00-8a-27-57-7d … (not found, fast) … 
Config file 'pxelinux.cfg/default-arm-sunxi' found
1:	Zero2 netboot (sd) Linux version 7.3.1…
Retrieving file: Image … Retrieving file: sun50i-h616-orangepi-zero2.dtb
## Flattened Device Tree blob at … Starting kernel ...
```
Kernel modules for the netbooted kernel must exist on the SD rootfs
(`make modules_install INSTALL_MOD_PATH=…` + rsync to `/lib/modules/`) or the test is
built-in-only. `ROOTMODE=nfs` is documented in the script but needs an initramfs with
`dwmac_sun8i`/`realtek`/`nfs` (both `=m` in `linux-sunxi64-edge.config`) and
`nfs-kernel-server` exporting `/srv/nfs/opiz2`; the SD-rootfs mode is the recommended one.

## Files

- `/home/aruni/orangepizero2/kernel-check/build-uboot.sh` — rootless cached U-Boot+TF-A build / patch check.
- `/home/aruni/orangepizero2/kernel-check/work-uboot/{u-boot,arm-trusted-firmware,build,out}` — clones, objects, final artifact.
- `/home/aruni/orangepizero2/harness/netboot-setup.sh`, `harness/netboot-stage.sh`, `harness/06-opiz2-enx68da73af6279.network`
  (DefaultLeaseTimeSec), `harness/netboot/{README.md,dnsmasq-opiz2-tftp.conf,opiz2-dhcp-identifier-mac.yaml,06-opiz2-enx68da73af6279.network.d/netboot.conf}`.
- Patches: `wt-uboot/patch/u-boot/v2026.10-sunxi64/sunxi-h616-rsb-pmic-bus.patch`,
  `…/board_orangepizero2/0001…0007`, `…/usb-hub-yield-during-port-debounce.patch`, `…/sunxi-export-boot-source-env.patch`,
  `…/clk-sunxi-add-h6-h616-ce-gates-and-reset.patch`, `…/rng-add-allwinner-sun8i-ce-trng-driver.patch`, `…/sunxi-board-rng-seed-from-dm-rng.patch`,
  `wt-uboot/config/sources/families/include/sunxi64_common.inc`, `wt-uboot/config/bootscripts/boot-sun50i-next.cmd`.
