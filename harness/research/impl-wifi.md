# UWE5622 (AW859A) WiFi/BT on Orange Pi Zero2 — implementation report

Date: 2026-11-01. Worktree: `/home/aruni/orangepizero2/wt-wifi` (armbian/build main `27a7f72`). Research input: `harness/research/uwe5622-status.md`. Nothing was pushed; nothing touched the board.

Scope note (from the user, mid-task): the WiFi acceptance test is an SSID scan only. The driver/service fixes below are kept because they are correctness/stability issues; the board test plan (sec. 9) is trimmed accordingly and needs no network credentials.

---

## 1. Branches and commits

All topic branches are in the shared `.git` (visible from every checkout). Driver-side fixes depend on the pin bump, so those two branches start from it; the others start from `27a7f72` directly.

| Branch | Base | Commits | Content |
|---|---|---|---|
| (base) | `27a7f72` | `d5f8ee9` | cherry-pick of `ebcabca`: pin `uwe5622ver='commit:f88cd0d25ff624d853886c2db49963a32042d1ce'` in `lib/functions/compilation/patch/drivers_network.sh` |
| `sunxi/uwe5622-services` | `27a7f72` | `d380e99` | item 3: `packages/bsp/sunxi/aw859a-wifi.service`, `aw859a-bluetooth.service` |
| `sunxi/uwe5622-powersave` | `27a7f72` | `d189fa4` | item 4: `extensions/uwe5622-allwinner.sh` ships `/etc/modprobe.d/sprdwl_ng.conf` |
| `sunxi/uwe5622-bt-wake` | `d5f8ee9` | `721a30c`, `1f7fdf3` | item 6 + item 1 cosmetic: two driver patches in `patch/kernel/archive/sunxi-7.3/patches.armbian/` + `series.conf` |
| `sunxi/uwe5622-regdomain` | `d5f8ee9` | `589775f` | item 2: regdomain patch in `patch/kernel/archive/sunxi-7.3/patches.armbian/` + `series.conf` |
| `wt-wifi-integration` | `27a7f72` | `1549ea9 eeb7564 0d0bebd b62a1fa b238f87 27cd8be` | linear: pin bump, services, powersave, bt-wake(2), regdomain. Only conflict was the adjacent `series.conf` insertions; resolved. Tree is clean. |

Author on all commits: `Arun Iyengar <aiyengar1990@gmail.com>`; the prepare-commit-msg hook added `Assisted-by:`/`Signed-off-by:` trailers.

Upstream-ready copies of the three driver changes (git-am format against armbian/uwe5622 `f88cd0d`, see sec. 3.3): `/home/aruni/orangepizero2/harness/research/uwe5622-upstream/000{1,2,3}-*.patch`.

---

## 2. Item 1 — compile check of the bumped driver on 7.3.1

Command: `ARMBIAN=/home/aruni/orangepizero2/wt-wifi WORK=/home/aruni/orangepizero2/kernel-check/work-wifi /home/aruni/orangepizero2/kernel-check/build-kernel.sh` (rootless; re-extracts linux-7.3.1, applies the 690 active `sunxi-7.3/series.conf` patches, injects armbian/uwe5622 at the commit named in `drivers_network.sh`, `linux-sunxi64-edge.config`, builds `Image modules` + Zero2 DTB through ccache). Logs: `work-wifi/run1.log`, `work-wifi/build.log`.

**Result (pin `f88cd0d`, unpatched):** `patches applied: 690, failed: 0`; `make Image modules sun50i-h616-orangepi-zero2.dtb` finished with **0 errors**; `Image` (37.3 MB), the Zero2 DTB and all three driver modules were produced: `unisocwcn/uwe5622_bsp_sdio.ko`, `unisocwifi/sprdwl_ng.ko`, `tty-sdio/sprdbt_tty.ko`. Whole-kernel warning count 9, of which **exactly one** in `drivers/net/wireless/uwe5622`:

```
drivers/net/wireless/uwe5622/unisocwcn/sdio/sdiohal_ctl.c:758:27: warning: unused variable 'pub_gpio_desc' [-Wunused-variable]
```

