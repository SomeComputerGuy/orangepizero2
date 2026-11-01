# UWE5622 (AW859A) WiFi/BT on Orange Pi Zero2 — status for Linux 7.3.1 / Armbian edge

Date: 2026-11-01. Scope: what our Armbian build tree ships, what is known to be broken on 6.x/7.x, and what to change/test. All paths are absolute; all claims about upstream are backed by URLs.

---

## 1. What our build ships

### 1.1 Build tree
- Armbian build checkout: `/home/aruni/orangepizero2/armbian-build`, HEAD `794f1d4da859` (2026-11-01, "rootfs: skip dbus launch-helper chown when file is absent"). Includes upstream `21d426f545` "sunxi-7.3: rewrite patches against 7.3.1" (2026-10-31).
- Board: `config/boards/orangepizero2.csc` → `BOARDFAMILY=sun50iw9`, `KERNEL_TARGET="current,edge"`, `enable_extension "uwe5622-allwinner"`.
- Kernel 7.3.1 (edge), fully patched tree: `/home/aruni/orangepizero2/kernel-check/work/linux-7.3.1`.

### 1.2 Driver source and pin
- Injected by `driver_uwe5622()` in `lib/functions/compilation/patch/drivers_network.sh` (lines 548-580):
  - `uwe5622ver='commit:fa9d1a6703a93a85bcf68e865ebc2726474076ad'` (commit date 2026-10-13) from https://github.com/armbian/uwe5622
  - copies `tty-sdio/ unisocwcn/ unisocwifi/ Kconfig Makefile` into `drivers/net/wireless/uwe5622/`
  - adds `obj-$(CONFIG_SPARD_WLAN_SUPPORT) += uwe5622/` and a `source` line to the wireless Kconfig.
- Our pin is **identical to upstream armbian/build main** (checked `raw.githubusercontent.com/armbian/build/main/.../drivers_network.sh` line 555). armbian/build last bumped it on 2026-10-13 (`912b89c7fa "uwe5622: bump pinned commit hash"`).
- Cached checkout: `cache/sources/uwe5622/fa9d1a6703a93a85bcf68e865ebc2726474076ad/` (also has `dkms.conf`, `reference/` with the historical per-kernel patches incl. `uwe5622-v7.1.patch`).

### 1.3 Resulting kernel config (effective `.config` in the 7.3.1 tree; `config/kernel/linux-sunxi64-edge.config` is a defconfig so defaults are omitted there)
```
CONFIG_SPARD_WLAN_SUPPORT=y          # edge.config line 929
CONFIG_SC23XX=y / CONFIG_SC2355=m    # selected by default
CONFIG_AW_WIFI_DEVICE_UWE5622=y      # selected by SPARD_WLAN_SUPPORT if ARCH_SUNXI -> builds unisocwcn (uwe5622_bsp_sdio.ko)
CONFIG_AW_BIND_VERIFY=y
CONFIG_WLAN_UWE5622=m                # edge.config line 935 -> sprdwl_ng.ko
CONFIG_UNISOC_WIFI_PS=y              # edge.config line 936
CONFIG_TTY_OVERY_SDIO=m              # default -> sprdbt_tty.ko
CONFIG_SUNXI_ADDR_MGT=m              # edge.config line 635 -> sunxi_addr.ko (added upstream 2026-01-13, fe7b8eee12 "orangepizero2: fix bluetooth in edge kernel")
CONFIG_CFG80211=m CONFIG_MAC80211=m CONFIG_RFKILL=m CONFIG_BT=m CONFIG_BT_HCIUART=m CONFIG_BT_HCIUART_H4=y
CONFIG_BT_RFCOMM=m CONFIG_BT_BNEP=m CONFIG_BT_HIDP=m CONFIG_PWRSEQ_SIMPLE=y CONFIG_NVMEM_SUNXI_SID=y CONFIG_MMC_SUNXI=y
```
Modules actually produced by the 7.3.1 build (`build2.log`): `uwe5622_bsp_sdio.ko`, `sprdwl_ng.ko`, `sprdbt_tty.ko` (+ `sunxi_addr.ko` from drivers/misc).

Note: the vendor Makefile for the Allwinner variant does **not** define `CONFIG_WCN_PARSE_DTS` (commented out, `unisocwcn/Makefile` lines 131/161/189), so the WCN core ignores DT for its own GPIOs and registers a hard-coded `uwe_bsp` platform device (`wcn_boot.c:4326-4338`); `tty-sdio` likewise registers a hard-coded `mtty` platform device (`tty.c:878`). Power/reset of the chip is done purely by `mmc-pwrseq-simple` from the DT.

