# Orange Pi Zero2 (H616/AXP305) — remaining boot warnings & configuration warts: implementation

Date: 2026-11-01. Base: armbian/build main `27a7f72`, kernel 7.3.1 + `patch/kernel/archive/sunxi-7.3`.
Worktree: `/home/aruni/orangepizero2/wt-cleanup`. Evidence: `harness/analysis/board-dump-1.txt`, `board-tests-1.txt`.

Branches (all from `27a7f72`, one topic each; nothing pushed):

| Branch | Commit | Content |
|---|---|---|
| `sunxi/cleanup-regulators` | `70d6464` | Zero2 DT: `r_pio` `vcc-pl-supply`, SPI-NOR `vcc-supply`; megous 0028: `phy-io` regulator truly optional |
| `sunxi/cleanup-drm-blend` | `363a4c0` | `drm/sun4i`: "pixel blend mode" property on DE2/DE3 planes + blender pre-multiply bits |
| `sunxi/cleanup-thermal` | `332babe` | `sun50i-h616.dtsi`: CPU zone passive 85 °C / hot 100 °C / critical 110 °C with cooling-maps for cpu0-3 |
| `sunxi/cleanup-bsp` | `ca5d512` | BSP drop-ins: journal-nocow tmpfiles override, cron `EXTRA_OPTS`, bluetooth `ConfigurationDirectoryMode` |
| `sunxi/cleanup-kconfig` | `6d9361d` | `linux-sunxi64-edge.config`: `CONFIG_REALTEK_PHY_HWMON=y` |
| `sunxi/cleanup-mmc-aliases` | `72f0cb3` | `sun50i-h616-orangepi-zero.dtsi`: `mmc0`/`mmc1` aliases (SD / SDIO WiFi) for stable `mmcblkN` (coordinator follow-up) |
| **`wt-cleanup-integration`** | `1a3b1e4..1a297ed` | the six above, cherry-picked linearly in that order (one trivial `series.conf` adjacency conflict, resolved: mmc-aliases then thermal after `zero2-zero3-add-wifi`) |

Compile check (rootless, cached): `ARMBIAN=/home/aruni/orangepizero2/wt-cleanup WORK=/home/aruni/orangepizero2/kernel-check/work-cleanup STAGE=all DT_CHECK="vcc-pl-supply vcc-supply cpu-alert cpu-hot cooling-maps" /home/aruni/orangepizero2/kernel-check/build-kernel.sh` — see "Build results" at the end. `build-kernel.sh` itself was not modified.