Judgement: **not a real bug** — same cosmetic warning as before the bump (`pub_gpio_desc` is declared for >= 7.1 but only used inside `#ifdef CONFIG_WCN_PARSE_DTS`, which the Allwinner build does not define; the function is the debugfs `sdio_int_rx/tx` test hook, never run in normal operation). PR #28's 13 commits introduced **no new warnings** on 7.3.1. The new pin builds, so no compatibility patch was needed. The warning is nevertheless fixed in `1f7fdf3` (sec. 6) and offered upstream.

(Side note: the shared `kernel-check/build-kernel.sh` was edited by another agent at 21:59 while my run was in flight — the wrapper reported `line 87: syntax error` *after* the make had finished; `build.log` ends with the final `BTF [M]` lines and `grep -cE " error:|Error [0-9]"` is 0, so the result above stands.)

**Result with the three driver patches applied** (`patch -p1` of the `patches.armbian/` files from `wt-wifi-integration` into the same tree, then `make drivers/net/wireless/uwe5622/` and `make modules`, logs `work-wifi/build-patched-dir.log`, `build-patched-modules.log`): the three affected objects (`wcn_boot.o`, `sdiohal_ctl.o`, `cfg80211.o`) recompiled with **0 warnings, 0 errors**; `uwe5622_bsp_sdio.ko` and `sprdwl_ng.ko` relinked (BTF ok, no undefined symbols). Sanity: the new `no allwinner,sunxi-btlpm node` string is in `uwe5622_bsp_sdio.ko`; the old `no correct RegDomain` string is gone from `sprdwl_ng.ko`. The uwe5622 directory is now warning-free on 7.3.1.

---

## 3. Item 2 — 5 GHz / regulatory fix

### 3.1 Where a driver fix must live in Armbian's flow
`kernel_main_patching()` (`lib/functions/compilation/kernel-patching.sh:79`) first runs `kernel_drivers_create_patches` (`patch/drivers-harness.sh`), which executes every `driver_*()` in `drivers_network.sh` against a scratch tree and turns the result (the whole copied `drivers/net/wireless/uwe5622/` tree, Kconfig/Makefile hooks) into one cached patch `cache/patch/kernel-drivers/sha1_<kernel>_<family>_<branch>_<hash>.patch`. That file is handed to the Python patcher as `EXTRA_PATCH_FILES_FIRST` (`kernel-patching.sh:52`) and `lib/tools/patching.py:189` applies it **before** `series.conf` and the per-dir patches (`ALL_PATCH_FILES_SORTED = PATCH_FILES_FIRST + SERIES_PATCH_FILES + NORMAL_PATCH_FILES`). So a normal patch under `patch/kernel/archive/sunxi-7.3/patches.armbian/` touching `drivers/net/wireless/uwe5622/**` is legitimate and is applied on top of the injected driver. Verified by dry-running all three driver patches against the injected 7.3.1 tree (`patch -p1 --dry-run`: clean) and by the compile in sec. 2.

Options weighed:
- (a) Armbian patch under `patches.armbian/` — zero infrastructure, visible in `git log` of armbian/build, but Armbian prefers driver fixes in armbian/uwe5622 (that is why the `reference/` patch stack was folded into the repo), and the patch must be re-added to every `sunxi-6.x` archive that wants it.
- (b) Fork `github.com/SomeComputerGuy/uwe5622` and point the pin at it — works (`fetch_from_repo "$GITHUB_SOURCE/armbian/uwe5622"` would change to the fork URL) but upstream armbian/build would never merge a pin to a personal fork, and the cache key hashes `drivers_network.sh`, so every pin change invalidates all kernels' driver-patch caches.
- (c) PR to armbian/uwe5622 (CI builds sunxi64 current/edge/legacy, rockchip64, rk35xx via `.github/workflows/kernel-build.yml`), then bump the pin.

Chosen: **(c) with (a) as the interim carrier** — exactly what the commit messages say. The `patches.armbian/` files are dropped when the pin is bumped past the merge.

### 3.2 The fix
SUPE4COOKIE's `0001-unisocwifi-regdomain-from-cfg80211.patch` (https://github.com/SUPE4COOKIE/uwe5622-5ghz-fix, GPL-2.0, written against `cc2835a`) applies to `f88cd0d` **unchanged** (`git am` clean; PR #28 did not touch the notifier). It is carried as `patches.armbian/drv-net-wireless-uwe5622-regdomain-from-cfg80211.patch` with the paths re-rooted at `drivers/net/wireless/uwe5622/` and an Origin/Upstream note in the header; author kept as SUPE4COOKIE, my Signed-off-by added.