### 1.4 Device tree wiring (sunxi-7.3)
- `patch/kernel/archive/sunxi-7.3/patches.armbian/arm64-dts-sun50i-h616-orangepi-zero2-zero3-add-wifi.patch` (Gunjan Gupta, 2023-12-13): adds to `sun50i-h616-orangepi-zero.dtsi` fixed regulators `vcc33-wifi` (3V3, always-on) and `vcc-wifi-io` (1V8), `wifi_pwrseq` = `mmc-pwrseq-simple` with `clocks = <&rtc 1>` (osc32k-out), `reset-gpios = PG18 active-low`, `post-power-on-delay-ms = 200`; enables `&mmc1` (bus-width 4, non-removable, `mmc-ddr-1_8v`).
- `patches.armbian/arm64-dts-sun50i-h6-h616-add-sunxi-info-nodes.patch`: adds `addr_mgt: addr-mgt { compatible = "allwinner,sunxi-addr_mgt"; }` to `sun50i-h616.dtsi` (verified at line 1824 of the patched tree) — needed by `sunxi_addr`.
- `patches.armbian/drv-misc-sunxi-add-addr-mgt-driver-uwe5622.patch` (afaulkner420, 2022): `drivers/misc/sunxi-addr/` (`sunxi-addr.c` + `sha256.c`). Exports `get_custom_mac_address()` (consumed by `sprdwl_ng` in `unisocwifi/main.c:1082`) and creates `/sys/class/addr_mgt/addr_bt` (read by the installed `hciattach_opi` blob). Depends on `sunxi_get_soc_chipid()` exported from `drivers/nvmem/sunxi_sid.c` (present, via the sunxi-info patch).
- `patches.armbian/drv-bluetooth-hci-sprd-broken-park-link-quirk-v6.16-plus.patch` (Paolo Sabatino): adds `HCI_QUIRK_BROKEN_PARK_LINK_STATUS`, set in `hci_uart_register_dev()` when `hdev->manufacturer == 0xffff` and the tty driver name starts with `ttyBT`; `hci_setup_link_policy_sync()` skips `HCI_LP_PARK`. Works around the firmware rejecting `Write Default Link Policy` (0x080f) with status 0x12.