Coordination notes (things touching other agents' areas — nothing of theirs was edited):
* **wt-kernel (dwmac):** `sunxi/cleanup-regulators` edits `patches.megous/misc-7.3/0028-net-stmmac-sun8i-Add-support-for-enabling-a-regulato.patch` (probe/init/exit hunks of `dwmac-sun8i.c`). If wt-kernel replaces Armbian's reset-on-open patch with upstream `fee9c17671b6`, expect a trivial context conflict in `sun8i_dwmac_init()` — resolve by keeping both.
* **wt-kernel (PWM):** item 5 PWM subnodes are documented only; they disappear when the mainline `pwm-sun8i` v10 series replaces the vendor driver.
* **wt-kernel (GPU OPP):** the thermal patch does not add a GPU cooling map because the H616 `gpu` node has no `#cooling-cells`; once GPU OPPs/devfreq land, add `#cooling-cells = <2>` to `gpu` and a `gpu-thermal` map (same 85 °C trip) — one more hunk in the same patch.
* **wt-uboot:** KASLR seed (item 6) needs a U-Boot RNG; notes below, no U-Boot files touched.
* **wt-wifi:** the debugfs/tracing automount NOTICE (item 6) fires during AW859A/uwe5622 Bluetooth bring-up (17.1–18.4 s); see test steps to pin the accessor.

---

## 1. Dummy regulators (`vcc-pl`, `phy-io`, spi-nor `vcc`)

**Cause.** Three consumers request supplies that the Zero2 DT does not describe, so the regulator core substitutes the dummy regulator and `dev_warn`s:
* `sun50i-h616-r-pinctrl 7022000.pinctrl: supply vcc-pl not found` — pinctrl-sunxi requests `vcc-p<bank>` for every bank with pins in use; PL0/PL1 are the RSB bus to the AXP305. Mainline `sun50i-h616-orangepi-zero2.dts` sets `vcc-pc/pf/pg/ph/pi-supply` on `&pio` but nothing on `&r_pio`.
* `spi-nor spi0.0: supply vcc not found` — since 6.x the SPI-NOR core does `devm_regulator_get_enable(dev, "vcc")` (non-optional); `jedec,spi-nor` binding has an optional `vcc-supply`, not set for the Zero2 flash.
* `dwmac-sun8i 5020000.ethernet: supply phy-io not found` — **not mainline**: `patches.megous/misc-7.3/0028` (Ondřej Jirman, 2019, for Orange Pi 3's dual-rail RTL8211E) adds a second "phy-io" regulator with `devm_regulator_get()`, which is non-optional → dummy + warning on every board that does not describe it. The `phy-io-supply` property is not in the mainline binding.

**Schematic facts** (Orange Pi Zero2 H616 schematic v1.3, "ORANGEPI_ZERO2_H616 V1_3-202009", text extracted from the PDF): on the AXP305 sheet the power tree lists `ALDO1 → VCC-IO` (3.3 V, mainline name `vcc-sys`), `BLDO1 → VCC-PLL/VCC-PG/VCC18-HDMI` (1.8 V), `DCDCE → RGMII_3V3, VCC33-CARD` (3.3 V, mainline `vcc-eth-mmc`), `ALDO2 → VCC3V3-EXT`. The H616 power symbol has `VCC-IO` plus `VCC-PC`/`VCC-PG` pull-up nets; there is **no `VCC-PL` net** — PL0/PL1 (`RSB_SCK/RSB_SDA`) are in the VCC-IO domain. The SPI-NOR (`SPI_SO/SI/SCK/CE#`, on the PC bank whose `vcc-pc-supply` is already ALDO1) is a 3.3 V part on the same rail. The RTL8211F's `AVDD33`/`DVDD33` are all on `RGMII_3V3` = DCDCE, i.e. the PHY has a single 3.3 V rail (already `phy-supply = <&reg_dcdce>`), so a separate PHY-IO supply is simply not a thing on this board. (Other H616/H618 boards in mainline — bananapi-m4, kickpi-k2b — likewise wire `vcc-pl-supply` to their 3.3 V ALDO1.)

**Fix** (`sunxi/cleanup-regulators`, `70d6464`):
* New mainline-style patch `patches.armbian/arm64-dts-sun50i-h616-orangepi-zero2-add-pl-and-spi-nor-supplies.patch` (series line 571, after the last patch touching this dts):
  ```dts
  &r_pio { vcc-pl-supply = <&reg_aldo1>; };
  &spi0 { flash@0 { vcc-supply = <&reg_aldo1>; }; };
  ```
  ALDO1 is `regulator-always-on`, so this is descriptive only (no power-sequencing change). Candidate for upstream as-is.
* `patches.megous/misc-7.3/0028`: `devm_regulator_get()` → `devm_regulator_get_optional()`, `-ENODEV` → `NULL`, NULL-guarded `regulator_enable/disable` in init/exit paths (the regulator API does not accept NULL). Boards that do describe `phy-io-supply` (Orange Pi 3) are unaffected. The right fix would be in megous' tree; a DT-only workaround (`phy-io-supply = <&reg_dcdce>`) was rejected because the property is not a mainline binding.

**Test.** After flashing: `dmesg | grep -c 'using dummy regulator'` → `0` (was 3). `cat /sys/kernel/debug/regulator/regulator_summary | grep -E 'dummy|vcc-pl|spi0.0|phy-io'` → `regulator-dummy` has 0 users; `7022000.pinctrl-vcc-pl` and `spi0.0-vcc` listed under `vcc-sys`. Ethernet still comes up (`ip -br link show end0` UP, `ethtool end0 | grep Speed` 1000Mb/s); `cat /sys/class/mtd/mtd0/name` = `spi0.0`.

---

## 2. DRM: "[PLANE:n] pixel format with alpha exposed but blend mode not setup. Please fix." ×6

**Cause.** New in 7.x: `drm_mode_config_validate()` → `validate_blend_mode_for_alpha_formats()` warns for every plane that exposes an alpha format (ARGB8888, ABGR…, BGRA… are in `sun8i_ui_layer_formats` and the DE3 VI format list) without a `blend_mode_property`. `sun8i_ui_layer.c`/`sun8i_vi_layer.c` only create the `alpha` and `zpos` properties. This is a mainline sun4i problem (vanilla 7.3.1 behaves the same on every DE2/DE3 board); Jernej's `sun4i-drm-refactor` branch does not add the property either. The six planes are the DE33 planes of the two mixers (3 per mixer, created by `sun50i_planes.c` through the same `*_init_one()` helpers). Prior art: Roman Stratiienko "[PATCH v4 3/4] drm/sun4i: Add support for premulti/coverage blending mode handling" (2020) and a 2022 resend; Jernej's review asked to (a) not convert coverage→premul in the layer but "just mark it accordingly in BLD premultiply control register" and (b) compute the pipe-dependent bits in `sun8i_mixer_commit()` where zpos is known. That series was never merged.

Side finding: without the property KMS *assumes* "Pre-multiplied" (compositor/cursor ARGB content is premultiplied), but the driver leaves `BLD_PREMUL_CTL` (0x84) at 0 (= pipe not pre-multiplied → blender multiplies colour by alpha again), i.e. it has been blending ARGB overlays as "Coverage". So this is a (minor) correctness fix too.

**Fix** (`sunxi/cleanup-drm-blend`, `363a4c0`): `patches.armbian/drm-sun4i-add-pixel-blend-mode-property.patch` (series line 659), 4 files, +60/−8:
* `sun8i_mixer.h`: `SUN8I_MIXER_BLEND_PREMULTIPLY_EN(pipe)`, `SUN8I_LAYER_BLEND_MODES` (PREMULTI|COVERAGE|PIXEL_NONE), documented the "magic" `BLEND_MODE_DEF 0x03010301` (fs=1, fd=1−As = source-over on pre-multiplied data).
* `sun8i_ui_layer.c`, `sun8i_vi_layer.c` (DE3+ VI only — DE2 VI layers expose X-formats only and use FCC global alpha, so no property, pipe stays non-premultiplied): `drm_plane_create_blend_mode_property()`; alpha mode = `LAYER` for "None", else `PIXEL`/`COMBINED` as before.
* `sun8i_mixer.c` commit: `premul |= EN(zpos)` for planes whose `pixel_blend_mode == PREMULTI` (only planes that have the property), written to `SUN8I_MIXER_BLEND_PREMULTIPLY(bld_base)` next to ROUTE/PIPE_CTL. Not applied on the A523 RCQ path (`sun55i_de_commit`, returns earlier).
* Documented limitation: PREMULTI + plane alpha < opaque scales alpha but not colour (hardware has no stage to scale already pre-multiplied colour); opaque plane alpha (the normal case) is exact.

**Test.** `dmesg | grep -c 'blend mode not setup'` → `0`. With a monitor: `modetest -M sun4i-drm -p | grep -A3 'pixel blend mode'` lists `None/Pre-multiplied/Coverage` on the UI/VI planes (value 1 = Pre-multiplied). Visual: desktop mouse cursor (ARGB cursor plane, Armbian cursor-plane patch) has no dark fringe; `modetest -M sun4i-drm -s <conn>@<crtc>:1920x1080 -P <overlay_plane>@<crtc>:512x512+100+100@AR24` shows a correctly blended overlay. Regression check without monitor: HDMI hotplug/unplug still produces `card0-HDMI-A-1 connected/disconnected`.

---

## 3. "sun4i-drm display-engine: [drm] Cannot find any crtc or sizes" (×2 at boot, no monitor)

**Cause.** `drm_fb_helper.c: drm_fb_helper_single_fb_probe()` → `drm_info()` when the fbdev emulation client finds no enabled connector (nothing plugged into HDMI). It is logged once at probe (0.295 s) and once more when the connector poll/hotplug path re-runs the initial config (10.47 s). Mainline deliberately downgraded this to `drm_info`; with a monitor attached it does not appear, and with `loglevel=1` it never reaches the console. **Benign; no change.** (Suppressing it would mean not registering fbdev or special-casing the poll path — not upstreamable.)

**Test.** Boot with HDMI connected: the line is absent and `cat /sys/class/graphics/fb0/modes` shows the mode. Boot without: line present, `/dev/fb0` still exists (fbdev emulation stays armed for hotplug).

---

## 4. Thermal trips 60/70 °C

**Cause.** Not Armbian's cpu-dvfs patch (that patch, `arm64-dts-sun50i-h618-orangepi-zero2w-zero3-cpu-dvfs.dtsi.patch`, only adds regulator ramp delays to the Zero2W/Zero3). The 60/70 °C passive trips are **vanilla** `sun50i-h616.dtsi`: it copied the vendor BSP's power-allocator layout (`cpu_threshold`/`cpu_target`, `sustainable-power`), but (a) mainline cannot select a governor from DT and Armbian's config defaults to `step_wise` (`CONFIG_THERMAL_GOV_POWER_ALLOCATOR` is not even enabled; dmesg lists fair_share/bang_bang/step_wise/user_space), (b) there is no energy model (`dynamic-power-coefficient`) for H616 CPUs so IPA could not work anyway, and (c) the vanilla zone has **no `cooling-maps` at all**. Net effect on the board: the passive trips only switch the zone to 500 ms polling; **nothing ever throttles**; the only protection is the 110 °C critical shutdown (`board-tests-1.txt`: 1512 MHz held at 55–60 °C with `cool=0`, consistent). Comparison: vendor `orange-pi-5.4-sun50iw9/arch/arm64/boot/dts/sunxi/sun50iw9.dtsi` uses `cpu_threshold` 70 °C, `cpu_target` 90 °C, `sustainable-power 927`, `dynamic-power-coefficient 202`, and maps `cpu_target` → cpu0 + gpu (`contribution 1024`); mainline H6 uses a single passive `cpu_alert` 85 °C (hyst 2 °C) → cpu0-3 and critical 100 °C. The H616 datasheet does not publish a junction limit in text I could reach (linux-sunxi.org was returning 522 during this work); the justification therefore rests on the vendor's own 90 °C target / 110 °C shutdown and the H6 precedent, not on a Tj number.

**Fix** (`sunxi/cleanup-thermal`, `332babe`): `patches.armbian/arm64-dts-sun50i-h616-thermal-trips-and-cooling-maps.patch` (series line 575, after the other h616 dtsi patches) rewrites `cpu-thermal` trips:

| trip | temp | hyst | type | action |
|---|---|---|---|---|
| `cpu_alert` | 85 °C | 2 °C | passive | `cooling-maps/map0` → cpu0..cpu3 `THERMAL_NO_LIMIT THERMAL_NO_LIMIT` (step_wise steps cpufreq down) |
| `cpu_hot` | 100 °C | 2 °C | hot | notification only (sysfs/uevent) |
| `cpu_critical` | 110 °C | 0 | critical | orderly shutdown (unchanged, vendor value) |

`polling-delay(-passive)` and `sustainable-power` kept (the latter so IPA can be used later if an EM is added). GPU/VE/DDR zones unchanged (the `gpu` node has no `#cooling-cells` yet — see coordination note). Label rename: `cpu_threshold/cpu_target` → `cpu_alert/cpu_hot/cpu_critical`; no other in-tree file referenced the old labels (checked all h616/h618 dts in the patched tree).

**Test.** `for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type): $(cat $z/trip_point_*_temp | tr '\n' ' ') / $(cat $z/trip_point_*_type | tr '\n' ' ')"; done` → cpu-thermal `85000 100000 110000 / passive hot critical`; `ls /sys/class/thermal/thermal_zone<cpu>/ | grep cdev` → `cdev0` present with `cdev0_trip_point` = 0 (bound to the 85 °C trip). Throttling (optional, needs heat): `stress-ng --cpu 4 --timeout 300` while logging `cpuinfo_cur_freq` + `temp`; frequency must step down only if temp ≥ 85 °C and recover ≤ 83 °C; at the ~60 °C the board normally reaches, `cur_state` of cooling_device0 stays 0 (previously it would have stayed 0 at any temperature).

---

## 5. Platform devices without a driver

All of these are expected for a mainline DT; none indicates a missing driver on the H616, except the PWM subnodes which are an artefact of the vendor driver (wt-kernel):

| node | compatible | explanation | action |
|---|---|---|---|
| `3005000.hstimer` | `allwinner,sun50i-h616-hstimer`, `allwinner,sun20i-d1-hstimer` | `drivers/clocksource/timer-sun5i.c` is a `module_platform_driver` and *does* match the D1 fallback, but `CONFIG_SUN5I_HSTIMER` is `bool … if COMPILE_TEST` — selectable only through arch Kconfig, and arm64 `ARCH_SUNXI` selects `SUN4I_TIMER`/`SUN6I_R_INTC`/`SUNXI_NMI_INTC`, not it. The hstimer is redundant with the ARMv8 arch timer (clocksource/clockevents already provided; dmesg: `arch_sys_counter` selected). Node exists upstream for completeness (D1 needed it). | none (documented) |
| `3009000.timer` | `allwinner,sun50i-h616-timer`, `allwinner,sun8i-a23-timer` | `timer-sun4i.c` uses `TIMER_OF_DECLARE` (early init, no platform driver ever binds) and **is in use**: `clocksource: timer: mask: 0xffffffff …` at 0.000204 s is this timer, registered as secondary clocksource/sched source. | none (normal) |
| `opp-table-cpu` | `allwinner,sun50i-h616-operating-points` | Data node consumed via `operating-points-v2 = <&…>` by the OPP core / `sun50i-cpufreq-nvmem` (which bound and chose `speed3`). Root-level node with a compatible → platform device created, never bound; identical on every mainline board. | none (normal) |
| `psci`, `timer` (armv8) | `arm,psci-0.2`, `arm,armv8-timer` | Firmware/arch nodes initialised before the driver model. | none |
| `soc:pwm0..5@0300a000` | `allwinner,sunxi-pwm0..5` | Vendor-style binding of Armbian's `pwm-sunxi-enhance` driver (`arm64-dts-sun50i-h616-add-pwm-nodes.patch`): the controller `pwm@300a000` references these empty subnodes through `sunxi-pwms = <&pwm0>…`; because they have a compatible and sit under `/soc`, platform devices are created that nothing binds to. Harmless but non-mainline. | **wt-kernel**: replaced by one `pwm@300a000` node when the mainline `pwm-sun8i` (H616 PWM v10) driver lands; nothing to do here. |

**Test.** `for d in /sys/bus/platform/devices/*; do [ -e $d/driver ] || echo "$(basename $d) $(cat $d/of_node/compatible 2>/dev/null | tr '\0' ' ')"; done` → only the rows above. `cat /sys/devices/system/clocksource/clocksource0/available_clocksource` → `arch_sys_counter timer`.

---

## 6. systemd / journal warnings

| warning | cause | fix / status |
|---|---|---|
| `systemd-tmpfiles: Setting file flags is only supported on regular files and directories, cannot set on '/var/log/journal'` | `armbian-ramlog` mounts tmpfs/zram on `/var/log` and replaces `/var/log/journal` with a **symlink** to `/var/log.hdd/journal`; systemd's `/usr/lib/tmpfiles.d/journal-nocow.conf` has `h /var/log/journal - - - - +C` (btrfs NOCOW) which cannot be applied to a symlink. Armbian-caused. | **Fixed** (`sunxi/cleanup-bsp`): `packages/bsp/common/etc/tmpfiles.d/journal-nocow.conf` overrides the stock file (same basename in `/etc` wins) and applies `+C` to `/var/log.hdd/journal{,/%m,/remote}` instead. `h` lines on non-existent paths are silently skipped (ramlog disabled / no btrfs). |
| `cron.service: Referenced but unset environment variable evaluates to an empty string: EXTRA_OPTS` | Ubuntu/Debian `cron.service`: `EnvironmentFile=-/etc/default/cron` + `ExecStart=/usr/sbin/cron -f -P $EXTRA_OPTS`; `/etc/default/cron` has `EXTRA_OPTS` commented out. Distro packaging, not Armbian. | **Fixed** (`sunxi/cleanup-bsp`): drop-in `lib/systemd/system/cron.service.d/10-armbian-extra-opts.conf` with `Environment=EXTRA_OPTS=` (a value in `/etc/default/cron` still wins because `EnvironmentFile=` is applied after `Environment=`). Conffile untouched. |
| `bluetooth.service: ConfigurationDirectory 'bluetooth' already exists but the mode is different. (File system: 755 ConfigurationDirectoryMode: 555)` | bluez upstream unit sets `ConfigurationDirectoryMode=0555`, the bluez .deb installs `/etc/bluetooth` as 0755. Nothing in Armbian creates `/etc/bluetooth` (grepped `packages/bsp`, `lib`, `extensions`). | **Fixed** (`sunxi/cleanup-bsp`): drop-in `bluetooth.service.d/10-armbian-confdir-mode.conf` → `ConfigurationDirectoryMode=0755` (matches the package). |
| `NOTICE: Automounting of tracing to debugfs is deprecated and will be removed in 2030` | Kernel `kernel/trace/trace.c` prints this when *something* path-walks `/sys/kernel/debug/tracing` (tracefs automount) instead of `/sys/kernel/tracing`. It fires at 18.447 s, i.e. during AW859A/uwe5622 **Bluetooth bring-up** (17.1 s power on … 17.99 s `Bluetooth: Core`, `aw859a-bluetooth.service`/`hciattach_opi`), not during the dump (which ran hours later). No Armbian BSP file references `/sys/kernel/debug` or `tracing` (grepped `packages/bsp/common`, `lib/functions`, `extensions`). | **Not fixed, culprit to be pinned on hardware** (wt-wifi area if it is hciattach_opi/uwe5622). Test below. |
| `gpio gpiochip0/1: Static allocation of GPIO base is deprecated, use dynamic allocation.` | `drivers/pinctrl/sunxi/pinctrl-sunxi.c: pctl->chip->base = pctl->desc->pin_base;` — sunxi deliberately keeps static bases (0 for PIO, 352 for R_PIO) because the legacy sysfs numbers (`/sys/class/gpio/gpiochip0`, `gpiochip352`, used by WiringOP/`gpio` sysfs scripts; `CONFIG_GPIO_SYSFS=y` in Armbian) and the pinctrl `pin_base` mapping depend on them. Converting to `base = -1` is a userspace-ABI decision upstream has not taken for sunxi. | **Documented only** (two `dev_warn` lines; changing it would renumber every sysfs GPIO on all sunxi boards). |
| `KASLR disabled due to lack of seed` | Kernel found no `/chosen/kaslr-seed` (and no EFI RNG). Armbian's U-Boot v2026.10 for `orangepi_zero2_defconfig` has `# CONFIG_DM_RNG is not set`; `drivers/rng/` has no Allwinner driver (only `smccc_trng.c`, which needs TF-A TRNG support — `plat/allwinner` in TF-A lts-v2.14.11 does not implement `plat_get_entropy`; `arm_rndr.c` needs ARMv8.5 RNDR, absent on Cortex-A53). Also `fdt_kaslrseed()` is only called from the extlinux/pxe path and the `kaslrseed` command, not from `booti`/`bootm`. | **Note for wt-uboot** (no U-Boot edit here): options are (a) a U-Boot `UCLASS_RNG` driver for the H616 Crypto Engine TRNG (Linux `sun8i-ce-trng.c` is the reference; CE TRNG works on this board: `/dev/hwrng` = "sun8i Crypto Engine TRNG") + `CONFIG_DM_RNG=y` + `kaslrseed` in `boot.cmd` (or the pxe path), or (b) implement SMCCC TRNG in TF-A sun50i_h616 and enable `RNG_SMCCC_TRNG`. Until then the kernel line is expected; KASLR itself is just disabled, not a fault. |

**Test (BSP branch; after an image rebuild with the new `armbian-bsp-cli`).** `journalctl -b -p warning --no-pager | grep -E 'tmpfiles|EXTRA_OPTS|ConfigurationDirectory'` → empty. `systemctl show cron -p Environment` → `Environment=EXTRA_OPTS=`; `systemctl show bluetooth -p ConfigurationDirectoryMode` → `0755`; `systemd-tmpfiles --cat-config | grep -A3 journal-nocow` shows the `/etc/tmpfiles.d` version; `ls -ld /var/log/journal /var/log.hdd/journal` (symlink + dir) and `lsattr -d /var/log.hdd/journal` (on ext4 the `C` flag is simply not set, no error).
**Test (tracing automount culprit).** On the board, right after boot: `journalctl -b -o short-monotonic --no-pager | awk '$1+0>17.0 && $1+0<18.7'` to see which unit/binary is active when the NOTICE appears; then `mount | grep tracefs` (shows `/sys/kernel/debug/tracing`), and `grep -rl 'kernel/debug' /usr/bin/hciattach_opi /usr/lib/systemd/system /etc/systemd /usr/lib/armbian /usr/sbin 2>/dev/null`. If it is `hciattach_opi`/the uwe5622 service → wt-wifi: point it at `/sys/kernel/tracing` or drop the access. If nothing matches, `sudo auditctl -w /sys/kernel/debug/tracing -p r -k trc` (auditd) across one reboot names the process.

---

## 7. Kernel config review (`config/kernel/linux-sunxi64-edge.config`, after `olddefconfig` on 7.3.1)

Everything the H616/Zero2 hardware needs is already on: `SUN50I_H616_CCU`/`SUN50I_H6_R_CCU`/`SUN6I_RTC_CCU`/`SUN8I_DE2_CCU=y`, `SUN8I_THERMAL=y`, `SUN50I_H6_PRCM_PPU=m` (bound; GPU domain works with panfrost=m), `CRYPTO_DEV_SUN8I_CE=m` + `_HASH` + `_TRNG` (hwrng present), `RTC_DRV_SUN6I=y`, `IR_SUNXI=y`, `KEYBOARD_SUN4I_LRADC=m`, `SUN6I_MSGBOX=y`, `HWSPINLOCK_SUN6I=m`, `SUN50I_IOMMU=y`, `DRM_SUN4I/SUN8I_MIXER/SUN8I_DW_HDMI/SUN8I_TCON_TOP=y`, `VIDEO_SUNXI_CEDRUS=y`, `DRM_PANFROST=m` (selects `DEVFREQ_GOV_SIMPLE_ONDEMAND=m`; `PERFORMANCE/POWERSAVE/USERSPACE/PASSIVE=y`), `ARM_PSCI_CPUIDLE=y` (+`_DOMAIN`; the board shows no idle states because H616 TF-A has no SCP/`CPU_SUSPEND` idle states in DT — expected), `ARM_ALLWINNER_SUN50I_CPUFREQ_NVMEM=y`, `SPI_SUN6I`, `MTD_SPI_NOR`, `MMC_SUNXI`, `PHY_SUN4I_USB`, `USB_MUSB_SUNXI=m`, `SND_SUN50I_CODEC_ANALOG/DMIC=y`, `HW_RANDOM_ARM_SMCCC_TRNG=y`, `REGULATOR_AXP20X`/`MFD_AXP20X_RSB=y`, `AXP20X_ADC=m`.

Deliberately **not** changed: `CONFIG_SUN5I_HSTIMER` (not selectable, not needed — item 5); `CONFIG_THERMAL_GOV_POWER_ALLOCATOR` (arm64 defconfig has it, but useless without an energy model; item 4 solved with step_wise); `SUN50I_H6_PRCM_PPU=m → y` (works as module, no boot-order issue observed); `CRYPTO_DEV_SUN{4I,8I}_{CE,SS}_DEBUG=y` (debugfs counters only); `GPIO_SYSFS=y` (deprecated but relied on); `RANDOMIZE_BASE=y` (harmless without seed).

**Changed** (`sunxi/cleanup-kconfig`, `6d9361d`): `CONFIG_REALTEK_PHY_HWMON=y` — the Zero2's RTL8211F has a die temperature sensor that the realtek PHY driver exposes via hwmon when this bool is set; no cost for boards without a Realtek PHY. (Shared sunxi64 config → affects all sunxi64 boards, all benign.)

**Test.** `grep -l rtl /sys/class/hwmon/hwmon*/name 2>/dev/null; for h in /sys/class/hwmon/hwmon*; do echo "$(cat $h/name): $(cat $h/temp1_input 2>/dev/null)"; done` → an `rtl8211f` (or `stmmac-0:01`-named) hwmon with a plausible PHY temperature; `sensors` lists it.

---

## 8. (coordinator follow-up) Unstable SD block device name — no mmc aliases

**Cause.** `drivers/mmc/core/host.c: mmc_alloc_host()` takes the host index from `of_alias_get_id(np, "mmc")` and only falls back to a free index when there is no alias. `sun50i-h616-orangepi-zero.dtsi` (shared by Zero2 and Zero3) declares only `ethernet0`/`serial0`, so the microSD host (`mmc0`) and the SDIO WiFi host (`mmc1`, `non-removable`) race on probe order: SD = `/dev/mmcblk0` on most boots, `/dev/mmcblk1` with no `mmcblk0` on others (observed). Root is by UUID, but `armbian-install`/`nand-sata-install`, `write_uboot_platform`, docs assume `mmcblk0`. Mainline policy: `sun50i-a64.dtsi`/`sun50i-h5.dtsi` carry `mmc0..2` aliases at SoC level; the H6/H616 dtsi do not, and H616/H618 **board** files add them (`sun50i-h616-tanix-tx6s*.dts`: mmc0/mmc2; `sun50i-h618-mellow-fly-c5.dts`: mmc0 SD/mmc1 WiFi/mmc2 eMMC; `sun50i-h618-walnutpi.dtsi`). Orange Pi 3 (H6) and Zero2W also lack them (same latent bug there).

**Fix** (`sunxi/cleanup-mmc-aliases`, `72f0cb3`): `patches.armbian/arm64-dts-sun50i-h616-orangepi-zero-add-mmc-aliases.patch` (series line 574, right after `zero2-zero3-add-wifi`, the last patch touching the dtsi) adds to the shared dtsi's `aliases`: `mmc0 = &mmc0; /* microSD slot */`, `mmc1 = &mmc1; /* SDIO WiFi/BT module */`. No `mmc2`: eMMC is not wired on Zero2 or Zero3 (`mmc2` stays disabled, so no alias — same as the Tanix boards which alias only the hosts they use). Covers the Zero3 as well. Upstream-ready as-is.

**Test.** `ls -l /proc/device-tree/aliases/` → `mmc0`, `mmc1` present; `cat /sys/class/mmc_host/mmc0/device/of_node/name` → `mmc` at `4020000`; across 5 reboots `readlink -f /dev/disk/by-path/platform-4020000.mmc` → always `/dev/mmcblk0` and `ls /sys/bus/mmc/devices/` shows `mmc0:aaaa` (SD) and `mmc1:8800` (SDIO); `armbian-install` lists the SD as `/dev/mmcblk0`. WiFi still associates (`iw dev wlan0 link`).

---

## Build results

All on `wt-cleanup-integration` (final head `1a297ed`), `WORK=/home/aruni/orangepizero2/kernel-check/work-cleanup`, ccache shared:

* `STAGE=all` (`run-cleanup-all.log`): 693 patches applied, 0 failed; all modified objects (`sun8i_mixer.o`, `sun8i_ui_layer.o`, `sun8i_vi_layer.o`, `dwmac-sun8i.o`) compiled without warnings; the 7 C warnings are pre-existing (sunxi-sysinfo, sunxi-addr, uwe5622, axp20x, panel-simple, fdt_address). The first `make Image modules` aborted at unrelated objects with `Cannot create temporary file in /tmp/: No space left on device` (`/tmp` tmpfs 96% full from other agents' work); resumed in-place with `TMPDIR` on disk → `exit=0`, `arch/arm64/boot/Image` built (`work-cleanup/build2.log`). dtbs exit 0; `DT_CHECK ok`: `vcc-pl-supply vcc-supply cpu-alert cpu-hot cooling-maps`.
* `STAGE=dtbs` after adding the mmc-alias commit (`run-cleanup-dtbs2.log`): 694 patches applied, 0 failed; dtbs exit 0 (17 dtc warnings, all pre-existing in other boards' files); `DT_CHECK ok`: `mmc0 mmc1 vcc-pl-supply vcc-supply cpu-alert cooling-maps`. Decompiled Zero2 DTB: `aliases { ethernet0; mmc0 = /soc/mmc@4020000; mmc1 = /soc/mmc@4021000; serial0 }`, `vcc-pl-supply`/flash `vcc-supply` = ALDO1 phandle, cpu-thermal trips 85000/100000/110000 with a 4-CPU cooling map.

Not yet done (needs hardware, coordinator): boot test of each item per the "Test" paragraphs above; an image rebuild is needed for the BSP drop-ins (item 6) and the kernel config (item 7).