What it changes in `unisocwifi/cfg80211.c`:
- New guard `SPRDWL_CFG80211_REGDB` (kernel >= 4.15 and no `CUSTOM_REGDOMAIN`): compiles the *cfg80211-driven* `sprdwl_reg_notify()` variant (the one that used to need `CONFIG_CFG80211_INTERNAL_REGDB`, gone since 4.15) and compiles out the private path: `reg_domain.h` include, `getRegdomainFromSprdDB()` lookup, `REGULATORY_CUSTOM_REG`, `apply_custom_regulatory()` of the driver's "00" world table in `sprdwl_setup_wiphy()`.
- New `sprdwl_fill_reg_rule()` copies `freq_range`, `power_rule`, `flags & GENMASK(16,0)`, `dfs_cac_ms` field by field into `struct unisoc_reg_rule` (12+8+4+4 = 28 bytes, `cfg80211.h:143`) and sizes the `WIFI_CMD_SET_REGDOM` buffer by `sizeof(rd->reg_rules[0])` instead of `sizeof(struct ieee80211_reg_rule)` (96 bytes on 7.3, includes `wmm_rule`/`psd`). Before, only rule 0's frequencies were intact; rule 1..n were read by the firmware from mis-aligned offsets (WMM params where it expected flags/CAC time).
- `intf` is now only declared under `STA_SOFTAP_SCC_MODE` (avoids an unused-variable warning in the new path).
- I checked the one thing the old path did that the new one does not: under `CP2_RESET_SUPPORT` (defined in `unisocwifi/Makefile:32`) it saved the country-IE request into `priv->sync.request`. That field is written there and never read anywhere in the driver (grep), so nothing is lost.