### 1.5 Firmware files the driver loads
From `drivers/net/wireless/uwe5622` (7.3.1 tree):
- `unisocwcn/platform/wcn_boot.c`: `WCN_FW_NAME "wcnmodem.bin"`; search path list `wcn_fw_path[] = { CONFIG_CUSTOMIZE_UNISOC_FW_PATH, "/lib/firmware/" }` and the top-level `Makefile` sets `UNISOC_FW_PATH_CONFIG := "/lib/firmware/uwe5622/"` → **`/lib/firmware/uwe5622/wcnmodem.bin`** (fallback `/lib/firmware/wcnmodem.bin`). Loaded via `filp_open` through `wcn_fs.h`/`scoped_with_init_fs()` (the 7.3 "open files from the init root" fix, armbian/uwe5622 PR #23). `gnssmodem.bin` is only used for GNSS (not shipped, not needed).
- `unisocwifi/rf_marlin3.c:485`: `sprintf(conf_name, "wifi_%8x_%dant.ini", chipid, ant)` with `WIFI_BOARD_CFG_PATH "/lib/firmware"` → **`/lib/firmware/wifi_2355b001_1ant.ini`** (chip id 0x2355b001, 1 antenna).
- Optional (`unisocwcn/platform/rf/rf.c`): `/lib/firmware/connectivity_configure.ini`, `/lib/firmware/connectivity_calibration.ini` (not shipped; driver tolerates absence).
- Bluetooth (userspace, read by the installed `hciattach_opi_arm64` blob — confirmed with `strings`): **`/lib/firmware/bt_configure_pskey.ini`**, **`/lib/firmware/bt_configure_rf.ini`**, BD address from `/sys/class/addr_mgt/addr_bt`.

**Which package ships them:** `armbian-firmware` (built by `lib/functions/compilation/packages/firmware-deb.sh` from `https://github.com/armbian/firmware` branch `master` — `ARMBIAN_FIRMWARE_SOURCE/BRANCH` in `lib/functions/configuration/main-config.sh:259-260`; installed by default via `lib/functions/rootfs/distro-agnostic.sh:431-436`). Our built deb `output/debs/armbian-firmware_26.11.0-trunk_all__1-SAf7fa-Ba2de-R448a.deb` (2026-10-29) contains:
```
/lib/firmware/uwe5622/wcnmodem.bin            947120 B
/lib/firmware/uwe5622/wcnmodem-38222.bin     1753088 B  (OPi 3B variant, unused here)
/lib/firmware/uwe5622/wifi_2355b001_1ant.ini    6703 B
/lib/firmware/wcnmodem.bin -> uwe5622/wcnmodem.bin             (symlink)
/lib/firmware/wifi_2355b001_1ant.ini -> uwe5622/wifi_2355b001_1ant.ini (symlink)
/lib/firmware/bt_configure_pskey.ini            5284 B
/lib/firmware/bt_configure_rf.ini               3050 B
```
The pskey file in our deb already has the park-mode bit cleared (`feature_set = 0xBF, 0xFE, ...`), i.e. it includes armbian/firmware commit `1f85287ae7` / PR #154 (2026-10-28). No Debian `firmware-*` package ships these files; `armbian-firmware` Conflicts/Provides `linux-firmware`.

### 1.6 Extension, services, blob
- `extensions/uwe5622-allwinner.sh` (identical to upstream main; last upstream change 2026-08-26 was only a description header):
  - `MODULES += sprdbt_tty`; installs `rfkill bluetooth bluez bluez-tools`
  - enables `aw859a-bluetooth.service` and `aw859a-wifi.service`
  - installs `packages/blobs/bt/hciattach/hciattach_opi_arm64` → `/usr/bin/hciattach_opi` (the 199632-byte blob, linked only against libc; it is the one updated 2023-12-30 "to fix intermittent segfaults").
- `packages/bsp/sunxi/aw859a-wifi.service`: `Type=forking`, `ExecStart=/sbin/modprobe sprdwl_ng`, `WantedBy=multi-user.target`. (`sunxi_addr` is pulled in automatically by modprobe symbol dependency: `sprdwl_ng` needs `get_custom_mac_address`; `uwe5622_bsp_sdio` by `depends`.)
- `packages/bsp/sunxi/aw859a-bluetooth.service`: `After=bluetooth.service`, `ExecStartPre=/sbin/modprobe sunxi_addr`, `ExecStartPre=/usr/sbin/rfkill unblock all`, `ExecStart=/usr/bin/hciattach_opi -s 1500000 /dev/ttyBT0 sprd`, `RemainAfterExit=true`. Identical to upstream main. `config/sources/families/sun50iw9.conf` `family_tweaks_s()` also enables it (redundant).
- Not used by our board: `hciattach_opi_arm64_upstream` (513848 B, added 2026-01-31 `642a75f5b3`), which reads the BD address from `/etc/default/sprd_bt_addr` instead of `/sys/class/addr_mgt/addr_bt`, and `packages/bsp/sunxi/sprd-bluetooth` (bash script added by armbian/build PR #9323 for Orange Pi 3 LTS, derives the BD address from a sha256 of the root block device CID). Both exist in our tree but only OPi 3 LTS wires them.

### 1.7 Compiler warnings in `/home/aruni/orangepizero2/kernel-check/work/build2.log` touching uwe5622
Exactly one:
```
drivers/net/wireless/uwe5622/unisocwcn/sdio/sdiohal_ctl.c: In function 'sdiohal_test_int_init':
drivers/net/wireless/uwe5622/unisocwcn/sdio/sdiohal_ctl.c:758:27: warning: unused variable 'pub_gpio_desc' [-Wunused-variable]
```
Judgement: **not a real bug.** `pub_gpio_desc` is declared under `#if LINUX_VERSION_CODE >= KERNEL_VERSION(7,1,0)` but only used inside `#ifdef CONFIG_WCN_PARSE_DTS`, which is not defined for the Allwinner build. The function is a debugfs test hook (`sdio_int_rx`/`sdio_int_tx` written to a debug file, `sdiohal_ctl.c:1091/1141`), never called in normal operation. The matching pre-7.1 variable `pub_gpio_num` would be "unused" the same way. Cosmetic; a one-line fix would be to move the declaration inside the `CONFIG_WCN_PARSE_DTS` block. No other uwe5622 warnings or errors (the earlier -Wvla/-Wmissing-prototypes/-Wint-conversion issues were fixed in the pinned commit range, PRs #1, #5, #21, #24).

---

## 2. Known problems on 6.x/7.x kernels (evidence)

### 2.1 armbian/uwe5622 — our pin is 13 commits behind master, and the newer commits are real bug fixes
GitHub compare `fa9d1a67...master`: ahead_by 13, behind_by 0 (all from PR #28, merged 2026-10-31, tested on 7.3.0-edge-rockchip64; "The Allwinner builds have not been run on hardware", CI builds Allwinner cleanly):
https://github.com/armbian/uwe5622/pull/28
- `74baabf334` **memory corruption**: PMF/IGTK keys use indices 4-5 but `vif->key[][]` only held 0-3 → out-of-bounds write on every PMF connect; kernel 7.3 reports `memcpy: detected field-spanning write (size 16)`. Follow-ups `5b6a686afe`, `f88cd0d25f`.
- `3e15ff9514` **memory corruption on unload**: `dtbs_buf` freed with `free_pages()` order 6 although it is a 2 KB slice of a shared page → 60x `BUG: Bad page state`, frees pages belonging to page cache/DRM. Affects anyone who unloads/reloads `uwe5622_bsp_sdio` (e.g. suspend scripts, `rmmod`).
- `8441aef962` + `de75ac8be1` tty-sdio: rfkill not unregistered on remove → oops in `rfkill_register` with `rfkill_global_mutex` held on module reload, all later rfkill users hang; BT power bit left set on unload.
- `92d51d4d62` cfg80211 `WARNING ... _cfg80211_unregister_wdev` when removing a connected interface.
- `adb85e1956` start-up retry when SDIO enumerates but chip-ID read times out (-110) → "no wlan0 until reboot". **Rockchip-only code path** (uses `mmc_hw_reset()`); the Allwinner start path does not get it.
- `cefa769e6d` tty-sdio: do not add second `mtty` device when DT has `sprd,mtty` (our DT has none → not hit).
- `abab6e004d` **TCP ACK stall**: held ACK never sent if the 5 ms timer fired while previous ACK still queued; flow table slowly fills; `tcp_ack_drop_enable/cnt` now actually applied and writable (throughput/latency bug).
- `7abc603489` errors now logged by default (`wl_err` was compiled out unless `DEBUGMODE`); new `debug_level` module parameter. `e73145a3b0` makes `disable_powersave` writable in sysfs.

Still-open issues listed at the end of PR #28 (not fixed anywhere):
1. `sprdwl_fw_power_down_ack` agrees to power down while frames are still being received (mitigation: `disable_powersave=1`, PR #18, commit `84a3017437`).
2. Block-ack request events ignored (`reorder.c`) → 100 ms reorder-timer stall per abandoned frame.
3. `MMC_CAP2_SDIO_IRQ_NOTHREAD` stripped on Rockchip (n/a for us).
4. On >= 7.1 `wl-reg-on`/`bt-reg-on` are no longer found by `devm_gpiod_get_optional()` (properties lack `-gpios` suffix). On Allwinner `mmc-pwrseq` owns the enable pin, so limited impact.

No open issues on the repo (issues tab is unused; everything lands as PRs). Earlier relevant fixes already in our pin: 7.3 compatibility (`b64c5d6c36`, PR #20), 7.2 (`02e52520ce`), 7.1 gpiod `int_ap` (PR #1, #13), `tty_alloc_driver` ERR_PTR (PR #8), use-after-free in `mtty_probe` error path (PR #4), connect/roam state reconciliation + firmware event validation (PRs #17, "harden connection setup"), removal of CPUFreq interaction (PR #9), "open files from init root on 7.3" (PR #23 — required because 7.3 kthreads no longer see the rootfs; without it firmware/ini loads fail).

### 2.2 Bluetooth: hci0 stuck in HCI_SETUP / `Opcode 0x080f failed: -22`
- Root cause: `bt_configure_pskey.ini` advertised LMP Park; firmware rejects `Write Default Link Policy` with PARK. Fixed in firmware by https://github.com/armbian/firmware/pull/154 (merged 2026-10-28, tested on OPi 3B with 7.3.0-edge). **Our deb already carries the fixed file** (`0xBF, 0xFE`). The kernel quirk patch (sec. 1.4) is the belt-and-braces fix for the same symptom; the two are compatible. Independent confirmation of the ini approach: https://github.com/LinuxMint-User/uwe5622-ng (states a one-byte ini change replaces the kernel patch).
- The firmware only picks the new pskey up on a cold start of the BT core — a reboot, not a service restart (PR #154 note).
- Missing `bt_configure_*.ini` → controller reports Manufacturer 0x0000 and no LE (aa-proxy buildroot PR #19 observations: https://github.com/aa-proxy/buildroot/pull/19).
- BT can only be attached after the shared WCN firmware has booted (i.e. after `wlan0` exists); aa-proxy polls for `wlan0` before `hciattach`. Our unit only orders `After=bluetooth.service` and does not depend on `aw859a-wifi.service` or `/dev/ttyBT0` → race on slow boots; `RemainAfterExit=true` with `Type=simple` means a failed/early `hciattach_opi` is not retried.
- Historic reports (DietPi, 6.6.31 on Zero 2W, 2024): `hci0` absent until `hciattach_opi` is run; `sprdwl_ng` in modules-load competing with the service (https://dietpi.com/forum/t/orange-pi-zero-2w-bluetooth/21615). Armbian forum OPi 3 LTS 6.12/6.18 BT not working until newer images (https://forum.armbian.com/topic/58224-orangepi-3-lts-bluetooth-not-working/).
- No open-source replacement for `hciattach_opi` in Armbian. Alternatives found:
  - Reinerost/UWE5622-OpenWrt-Driver (https://github.com/Reinerost/UWE5622-OpenWrt-Driver, 6.18, mac80211 backports 7.2): moved the vendor HCI init (0xFCA0 PSKEY, 0xFCA2 RF, 0xFCA1 enable, synchronous waits) **into the `sprdbt_tty` kernel driver**, then uses plain BlueZ `btattach` on `/dev/ttyBT0`; includes the park-link workaround. This is the cleanest path to drop the blob but needs porting into armbian/uwe5622.
  - No serdev/`hci_uart` binding exists for this chip (transport is TTY-over-SDIO, not a UART), so a `btuart`/serdev driver is not applicable; `hciattach`/`btattach` with the N_HCI ldisc is the right model.

### 2.3 5 GHz / regulatory
- The chip does 2.4+5 GHz STA (`cfg80211.c` registers `NL80211_BAND_5GHZ`); the armbian README's "2.4 GHz only" is wrong.
- Driver sets `REGULATORY_CUSTOM_REG` and answers country hints from a private 7-country table (00, US, CN, NL, CZ, JP, TR); other countries fall back to world → DFS channels (52+) associate but pass almost no traffic / 4-way handshake times out, `iw reg get` shows `country 00: DFS-UNSET`; and the rule table pushed to firmware memcpy's the 96-byte kernel `struct ieee80211_reg_rule` into 28-byte firmware entries (only first rule survives). Out-of-tree patch `0001-unisocwifi-regdomain-from-cfg80211.patch` fixes both (built against armbian/uwe5622 `cc2835a` for 6.18.45, Zero 2W/3/3 LTS): https://github.com/SUPE4COOKIE/uwe5622-5ghz-fix — **not submitted to armbian/uwe5622** as far as documented.
- AP mode on 5 GHz: hostapd 2.11 completes setup but never transmits 5 GHz beacons on `sprdwl_ng` (hidden hotspot); hostapd 2.10 works; 2.4 GHz AP works (https://github.com/aa-proxy/buildroot/pull/19). OpenWrt backport notes: `channel auto` does not work, DFS/160 MHz/40 MHz-on-2.4 blocked, no per-station RSSI/rx rate (https://github.com/Medvedolog/opiz3-wlan-backport/releases/tag/opiz3-25.12.5-beta2).

### 2.4 Power save / first-connect delay
- After a cold boot the firmware can power down right after CONNECT so EAPOL frames go unanswered; AP deauths ~11 s later; adds 12-25 s to boot connect. `disable_powersave=1` module option (in our pin) avoids it (SUPE4COOKIE write-up; PR #28 open issue 1).

### 2.5 Other reports (older / other boards, for context)
- Kernel panics in `sprdwl_probe` (`get_loopcheck_status` NULL deref; SError in `sprdwl_msg_init`) on rk35xx vendor 6.1 / 6.6 / 6.12 with UWE5621DS; workaround blacklist (https://forum.armbian.com/topic/48528-kernel-panic-encountered-when-calling-modprobe-sprdwl_ng/). Not reproduced on H616.
- OPi Zero2 Armbian 6.1/6.4 era: chip not detected until DT + driver landed in 6.6.7 edge (Dec 2023); `sprdwl_ng: Unknown symbol get_custom_mac_address` when `sunxi_addr` missing; `regulatory.db` load error (https://forum.armbian.com/topic/30720-wifi-not-working-on-orangepi-zero-2/).
- unifreq/linux-6.18.y PR #96 imported the same `fa9d1a67` commit for Amlogic/UWE5621DS and needed heavy fixes (SDIO IRQ never arriving → RX polling, CMD53 refusals, offload crashes, clock cap 166 MHz). Amlogic-specific but shows SDIO host interaction is fragile (https://github.com/unifreq/linux-6.18.y/pull/96).
- Loopcheck (firmware heartbeat) miss blocking its own recovery; deleting interface before firmware finished disconnect crashes firmware (OpenWrt backport patches 310/330, Medvedolog).

### 2.6 Mainline status
- No mainline or linux-wireless/lore series for UWE5622/SC2355/sprdwl exists (searches via WebSearch returned only out-of-tree repos; lore.kernel.org itself is behind an Anubis challenge for fetch). Gunjan Gupta (Armbian sunxi maintainer) stated in 2023 there is nothing even in linux-next; nothing has changed since. The chip will stay out-of-tree.

### 2.7 Upstream armbian/build changes after our checkout
- None relevant. Last upstream touches: `extensions/uwe5622-allwinner.sh` 2026-08-26 (comment only), `aw859a-bluetooth.service` 2026-01-13, blobs 2026-01-31, `drivers_network.sh` pin bump 2026-10-13, `sunxi-7.3` patch rewrite 2026-10-31 — all already in our HEAD (`794f1d4`, 2026-11-01). Nothing newer on main for `packages/bsp/sunxi`, `sun50iw9.conf`, `orangepizero2.csc` as of today.

---

## 3. Recommended changes

1. **Bump the driver pin to armbian/uwe5622 master `f88cd0d25f`** (2026-10-31) in `lib/functions/compilation/patch/drivers_network.sh:555`: `local uwe5622ver='commit:f88cd0d25f...'` (use the full 40-char sha from `git ls-remote https://github.com/armbian/uwe5622 master`). Rationale: two memory-corruption fixes, rfkill reload oops, TCP ACK stall, cfg80211 unregister warning, errors logged by default. Diff is confined to the driver dir (14 files, ~+330/-140), CI-built for sunxi 6.1-7.3. Re-run the 7.3.1 compile check; expect zero new warnings (`sdiohal_ctl.c:758` cosmetic warning remains).
2. **Carry the 5 GHz regulatory patch** (SUPE4COOKIE `0001-unisocwifi-regdomain-from-cfg80211.patch`) as an Armbian patch or get it merged upstream, if 5 GHz on non-US/CN/NL/CZ/JP/TR regdomains or DFS channels matters. Verify it applies on top of `f88cd0d` (`cfg80211.c` and `main.c` changed in PR #28).
3. **Module options**: ship `/etc/modprobe.d/sprdwl_ng.conf` with `options sprdwl_ng disable_powersave=1` (fixes cold-boot EAPOL power-down; costs idle power) — or at least document it. After the pin bump, `tcp_ack_drop_enable`/`debug_level` become usable for tuning/diagnosis.
4. **Service hardening** (`packages/bsp/sunxi/aw859a-*.service`):
   - `aw859a-wifi.service`: `Type=oneshot` + `RemainAfterExit=yes` (modprobe is not a forking daemon); add `ExecStartPre=/sbin/modprobe sunxi_addr` for explicitness; consider `ExecStartPost=/bin/sh -c 'for i in $(seq 1 30); do [ -d /sys/class/net/wlan0 ] && exit 0; sleep 1; done; exit 1'` so dependents can order on it.
   - `aw859a-bluetooth.service`: add `Requires=aw859a-wifi.service After=aw859a-wifi.service`, `ConditionPathExists=/dev/ttyBT0` is not enough (device appears late) → `Restart=on-failure RestartSec=2 StartLimitBurst=10`, and `ExecStartPre=/sbin/modprobe sprdbt_tty`. Keep `Type=simple` (hciattach_opi stays in foreground only with `-n`; without `-n` it daemonizes → prefer `Type=forking` or add `-n`). `RemainAfterExit` is meaningless with `Type=simple`; drop it.
   - Optional: switch to upstream's `sprd-bluetooth` script + `hciattach_opi_arm64_upstream` (BD address from eMMC/SD CID hash in `/etc/default/sprd_bt_addr`) to drop the `sunxi_addr` dependency for BT; but WiFi still needs `sunxi_addr` for `get_custom_mac_address`, so there is little gain on this board. Keep current blob.
5. **Firmware**: nothing to change; `armbian-firmware` from `armbian/firmware` master already ships `uwe5622/wcnmodem.bin`, `wifi_2355b001_1ant.ini` (+ root symlinks), and park-fixed `bt_configure_pskey.ini`/`bt_configure_rf.ini`. Make sure the image uses a firmware deb built on/after 2026-10-28 (ours is 2026-10-29). Do not install Debian `firmware-*`/`linux-firmware` alongside (Conflicts).
6. **Kernel patches**: keep `drv-bluetooth-hci-sprd-broken-park-link-quirk-v6.16-plus.patch` (harmless with the fixed ini, protects against stale ini). Keep sunxi-info + sunxi-addr patches (hard dependency of `sprdwl_ng`).
7. **Longer term**: evaluate porting Reinerost's in-kernel BT vendor-init into `tty-sdio` so BlueZ `btattach -B /dev/ttyBT0 -P h4 -S 1500000` replaces the closed `hciattach_opi` blob; and ask upstream to extend the start-up chip-ID retry (`adb85e1956`) to the Allwinner path (it is Rockchip-only but the -110 symptom is generic).
8. Cosmetic: fix the `pub_gpio_desc` unused-variable warning upstream (move declaration under `CONFIG_WCN_PARSE_DTS`).

---

## 4. Test checklist on the board (Orange Pi Zero2, 7.3.1 edge)

### 4.1 Bring-up / modules
- [ ] `dmesg | grep -iE 'mmc1|sdio'` — mmc1 enumerates an SDIO card (vendor 0x0000/0x2355-ish), no CRC errors; note bus speed (`cat /sys/kernel/debug/mmc1/ios`).
- [ ] `lsmod | grep -E 'uwe5622_bsp_sdio|sprdwl_ng|sprdbt_tty|sunxi_addr'` — all four loaded; `systemctl status aw859a-wifi aw859a-bluetooth` active.
- [ ] `dmesg | grep -iE 'WCN|marlin|sprdwl|chipid'` — firmware path `/lib/firmware/uwe5622/wcnmodem.bin`, chip id `0x2355b001`, no `-110`/timeout, no `download` failures; `wifi ini path = /lib/firmware/wifi_2355b001_1ant.ini`.
- [ ] `cat /sys/class/addr_mgt/addr_wifi /sys/class/addr_mgt/addr_bt`; `ip link show wlan0` MAC is non-zero, stable across reboots, not 00:00:…; `ethtool -i wlan0` driver `sprdwl_ng`.
- [ ] `dmesg | grep -iE 'field-spanning|Bad page state|WARNING|Oops|rfkill'` — must be empty (regressions fixed by PR #28).
- [ ] Reload test: `systemctl stop aw859a-bluetooth; rmmod sprdbt_tty sprdwl_ng uwe5622_bsp_sdio; modprobe sprdwl_ng sprdbt_tty` → no oops, no bad pages, `wlan0` back, `cat /proc/sys/kernel/tainted` unchanged.
- [ ] Soft reboot x5 and cold boot x5: wlan0 present each time (watch for the enumerate-but-no-chip-ID case).

### 4.2 WiFi STA
- [ ] `iw dev wlan0 scan | grep -E 'SSID|freq'` — sees 2.4 and 5 GHz networks; repeat 10x, count failures/empty scans.
- [ ] `iw reg get` — phy regdomain follows `iw reg set XX` / wpa_supplicant `country=`; note if stuck on `00` (regulatory bug, sec. 2.3).
- [ ] Connect WPA2-PSK 2.4 GHz via NetworkManager/wpa_supplicant; measure time from `modprobe` to DHCP lease (cold boot); compare with `disable_powersave=1`.
- [ ] Connect WPA2/WPA3 with PMF optional and required (IGTK path) — check `dmesg` for `field-spanning write` and that traffic flows.
- [ ] Connect 5 GHz non-DFS (ch 36-48) and DFS (ch 52+) at VHT80 → `iw dev wlan0 link`, `ping -c 100` loss, `iperf3 -c <host> -t 60` and `-R`; expect ~tens of Mbit/s on 2.4, higher on 5 GHz; DFS throughput near zero indicates the regulatory bug.
- [ ] Idle 1 h connected: no disconnect/`deauth` in `journalctl -u wpa_supplicant`/NM; `ping` RTT stable (power-save stalls show as 100 ms+ spikes / block-ack issue).
- [ ] Roaming/`iw dev wlan0 disconnect` + reconnect 20x: no cfg80211 WARNING, no firmware reset (`loopcheck`).
- [ ] TCP latency test (`iperf3` with small window, interactive ssh) before/after pin bump (TCP ACK stall fix); try `echo 0 > /sys/module/sprdwl_ng/parameters/tcp_ack_drop_enable`.
- [ ] Suspend/resume (`rtcwake -m mem -s 20` if crust/ATF allows on H616; else `systemctl suspend`): WiFi reconnects; no hang; dmesg clean. Note: H616 mainline suspend is itself limited — record whether the hang is WiFi-related by testing with modules unloaded.

### 4.3 WiFi AP mode
- [ ] `iw list | grep -A10 'Supported interface modes'` includes AP; `hostapd` 2.4 GHz WPA2 (fixed channel, `hw_mode=g`) → client associates, `iperf3` works.
- [ ] 5 GHz AP (`hw_mode=a`, ch 36, `ieee80211ac=1`): check beacons visible from a client; with hostapd 2.11 expect invisible AP (sec. 2.3); retest with hostapd 2.10 or NM hotspot. `channel=0`/ACS expected not to work.
- [ ] AP + STA concurrently (if needed) — not supported by vendor driver without the OpenWrt repeater patches; expect failure.

### 4.4 Bluetooth
- [ ] `ls -l /dev/ttyBT0` exists after WiFi firmware boots; `rfkill list` shows bluetooth unblocked.
- [ ] `systemctl status aw859a-bluetooth`; `hciconfig -a` → `hci0` `UP RUNNING`, BD address matches `/sys/class/addr_mgt/addr_bt`, Manufacturer not 0x0000, features `0xbf 0xfe …` (park bit clear), link policy `RSWITCH SNIFF`.
- [ ] `dmesg | grep -i 'hci0'` — no `Opcode 0x080f failed: -22`, no `HCI_SETUP` timeout.
- [ ] `bluetoothctl list` shows controller; `bluetoothctl scan on` finds BR/EDR and LE devices (`bluetoothctl scan le`).
- [ ] Pair + connect a keyboard/mouse (HIDP) and an A2DP speaker; `bt-device -l`; reconnect after power cycle of peripheral.
- [ ] `btmon` while running `hciattach_opi` manually (`systemctl stop aw859a-bluetooth; hciattach_opi -n -s 1500000 /dev/ttyBT0 sprd`) to capture vendor PSKEY/RF uploads.
- [ ] BT + WiFi coexistence: `iperf3` on 2.4 GHz while streaming A2DP; note audio dropouts/throughput drop.
- [ ] Service restart (`systemctl restart aw859a-bluetooth`) and `rmmod sprdbt_tty; modprobe sprdbt_tty` → no oops, rfkill still responsive (PR #28 fixes).
- [ ] Boot-order race: 10 cold boots, `hci0` present each time without manual intervention; if not, apply the service ordering from sec. 3.4.

---

## 5. Source index
- armbian/uwe5622 repo, commits, PR #28: https://github.com/armbian/uwe5622 , https://github.com/armbian/uwe5622/pull/28 ; PR #23 (7.3 init-root): https://github.com/armbian/uwe5622/pull/23 ; PR #20 (7.3 compat): https://github.com/armbian/uwe5622/pull/20 ; PR #18 (`disable_powersave`): https://github.com/armbian/uwe5622/pull/18
- armbian/firmware PR #154 (park bit): https://github.com/armbian/firmware/pull/154 ; firmware tree: https://github.com/armbian/firmware/tree/master/uwe5622
- armbian/build: pin bump `912b89c7fa` (2026-10-13); BT fix `fe7b8eee12` (2026-01-13); new blob `642a75f5b3`; OPi 3 LTS `sprd-bluetooth` PR #9323: https://github.com/armbian/build/pull/9323
- 5 GHz regulatory fix: https://github.com/SUPE4COOKIE/uwe5622-5ghz-fix
- uwe5622-ng (zero-patch fork, 6.18/7.2, Zero 3): https://github.com/LinuxMint-User/uwe5622-ng
- OpenWrt port with in-kernel BT init + btattach: https://github.com/Reinerost/UWE5622-OpenWrt-Driver
- OpenWrt backport with loopcheck/disconnect fixes and AP-mode caveats: https://github.com/Medvedolog/opiz3-wlan-backport/releases/tag/opiz3-25.12.5-beta2
- hostapd 2.11 5 GHz AP regression, BT ini requirements, boot ordering: https://github.com/aa-proxy/buildroot/pull/19
- Amlogic import of the same commit with SDIO fixes: https://github.com/unifreq/linux-6.18.y/pull/96
- Armbian forum OPi Zero2 WiFi thread (2023): https://forum.armbian.com/topic/30720-wifi-not-working-on-orangepi-zero-2/ ; OPi 3 LTS BT (2026): https://forum.armbian.com/topic/58224-orangepi-3-lts-bluetooth-not-working/ ; rk35xx `sprdwl_ng` panic: https://forum.armbian.com/topic/48528-kernel-panic-encountered-when-calling-modprobe-sprdwl_ng/
- DietPi Zero 2W BT: https://dietpi.com/forum/t/orange-pi-zero-2w-bluetooth/21615