### 3.3 Behaviour change on the board
- `iw reg get` before: `global country XX: DFS-ETSI` (whatever cfg80211 has) but `phy#0 country 00: DFS-UNSET` for every alpha2 outside `00 US CN NL CZ JP TR`, because the wiphy was `REGULATORY_CUSTOM_REG` and the notifier bailed out with "no correct RegDomain". After: no `phy#0` self-managed block — the phy follows the global domain; `iw reg set DE`, `wpa_supplicant country=`, and the AP's country IE (initiator `NL80211_REGDOM_SET_BY_COUNTRY_IE`) all apply, and the notifier logs `sprdwl_reg_notify DE initiator 3 hint_type 0` plus one `… KHz - … KHz @ … KHz flags …` line per rule actually sent to the firmware.
- 5 GHz channel list (`iw list`/`iw phy phy0 channels`): follows `regulatory.db` for the active country — DFS channels 52-64/100-144 flagged `radar detection` with the right CAC time instead of `DFS-UNSET`; TX power limits per rule instead of the firmware's defaults from a garbage table.
- DFS channels: before, the station could associate on ch 52+ but the firmware, told by a corrupt rule table that those channels were not allowed/had odd flags, passed almost nothing (4-way handshake timeout, 11 s deauth, fallback to 2.4 GHz — SUPE4COOKIE's observation behind an SFR router). After, the firmware has the rules it expects; the author soaked ch 52 VHT80 for 10 min with zero loss on a Zero 2W/6.18.45. **Not board-tested here** (out of scope per the trimmed test plan; needs a 5 GHz DFS AP). Scan results (what we will test) are unaffected either way: scanning worked before too.
- Fallback for countries missing from `regulatory.db`: cfg80211's world domain (`00`), same as every in-tree driver; the driver's own 7-entry table is no longer consulted.
- Also dropped: the `wrong country` / `Error, no correct RegDomain` error lines at every country hint.

### 3.4 Upstreaming
Push `harness/research/uwe5622-upstream/0001-*.patch` as a PR to https://github.com/armbian/uwe5622 (branch suggestion in a `SomeComputerGuy/uwe5622` fork: `regdomain-from-cfg80211` = `f88cd0d` + this one commit; CI must stay green for sunxi64 legacy/current/edge, rockchip64, rk35xx — the patch is kernel-version-neutral and only touches `unisocwifi/cfg80211.c`). Credit SUPE4COOKIE as author (the patch is already in git-am form with their From:). Once merged, bump the pin and delete `patches.armbian/drv-net-wireless-uwe5622-regdomain-from-cfg80211.patch` + its `series.conf` line.

---

## 4. Item 3 — service hardening (`sunxi/uwe5622-services`, `d380e99`)

Both units are installed by `extensions/uwe5622-allwinner.sh` (`post_family_tweaks_bsp__add_uwe5622_services`) into the BSP of every board that enables the extension: `orangepizero2`, `orangepizero2w`, `orangepizero3`, `walnutpi-zerow`, `walnutpi-1b`, `walnutpi-1b-ddr3`, `walnutpi-box` (grep of `config/boards`). `orangepi3-lts.conf` has its own `sprd-bluetooth.service` and is untouched. `sun50iw9.conf family_tweaks_s()` still enables `aw859a-bluetooth.service` redundantly — harmless, left alone.

`aw859a-wifi.service` — before: `Type=forking`, `ExecStart=/sbin/modprobe sprdwl_ng`, `RemainAfterExit=yes`, `TimeoutSec=0`, obsolete `SysVStartPriority=99`. modprobe never forks a daemon, so systemd waited for a non-existent main PID; the unit only became active because the process exited. After: `Type=oneshot` + `RemainAfterExit=yes` (semantically what it does and what lets `aw859a-bluetooth` order on it), `TimeoutStartSec=0` kept (the firmware download runs inside modprobe and cannot be killed meaningfully), `SysVStartPriority` dropped. `sunxi_addr` and `uwe5622_bsp_sdio` are still pulled in by modprobe dependency.

`aw859a-bluetooth.service` — before: `After=bluetooth.service` only; `Type=simple`; `ExecStart=/usr/bin/hciattach_opi -s 1500000 /dev/ttyBT0 sprd` (no `-n`); `RemainAfterExit=true`. Problems (as the research flagged): without `-n` hciattach daemonises after the vendor init, so the tracked process exits and the unit shows "active (exited)" whether or not hci0 came up; `RemainAfterExit` does nothing for `Type=simple`; a failed init (firmware not booted yet, `/dev/ttyBT0` not created yet by udev) is never retried; no relation to the WLAN unit although the BT core shares the WCN firmware. After:
- `Requires=aw859a-wifi.service`, `After=aw859a-wifi.service bluetooth.service` — WCN firmware already running, `sunxi_addr` loaded. (Trade-off: `Requires=` means a masked WLAN unit also stops BT. `Wants=` would be the softer choice; `Requires` was the requested semantics and matches the shared-firmware reality.)
- `ExecStartPre=/sbin/modprobe sunxi_addr` (kept; the blob reads `/sys/class/addr_mgt/addr_bt`), `ExecStartPre=/sbin/modprobe sprdbt_tty` (explicit; it is also in `MODULES` via the extension), `ExecStartPre=/usr/bin/timeout 30 /bin/sh -c 'until [ -c /dev/ttyBT0 ]; do sleep 1; done'` — note `/dev/ttyBT0` is created when `sprdbt_tty` probes its hard-coded `mtty` platform device (`tty-sdio/tty.c:676`, not gated on firmware boot), so the wait covers module load + udev latency; the HCI init itself needs the BT core powered, which `rfkill unblock all` does (`rfkill.c bluetooth_set_power → start_marlin(MARLIN_BLUETOOTH)`).
- `ExecStart=/usr/bin/hciattach_opi -n -s 1500000 /dev/ttyBT0 sprd` — the blob advertises `[-n]` in its usage string (`strings` of `hciattach_opi_arm64`), so it stays in the foreground, `Type=simple` is now correct, `RemainAfterExit` removed.
- `Restart=on-failure`, `RestartSec=3`, `StartLimitIntervalSec=300`, `StartLimitBurst=10` — a failed init exits 1 ("Can't initialize device") and is retried for up to ~5 min; when hciattach dies later (controller gone) it is reattached.
No `$` is used in the unit (systemd would expand it), and `timeout`/`sh` paths are the Debian/Ubuntu merged-usr ones.

---

## 5. Item 4 — power save decision (`sunxi/uwe5622-powersave`, `d189fa4`)

Decision: **ship `options sprdwl_ng disable_powersave=1` in the BSP for every board using the extension** (implemented in `post_family_tweaks_bsp__add_uwe5622_services`: `${destination}/etc/modprobe.d/sprdwl_ng.conf`, with a comment pointing at armbian/uwe5622 PR #18/#28). Reasoning:
- The defect is in the firmware, not board-specific: `sprdwl_fw_power_down_ack()` (`unisocwifi/cmdevt.c:3221`) acknowledges the chip's power-down request even while frames are in flight; PR #28 lists it as open issue 1 with no fix in sight. It bites every UWE5622 user on first connect after cold boot (12-25 s, SUPE4COOKIE) and as RX stalls on idle links.
- The parameter exists in the pinned driver (`main.c:1661`, `0644` so it is also switchable at runtime via `/sys/module/sprdwl_ng/parameters/disable_powersave`, PR #28 `e73145a3b0`).
- Cost: idle power on a chip soldered to mains/USB-powered SBCs — acceptable as a default; a user who wants power save adds a later-sorting file in `/etc/modprobe.d/` (modprobe reads all files, last `options` wins) or edits the shipped one. The BSP deb does not list it as a conffile (`armbian-bsp-cli-deb.sh` has a fixed candidate list), so a BSP upgrade overwrites a local edit — same as the other `/etc/modprobe.d` files boards ship (`bananapim4berry.conf`, `radxa-zero3.conf`); documented in the commit message.
- Consequence for us: `/home/aruni/orangepizero2/userpatches/customize-image.sh` step 3 writes the identical `/etc/modprobe.d/sprdwl_ng.conf`; once the BSP route is in the image it is redundant (same file name, so it simply overwrites with the same content). Not changed here (outside the worktree) — drop step 3 when this lands.

---

## 6. Item 6 — `WCN_ERR: dts node for bt_wake not found` (`sunxi/uwe5622-bt-wake`, `721a30c`)

Root cause (new pin, `unisocwcn/platform/wcn_boot.c`): the Allwinner build defines `CONFIG_AW_BOARD`, `CONFIG_BT_WAKE_HOST_EN`, `CONFIG_WL_WAKE_HOST_EN` but **not** `CONFIG_WCN_PARSE_DTS` (`unisocwcn/Makefile:307-316`). In `marlin_parse_dt()` the non-DTS branch (lines 1870-1879) sets `bt_wl_wake_host_en |= BIT(BT_WAKE_HOST)` and then calls `marlin_registsr_bt_wake()` (line 1452), which looks for a node with compatible `allwinner,sunxi-btlpm` and, on >= 7.1, a GPIO via `fwnode_gpiod_get_index(np, "bt_hostwake", 0, GPIOD_IN, …)` — i.e. a `bt_hostwake-gpios` property (vendor BSP style). No mainline DT has that node → `WCN_ERR` + `-EINVAL`, `marlin_parse_dt()` returns early (so the `WL_WAKE_HOST` bit is never set either), probe logs `marlin2 parse_dt some para not config` and carries on. Side effects of the current state: the firmware is told `bt_wake_host_en=1` (`sdio_config`, line 2209) with nobody listening on the pin; `marlin_suspend()/marlin_resume()` call `enable_irq(0)/disable_irq(0)` (no-ops for IRQ 0, but wrong).

Is the pin wired on the Zero2? Yes. Orange Pi's vendor DT (`orangepi-xunlong/linux-orangepi`, branch `orange-pi-4.9-sun50iw9`, `arch/arm64/boot/dts/sunxi/sun50i-h616-orangepi-zero2.dts`), decoded (`<&pio port pin mux pull drive data>`, port 6 = PG):
- `wlan_regon` PG18 (matches our `mmc-pwrseq` reset-gpios), `wlan_hostwake` PG15 (mux 6 = EINT)
- `bt_rst_n` PG19
- `btlpm`: `uart_index=1`, `bt_wake` PG17 (output, 1), `bt_hostwake` PG16 (mux 6 = EINT input)
(UART1 PG6-PG9 is routed to the module but unused by the SDIO-TTY transport.)

Chosen fix: **quiet it properly in the driver**, generic for all boards: the missing node is logged once at info level (`no allwinner,sunxi-btlpm node, bt_hostwake irq not used`), the function returns `-ENODEV`, and `marlin_bt_wake_int_en()/dis()` are guarded on `bt_wake_host_int_num != 0`. Behaviour (bits sent to firmware, early return) is deliberately unchanged so nothing that currently works on hardware can regress. Not done: adding a `bt-lpm { compatible = "allwinner,sunxi-btlpm"; bt_hostwake-gpios = <&pio 6 16 GPIO_ACTIVE_HIGH>; }` node to the Zero2 DT. It would make the driver `request_irq()` PG16 (rising) and `dev_pm_set_wake_irq()` it — a suspend-path change (wake source on a GPIO IRQ through sunxi-pinctrl) that I cannot validate without the board, with no benefit for a device that does not use suspend. The exact node is documented in the patch header for whoever wants it; the Zero3/Zero2W pins would need their vendor DTs checked first.

Also on this branch (`1f7fdf3`): the only compiler warning in the driver, `sdiohal_ctl.c:758 unused variable 'pub_gpio_desc'`, fixed by moving the declaration under `CONFIG_WCN_PARSE_DTS` (cosmetic; the function is a debugfs test hook). Both are in `harness/research/uwe5622-upstream/0002,0003-*.patch` for the armbian/uwe5622 PR.

---

## 7. Item 5 — Bluetooth without the blob: design note

**Current**: `hciattach_opi` (closed, 199632 B, libc only) opens `/dev/ttyBT0`, reads `/lib/firmware/bt_configure_pskey.ini` and `bt_configure_rf.ini`, reads the BD address from `/sys/class/addr_mgt/addr_bt`, sends vendor HCI commands and sets the N_HCI line discipline (H4). Strings in the blob: "SPRD Bluetooth init uart", "SPRD Bluetooth post process", "Set BDADDR", "Failed to write vendor init command".

**Reinerost's approach** (https://github.com/Reinerost/UWE5622-OpenWrt-Driver, WalnutPi 1B/H618, 6.18 + backports 7.2, tested BR/EDR + LE + discovery): move the vendor init into `sprdbt_tty`:
- `tty-sdio/bt_init.c` (497 lines, +8-line header): `request_firmware()` the two ini files (same files armbian-firmware ships), parse `key = v1, v2, …` lines, serialise the 176-byte PSKEY (`device_class, feature_set[16], device_addr[6], comp_id, …, bt_coex_threshold[8], other_rfu_w`) and the 252-byte RF table (`g_GainValue_A …`, `RF_common_rfu_w[5]`), then `hci_cmd_send_sync(0xFCA0 PSKEY)`, `0xFCA2 RF`, `0xFCA1 enable {00 00 01}`.
- Transport reuse: `hci_cmd_send_sync()` already exists in the armbian pin (`tty-sdio/woble.c:225`, WOBLE_FUN is on in `tty-sdio/Makefile`) — it writes via `marlin_sdio_write()` (`tty.c:753`) and waits on a semaphore that `woble_data_recv()` ups when a Command Complete for the pending opcode arrives. Important detail: in the armbian pin `mtty_rx_cb` calls `woble_data_recv()` *before* the "tty is closed" early-return (`tty.c` ~line 304), so the responses are seen even while no userspace has the tty open. Reinerost hooks `sprd_bt_init()` into `rfkill.c bluetooth_set_power()` right after `start_marlin(MARLIN_BLUETOOTH)` (power-off on failure).
- Userspace becomes stock BlueZ: `btattach -B /dev/ttyBT0 -P h4` (OpenWrt init script `files/uwe5622-bt.init`; `-S` is irrelevant for a TTY-over-SDIO). No serdev binding is possible (not a UART), so N_HCI/H4 via btattach is the right model.
- Park-link quirk: Reinerost masks LMP feature byte 1 bit 0 (Park) in the Read Local Supported Features (0x1003) Command Complete on the RX path (`tty.c` ~line 275). We do not need that: armbian/firmware PR #154 already cleared the bit in `bt_configure_pskey.ini` (`feature_set = 0xBF, 0xFE, …`, in our deb), and Armbian carries `drv-bluetooth-hci-sprd-broken-park-link-quirk-v6.16-plus.patch` as belt-and-braces. Keep both, skip the RX-path rewrite.
- Also in his tree but unrelated to BT init: a different `tty_alloc_driver` error check (older), `wakeup_source_register` in `lpm.c` (armbian pin handles >= 6.16 already), `ant_num` sysfs attr. Not needed.

**What a port into armbian/uwe5622 needs beyond copying `bt_init.c`:**
1. BD address: Reinerost sends `device_addr` from the ini verbatim (all boards identical — not acceptable). The blob reads `/sys/class/addr_mgt/addr_bt`. In-kernel: `#if IS_ENABLED(CONFIG_SUNXI_ADDR_MGT) get_custom_mac_address(1, "bt", addr)` exactly as `unisocwifi/main.c:1082` does for WLAN, with a `bdaddr=` module parameter / DT `local-bd-address` fallback for Rockchip boards (which use `sprd-bluetooth` + CID hash today). Alternatively leave the address to BlueZ (`btmgmt public-addr` is not supported by this firmware — the PSKEY is the only known way), so in-kernel it is.
2. Ordering: `rfkill unblock` must happen after the WCN firmware is downloaded (start_marlin does it) — same as today; `request_firmware()` from the rfkill callback runs in process context, fine; `bt_configure_*.ini` are in armbian-firmware root (`/lib/firmware/`), so `request_firmware(…, "bt_configure_pskey.ini")` finds them.
3. Confirm the blob sends nothing else: capture once with `btmon` while running `hciattach_opi -n` by hand (test plan item). Reinerost's working BR/EDR+LE on the same chip/firmware suggests the three commands are sufficient, but the "post process" string hints at an HCI Reset or baud command that is a no-op here.
4. Makefile: add `bt_init.o` to `sprdbt_tty-objs`; Kconfig: optional `CONFIG_TTY_OVERY_SDIO_VENDOR_INIT` (default y) so a distro can keep the blob flow.
5. Armbian side: `extensions/uwe5622-allwinner.sh` switches `ExecStart` to `/usr/bin/btattach -B /dev/ttyBT0 -P h4` (bluez package already installed), drops the blob install, and `orangepi3-lts.conf`'s `sprd-bluetooth` script does the same (its only other job is the BD address, which moves into the driver).

**Effort**: ~1 day to port and build (code is a copy + the BD-address hook + Kconfig), ~0.5 day board testing (hci0 up, BR/EDR + LE scan, pair, reload/rfkill cycles, 10 cold boots), plus upstream review time at armbian/uwe5622 and the armbian/build extension change. Risk: low-medium — synchronous HCI in the rfkill `set_block` callback blocks the rfkill mutex for up to 3 × CMD_TIMEOUT if the firmware does not answer (mitigate with a bounded total timeout and `stop_marlin()` on failure, as Reinerost does); any undocumented command the blob sends would show up immediately as a non-functional controller in testing. Not implemented now: it is not "small and safe" without a board and a `btmon` capture of the blob first.

---

## 8. Not changed / follow-ups
- `patch/kernel/archive/sunxi-6.18` (the `current` kernel; `KERNELPATCHDIR="archive/sunxi-${KERNEL_MAJOR_MINOR}"`) does not get the three driver patches — they apply there too (version-neutral) but were only compile-checked on 7.3.1. Add them to `sunxi-6.18/series.conf` after a 6.18 compile check, or wait for the upstream merge + pin bump which covers all kernels.
- `series.conf` line 693 `patches.armbian/drv-net-bluetooth-hci-ignore-def-link-policy-error.patch` is indented with spaces instead of a tab in upstream main (parses fine; cosmetic, not touched).
- `userpatches/customize-image.sh` step 3 becomes redundant (sec. 5).
- Zero2 DT `bt-lpm` node (sec. 6) if BT-wakes-host from suspend is ever wanted.
- Ask upstream to extend the Rockchip-only chip-ID retry (`adb85e1956`) to the Allwinner start path (research sec. 2.1) — not addressed here.

---

## 9. Board test plan (trimmed to scan-only WiFi acceptance; no credentials needed)

Image: built from `wt-wifi-integration` (edge 7.3.1, armbian-firmware >= 2026-10-28). Serial console attached for dmesg.

**A. Boot / modules**
- [ ] `lsmod | grep -E 'uwe5622_bsp_sdio|sprdwl_ng|sprdbt_tty|sunxi_addr'` — all four; `systemctl status aw859a-wifi aw859a-bluetooth` → wifi `active (exited)`, bluetooth `active (running)` with `hciattach_opi -n` as main PID; `systemctl show aw859a-bluetooth -p NRestarts`.
- [ ] `dmesg | grep -E 'WCN|marlin|sprdwl'`: firmware `/lib/firmware/uwe5622/wcnmodem.bin` loaded, chip id `0x2355b001`, **no** `WCN_ERR: dts node for bt_wake` (expect `WCN_INFO: no allwinner,sunxi-btlpm node, bt_hostwake irq not used`), no `-110`.
- [ ] `dmesg | grep -iE 'field-spanning|Bad page state|WARNING|Oops|BUG'` — empty (PR #28 fixes).
- [ ] `cat /sys/module/sprdwl_ng/parameters/disable_powersave` → `1`; `cat /etc/modprobe.d/sprdwl_ng.conf` is the BSP copy.
- [ ] `ip link show wlan0` — non-zero MAC, stable over 3 reboots (`sunxi_addr`).

**B. WiFi scan + regulatory**
- [ ] `iw dev wlan0 scan | grep -E 'freq|SSID'` — 2.4 GHz *and* 5 GHz SSIDs visible; repeat 10× (`for i in $(seq 10); do iw dev wlan0 scan | grep -c SSID; done`), no empty scans, no `scan timeout` in dmesg.
- [ ] `iw reg get` — only a `global` block (no `phy#0 … country 00: DFS-UNSET` self-managed block); `iw reg set DE; iw reg get` → `country DE: DFS-ETSI`; dmesg shows `sprdwl_reg_notify DE initiator 2 …` and per-rule `KHz … flags` lines (rule count ≥ 4, i.e. the rules reach the firmware); `iw phy phy0 channels` shows 5 GHz channels 52-64/100-140 with `radar detection` and CAC times, 2.4 GHz 1-13.
- [ ] Idle 30 min with wlan0 up (no association): `dmesg` clean, scan still works afterwards, `systemctl is-active aw859a-*` unchanged.

**C. Module unload/reload**
- [ ] `systemctl stop aw859a-bluetooth aw859a-wifi; rmmod sprdbt_tty sprdwl_ng uwe5622_bsp_sdio` → no `Bad page state`, no rfkill oops, `cat /proc/sys/kernel/tainted` unchanged (only the pre-existing bits); `systemctl start aw859a-wifi aw859a-bluetooth` → wlan0 + hci0 back, scan works. Repeat 3×.
- [ ] `systemctl restart aw859a-bluetooth` 5× → hci0 re-attached each time, `NRestarts` not climbing on its own.

**D. Suspend/resume**
- [ ] `rtcwake -m mem -s 20` (or `systemctl suspend` + power button) with modules loaded: board resumes, `dmesg` shows `marlin_suspend/resume enter` with no IRQ 0 warnings, scan works after resume, hci0 still up (or re-attached by the service). If the H616 does not resume at all, retest once with the four modules unloaded to separate SoC from WiFi issues (research sec. 4.2 note).

**E. Bluetooth**
- [ ] `hciconfig -a` → `hci0 UP RUNNING`, BD address = `/sys/class/addr_mgt/addr_bt`, Manufacturer ≠ 0x0000, features byte 1 `0xfe` (park bit clear), no `Opcode 0x080f failed` in dmesg.
- [ ] `bluetoothctl scan on` for 60 s → BR/EDR and LE devices listed (`bluetoothctl scan le` too).
- [ ] (For item 5 groundwork, optional) `systemctl stop aw859a-bluetooth; btmon -w /root/hciattach.btsnoop & hciattach_opi -n -s 1500000 /dev/ttyBT0 sprd` — record the vendor command sequence the blob sends.
- [ ] 5 cold boots: hci0 present each time without manual intervention; `journalctl -u aw859a-bluetooth` shows at most a couple of early retries.

Expected failure signatures: `iw reg get` still shows `phy#0 country 00` → regdomain patch not in the running kernel (`modinfo sprdwl_ng | grep -i srcversion`, rebuild); `hciattach` loops with "Can't initialize device" → BT core not powered (check `rfkill list`, `/sys/class/rfkill/*/state`) or stale `bt_configure_pskey.ini`.
