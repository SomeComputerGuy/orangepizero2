# Orange Pi Zero2 (H616) — kernel-side improvements on Armbian sunxi-7.3 (Linux 7.3.1)

Date: 2026-11-01. Worktree: `/home/aruni/orangepizero2/wt-kernel` (shares `.git` with `armbian-build`).
Base: upstream `armbian/build` main `27a7f72` ("genio-7.3: disable ASP FSM parity ...").
Author of all commits: Arun Iyengar <aiyengar1990@gmail.com> (trailers `Assisted-by: Claude:claude-fable-5-1` and `Signed-off-by` added by the repo's prepare-commit-msg hook). Nothing pushed.

Inputs: `harness/research/h616-patch-landscape.md`, `harness/research/opi5-carryover.md` §2.
Upstream sources: every sha was fetched from `https://github.com/torvalds/linux/commit/<sha>.patch` and its Subject/Link checked against the research before use. Pending series were fetched from `https://lore.kernel.org/all/<msgid>/t.mbox.gz` (lore answers 200 from this host) and split with `kernel-check/split-mbox.py`. Downloads live in `kernel-check/dl-upstream/` (untrusted data, nothing executed from there).

## 1. Branches and commits

All topic branches are based directly on `27a7f72`; `wt-kernel-integration` is the five topics cherry-picked (`-x`) linearly on top of `27a7f72`, no merge commits, **no conflicts**.

| Branch | Commit | Item |
|---|---|---|
| `sunxi/dwmac-sun8i-upstream-reset` | `e04e429` | 1 — dwmac-sun8i: backport fee9c17671b6 + d9750b3c4c27, drop Armbian reset-on-open patch, rebase Armbian EMAC1 patch |
| `sunxi/cedrus-h616-upstream` | `96a216e` | 2 — Cedrus H616: upstream 1f24d4307515 + eabc3c090e81 replace the two Armbian patches |
| `sunxi/zero2-gpu-opp` | `f24863d` | 3 — Mali-G31 OPP table for Zero2/Zero3 + `CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y` |
| `sunxi/zero2-usb-otg-host-overlay` | `d315966` | 4 — `sun50i-h616-usb-otg-host.dtso`; IR stays overlay-only (header-only receiver) |
| `sunxi/pm-s2idle-dpm-backports` | `3d287e0` | 6 — 4785d5faa935 (s2idle begin/end) + 33392343c74e (DPM watchdog phases), `CONFIG_DPM_WATCHDOG` left off |
| `wt-kernel-integration` | `59e9d39 7af4eed 14924c9 e146e2c 7a724ac` (= the five above, in that order) | all |

Item 5 (pending-upstream series) produced **no branch** — see §3 for the reasoning per series.

Other `sunxi/uwe5622-*` branches visible in the shared `.git` belong to the wifi agent and were not touched.

## 2. What each item changes

### Item 1 — dwmac-sun8i (`patch/kernel/archive/sunxi-7.3/`)

- **Added** `patches.armbian/drv-net-stmmac-dwmac-sun8i-fix-ephy-clock-leak.patch` = upstream `d9750b3c4c27` "net: stmmac: dwmac-sun8i: Fix EPHY clock leak in get_ephy_nodes()" (Wentao Liang, Cc: stable, Link kept; `(cherry picked from commit ...)` note added).
- **Added** `patches.armbian/drv-net-stmmac-dwmac-sun8i-reset-mac-after-phy-init.patch` = upstream `fee9c17671b6` "net: stmmac: sun8i: reset the MAC after PHY initialization" (James Hilliard, Reviewed/Tested-by Maxime Chevallier). The MAC soft reset moves from probe into `sun8i_dwmac_dma_reset()` (stmmac `dma_ops->reset`, called from `stmmac_hw_setup()` after the PHY is attached/resumed), interrupts are masked before the reset and the DMA/IRQ registers are still cleared on timeout.
- **Dropped** `patches.armbian/drv-net-stmmac-dwmac-sun8i-reset-emac-on-open.patch` (Pedro Santos, 2026-08-22, armbian/build#10492). Justification: it is the same idea as fee9c17671b6 — a `sun8i_dwmac_soft_reset(ioaddr)` called from `sun8i_dwmac_dma_reset()` and the probe-time reset removed — but (a) it returns early on timeout without clearing the DMA/INT registers, (b) it does not mask interrupts first, (c) it keeps a now-unused `sun8i_dwmac_reset(priv)` wrapper. With the upstream patch in place the two cannot coexist (both rewrite `sun8i_dwmac_dma_reset()` and delete the same probe hunk), and the upstream version is the maintainer-reviewed superset. Nothing of it remains.
- **Rebased** `patches.armbian/drv-net-stmmac-dwmac-sun8i-add-h616-internal-phy.patch` (Alastair D'Silva's EMAC1/AC300 "ARCHEOLOGY" patch, used by Zero2W/BigTreeTech CB1/X96 Mate, not by the Zero2). Header/authorship kept, a rebase note added, diff regenerated:
  - its forward declaration and extra `sun8i_dwmac_reset()` call in `sun8i_dwmac_init()` are gone (that is exactly what fee9c17671b6 does generically — the reset now happens after the internal PHY has been powered and attached);
  - the "skip the MDIO-mux reset for the internal PHY" hunk re-applied on the new `sun8i_dwmac_reset(priv->ioaddr)` + `dev_err` form;
  - its optional clock/reset handling in `get_ephy_nodes()` re-applied on top of d9750b3c4c27's local-variable version (`clk_put(ephy_clk)` on the defer path, `gmac->ephy_clk = ephy_clk` only on success).
- **series.conf**: the two upstream patches are listed right before `drv-net-stmmac-dwmac-sun8i-add-second-emac-clock.patch`, i.e. before Armbian's EMAC1 patches, matching the order in torvalds/master (d9750b3c4c27 → fee9c17671b6 → 61240e48a67d).

Follow-up (not done, out of scope): Armbian's two EMAC1 patches overlap upstream `61240e48a67d` "add support for Allwinner H616 EMAC1" (7.4). Upstream uses compatible `allwinner,sun50i-h616-emac1` and `soc_has_internal_phy = false`; Armbian uses `allwinner,sun50i-h616-internal-emac` and the H3 internal-PHY path, plus a chipid-derived MAC hack. Switching needs the Zero2W/CB1 DTs and the AC300 PHY driver patch re-checked on hardware those boards — a separate task.

### Item 2 — Cedrus H616

- `patches.armbian/drv-staging-media-sunxi-cedrus-add-H616-variant.patch` → content replaced by upstream `1f24d4307515` (Chen-Yu Tsai; same 4-line hunk, now with upstream message/tags, Reviewed-by Jernej).
- `patches.armbian/arm64-dts-sun50i-h616-add-vpu-node.patch` **removed**; `patches.armbian/arm64-dts-sun50i-h616-add-video-engine.patch` = upstream `eabc3c090e81` (Jernej Skrabec / Chen-Yu Tsai, Reviewed-by Andre Przywara, Link kept). The node now has `iommus = <&iommu 3>, <&iommu 2>` and `allwinner,sram = <&ve_sram 1>, <&sram_c 1>`.
- Verified in vanilla 7.3.1 `sun50i-h616.dtsi`: `iommu: iommu@30f0000` (`allwinner,sun50i-h616-iommu`, no `status = "disabled"`; driver `drivers/iommu/sun50i-iommu.c` matches it; `CONFIG_SUN50I_IOMMU=y`), `sram_c: sram-section@0` (`allwinner,sun50i-h616-sram-c` + a64 fallback) and `ve_sram: sram-section@0` (`allwinner,sun50i-h616-ve-sram`) exist — the multi-claim SRAM support (`be99eb936b4f`/`67890da74dd1`) and the H616 SRAM regions (`b70829432274`) are in 7.3. Nothing further to backport. (Armbian's `0701-...-enable-sound.patch` additionally adds an `allwinner,sun50i-h6-iommu` fallback to the iommu node; harmless, both compatibles are in the driver.)
- The resulting node in the patched tree (`work-patchcheck` / `work-kernel`): `video-codec@1c0e000 { compatible = "allwinner,sun50i-h616-video-engine"; ... iommus = <&iommu 3>, <&iommu 2>; allwinner,sram = <&ve_sram 1>, <&sram_c 1>; }`.

### Item 3 — GPU DVFS (Mali-G31 OPPs)

- New `patches.armbian/arm64-dts-sun50i-h616-orangepi-zero-add-gpu-opp.patch`: one line, `#include "sun50i-h616-gpu-opp.dtsi"` in **`sun50i-h616-orangepi-zero.dtsi`** (shared by Zero2 and Zero3). Scope decision: both boards' GPU regulators are named `vdd-gpu-sys` and constrained to **810000–990000 µV** in their board DTS (Zero2: AXP305 `reg_dcdcc`, `mali-supply = <&reg_dcdcc>`; Zero3: AXP313a `reg_dcdc1`, `mali-supply = <&reg_dcdc1>`), so the OPP table (targets 810–950 mV, min 810 mV, max 990 mV) fits both; the include therefore goes in the shared dtsi instead of the two board files. `dt_64/sun50i-h616-gpu-opp.dtsi` already exists (KickPi K2B) and is copied into `arch/arm64/boot/dts/allwinner/` by the framework; it sets `&gpu { operating-points-v2 = <&gpu_opp_table>; }`.
- series.conf: listed before `arm64-dts-sun50i-h616-orangepi-zero2-enable-expansion-board-usb.patch`.
- `config/kernel/linux-sunxi64-edge.config`: `CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y` added (before `CONFIG_DEVFREQ_GOV_PERFORMANCE=y`). Before: not in the file; `olddefconfig` resolved it to `=m` because `DRM_PANFROST=m` only `select`s it. `=m` *does* work — `devfreq_add_device()` → `try_then_request_governor()` does `request_module("governor_simpleondemand")` when the governor is missing — but it makes the GPU devfreq registration depend on module loading from inside panfrost's probe. Built-in is preferred and consistent with the other governors in this config (`PERFORMANCE/POWERSAVE/USERSPACE/PASSIVE=y`).
- Checked in the decompiled Zero2 DTB: `opp-table-gpu` with 10 OPPs (306–600 MHz) present; `gpu@1800000` has `operating-points-v2`, `mali-supply`, `power-domains = <&prcm_ppu 2>`, `status = "okay"`.
- Known gap: panfrost calls `devfreq_cooling_em_register()`; without `dynamic-power-coefficient` in the gpu node there is no energy model, so expect a one-time `panfrost ... Failed to register cooling device` info line; devfreq itself still works. The `gpu-thermal` zone only has a critical trip and no cooling map — GPU thermal throttling via devfreq is a possible follow-up once DVFS is confirmed stable.

### Item 4 — USB-C host overlay, IR

- New `overlay_64/sun50i-h616-usb-otg-host.dtso` (compatible `allwinner,sun50i-h616`, `allwinner,sun50i-h618`): fragment on `&usbotg` sets `dr_mode = "host"` (+ `status = "okay"`), fragments enable `&ehci0` and `&ohci0` — exactly what the mainline `sun50i-h616-orangepi-zero.dtsi` comment prescribes for boards powered via the header. Added to `overlay_64/Makefile` (`sun50i-h616-usb-otg-host.dtbo`). The default DT keeps `dr_mode = "peripheral"`. Verified by applying the built `.dtbo` to the built Zero2 DTB with `scripts/dtc/fdtoverlay`: `usb@5100000` → `dr_mode = "host"`, `usb@5101000`/`usb@5101400` → `status = "okay"`, no unresolved fixups.
- **IR receiver**: header-only. The Zero2 schematic (`Orange_Pi_Zero2_H616_schematic_v1.3.pdf`, text strings extracted) contains only the net `IR-RX` on `PH10` and no receiver part (no HS0038/VS1838/IRM designator); the linux-sunxi wiki lists the 13-pin header pin 13 as `CIR-RX / PH10`, and Xunlong advertises IR "via 13pin interface board" (the Orange Pi Zero expansion board). So `&ir` is **not** enabled in the board DTS; users with the expansion board keep `overlays=ir` (`sun50i-h616-ir.dtso`, `CONFIG_IR_SUNXI=y`).

### Item 6 — generic 7.4 PM fixes

- `patches.armbian/pm-suspend-do-not-call-suspend-ops-begin-end-for-s2idle.patch` = `4785d5faa935` (Ovidiu Panait; `Fixes: 7602c0ec0bbf`, which is in v7.3). Relevant here: H616 uses PSCI and only s2idle; on 7.3 every s2idle cycle still calls `psci_system_suspend_begin()` → `pm_set_suspend_via_firmware()`, so drivers wrongly take "firmware removes power" paths. GitHub `gregkh/linux` `linux-7.3.y` shows no `kernel/power/suspend.c` commits since October → not yet in stable, backport needed.
- `patches.armbian/pm-sleep-add-dpm-watchdog-to-all-phases.patch` = `33392343c74e` (Mayank Rungta). Compiled only under `CONFIG_DPM_WATCHDOG`, so a no-op for the shipped config.
- **`CONFIG_DPM_WATCHDOG` is not enabled.** Judgement: not production-safe — `dpm_watchdog_handler()` ends in `panic()` after `CONFIG_DPM_WATCHDOG_TIMEOUT` (default 120 s), and a USB/SDIO device that legitimately takes long to resume would reboot the box. It is a *test-kernel* option: the config already satisfies its deps (`PM_DEBUG=y`, `PSTORE=y`, `EXPERT=y`), so a test build only needs `CONFIG_DPM_WATCHDOG=y`, `CONFIG_DPM_WATCHDOG_TIMEOUT=60`, `CONFIG_DPM_WATCHDOG_WARNING_TIMEOUT=30` (userpatches kernel config). With the backport, the watchdog then covers prepare/late/early/noirq/complete, not just suspend/resume.
- series.conf: both listed before `soc-sunxi-mbus-drop-the-A80-display-engine.patch`. No other series patch touches `kernel/power/suspend.c` or `drivers/base/power/main.c`.

## 3. Item 5 — pending-upstream series: decisions

Dry-run method: each split patch applied with `patch -p1` to a vanilla 7.3.1 subtree (`kernel-check/scratch/`).

### 5a. H616 PWM v10 (`20260922-h616-pwm-v8-v10-0-dccebbe1aabf@gmail.com`, Hilliard/Genoud `pwm-sun8i.c`) — **NOT carried**

- Applies cleanly to 7.3.1 (patches 1–4; 5 is MAINTAINERS). Review state: only patch 1 (binding) has an Ack (Conor Dooley); the driver (patch 2, 1080 lines) and the clock export (patch 3) have **no Reviewed-by**, Uwe Kleine-König (PWM maintainer) has not accepted it, and this is v10 of a series that has changed its DT contract between versions (v10 adds `#clock-cells = <1>` for the bypass outputs). It is upstream-*bound* but not yet upstream-*track* in the sense of being queued in a maintainer tree.
- It is **not** a drop-in for the vendor driver: both use compatible `allwinner,sun50i-h616-pwm` for `pwm@300a000`, so they cannot coexist; the vendor model has per-channel subnodes (`pwm0..pwm5`, `allwinner,sunxi-pwmN`) each carrying its own `pinctrl-0`, while mainline has one node with `#pwm-cells = <3>` and pinctrl on the controller. A coherent switch would have to: drop `drv-pwm-sun50i-h616-add-pwm-driver.patch` and `CONFIG_PWM_SUNXI_ENHANCE=y` (add `CONFIG_PWM_SUN8I`), replace `arm64-dts-sun50i-h616-add-pwm-nodes.patch` (vendor pin nodes `pwm1_ph_pin`/`pwm1_pi_pin`/`pwm2_ph_pin`… vs. mainline's single `pwmN_pin` per channel — mainline v10 only defines PG19/PH2/PH0/PI14/PA12/PD28, so the Zero2 header pins PH3 (PWM1), PI11/PI12/PI13 would need extra pin nodes), rewrite the 8 Zero2 overlays `sun50i-h616-pwm{1-ph3,1-pi11,2-ph2,2-pi12,3-ph0,3-pi13,4-ph1,4-pi14}.dtso` (and they could no longer stack, since each would overwrite the controller's `pinctrl-0`), fix the `pwm34` logic in `sun50i-h616-fixup.scr-cmd`, and update four other boards that reference `&pwm5`/`sunxi-pwms` (`dt_64/sun50i-h618-bananapi-m4.dtsi`, `sun50i-h618-mellow-fly-c5.dts`, `sun50i-h313-x96q-lpddr3.dts`, `0302-...-zero2w-add-emac-sound.patch`). That is a family-wide, untestable-here change for a driver whose binding may still move; the vendor driver works today. Revisit when the series lands in pwm/for-next.

### 5b. H616 UART FIFO/trigger v5 (`20261029-submit-h616-uart-fifo-v1-v5-0-53b433aebbf8@gmail.com`) + APB2 clock export (`20261021-submit-sun50i-h616-apb2-clock-v1-v1-0-7b857ad1198d@gmail.com`) — **NOT carried**

- Does **not** apply cleanly to 7.3.1: patch 1/8 ("8250_dw: select port setup through platform data") hunk 5 fails and patch 2/8 ("8250: share the RX trigger conversion helper") fails entirely — they are against tty-next and depend on 8250 core refactors not in 7.3. Patches 3–8 apply, but 4/8 depends on 1–2. Posted 2026-10-29 (3 days old); review so far: Ilpo Järvinen R-b on 1 and 2, Andy Shevchenko R-b on 2, Krzysztof Acks on the bindings — promising, but a backport would mean rebasing the 8250 core changes by hand for a feature (correct 256-byte FIFO depth/RX trigger, auto RTS/CTS, keeping the clock gate on across termios) that only matters for high-baud/flow-controlled header UARTs; the console at 115200 works today.
- APB2 export (2 patches) applies cleanly and is trivial, but on its own has no consumer in our tree (the UART series' DT patch does not reference `CLK_APB2` either — it only adds the `allwinner,sun50i-h616-uart` compatible). Carrying it alone buys nothing; carry it together with the UART series when that lands.

### 5c. Jernej `h616-ahub-v1` (github.com/jernejsk/linux-1, head `8209ffebad45`, 2026-09-06) vs. vendor AHUB — **NOT carried, documented**

- Branch = Linux 7.2 + 17 commits: the first 11 are his generic HDMI-audio rework (dw-hdmi IEC958/HBR I2S in `drivers/gpu/drm/bridge/synopsys/dw-hdmi-i2s-audio.c`, `hdmi-codec` component naming, `sun4i-i2s` IEC958 transport (+233 lines), a new `sound/soc/sunxi/sunxi-hdmi.c` machine driver, new binding `allwinner,sun8i-a83t-hdmi-audio.yaml`, DT topology for H3/H5/A64/H6 boards); on top: `clk: sunxi-ng: sun50i-h616: propagate audio hub rate changes`, `ASoC: sunxi: resolve the HDMI CPU DAI from the phandle arguments`, binding + driver `sound/soc/sunxi/sun50i-h616-ahub.c` (1298 lines, compatible `allwinner,sun50i-h616-ahub`), and a dtsi node `ahub: audio-hub@5097000` (`#sound-dai-cells = <1>`, `status = "disabled"`). **No H616 board enables it in the branch** and there is no H616 HDMI sound-card node; it was never posted to a list.
- Not a drop-in: Armbian's HDMI audio on the Zero2 is the vendor `sound/soc/sunxi_v2` stack (`0701-...-enable-sound.patch`: `ahub_dam_plat`/`ahub1_plat` `allwinner,sunxi-snd-plat-ahub*`, `ahub1_mach` → `&hdmi`, plus `0702-...-digital-audio-node.patch` clocking fixes), together with Armbian's `drv-drm-sun4i-hdmi-add-audio-support.patch` and megi's `sun9i-hdmi-audio`/hdmi-sound-card DTS patches (`dts-allwinner-7.3/0006-0015`) — Jernej's dw-hdmi and sun4i-i2s changes collide with those, and his AHUB needs a new machine-driver/DT topology for the Zero2 that does not exist yet. The analog codec (`sun50i-h616-codec`, `sun4i-codec.c`) is independent of both and unaffected. Switching would be a rebase-and-test project (HDMI audio could regress to silence); the research's "watch, don't pull" stands.

## 4. Compile / DT checks

Script: `kernel-check/build-kernel.sh` (rootless, ccache; original kept as `build-kernel.sh.orig`). Improvements made:
- `STAGE=patch|dtbs|all` (patch = extract + series.conf + dt/overlay copy only; dtbs = + `olddefconfig` + `make dtbs`, i.e. all allwinner DTBs, all Armbian `.dtbo` overlays and the `*-fixup.scr` via mkimage; all = Image + modules + Zero2 DTB + dtbs);
- prints patch-failure names, C-warning counts per file, dtc warning lines, number of `sun50i-h616-*.dtbo` built;
- decompiles the Zero2 DTB to `$WORK/zero2.dts` and checks `DT_CHECK="pat ..."` patterns in it.
Invocation: `STAGE=... DT_CHECK="..." ARMBIAN=/home/aruni/orangepizero2/wt-kernel WORK=/home/aruni/orangepizero2/kernel-check/work-kernel ./build-kernel.sh` (a second `WORK=.../work-patchcheck` was used for the fast patch/dtbs stages while a full build was running). Logs: `kernel-check/run-item*.log`, `run-integration.log`, `build-*.log`.

| Branch | patches applied / failed | Build | Warnings in touched files | DT checks |
|---|---|---|---|---|
| `sunxi/dwmac-sun8i-upstream-reset` | 691 / 0 | Image + modules + Zero2 DTB OK, `dwmac-sun8i.ko` built; `make dtbs` OK (53 h616 overlays) | 0 in `dwmac-sun8i.c` (9 warnings total, all pre-existing in untouched Armbian files: sunxi-sysinfo, axp20x sysfs, sunxi-addr, panel-simple, uwe5622, fdt_address, sunxi_sid) | `ethernet@5020000` present |
| `sunxi/cedrus-h616-upstream` | 690 / 0 | Image + modules + Zero2 DTB OK (`cedrus.o` built), `make dtbs` OK (53 h616 overlays) | 0 in `cedrus.c` / dtsi (same 9 pre-existing warnings as item 1) | `video-codec@1c0e000` with `iommus` |
| `sunxi/zero2-gpu-opp` | 691 / 0 | `STAGE=dtbs` OK (DT-only + config) | n/a | `opp-table-gpu`, `operating-points-v2`, `opp-600000000` present; `.config` has `DEVFREQ_GOV_SIMPLE_ONDEMAND=y` |
| `sunxi/zero2-usb-otg-host-overlay` | 690 / 0 | `STAGE=dtbs` OK, 54 h616 overlays incl. `sun50i-h616-usb-otg-host.dtbo` (556 B), `sun50i-h616-fixup.scr` built | n/a | fdtoverlay-merged DTB: `dr_mode = "host"`, ehci0/ohci0 `okay` |
| `sunxi/pm-s2idle-dpm-backports` | 692 / 0 | Image + modules + Zero2 DTB OK, `make dtbs` OK | 0 in `kernel/power/suspend.c`, `drivers/base/power/main.c` (same 9 pre-existing) | n/a (patched `suspend.c` shows `s2idle_ops->begin/end` paths; `main.c` has 15 `DPM_WATCHDOG` sites) |
| `wt-kernel-integration` | 694 / 0 | Image + modules + Zero2 DTB OK, `make dtbs` OK (22 min wall, ccache) | 0 new (same 9 pre-existing warnings, identical list on every branch) | `video-codec@1c0e000` with `iommus = <&iommu 3>,<&iommu 2>` + `allwinner,sram = <&ve_sram 1>,<&sram_c 1>`; `gpu@1800000` has `operating-points-v2` + `mali-supply` + `status = "okay"`; `opp-table-gpu`; `ethernet@5020000`; 54 h616 overlays incl. `usb-otg-host` |

Pre-existing dtc warnings (not ours): `sun50i-h5-nanopi-r1s-h5.dts` (`reg_format` on `usb@1c1b000/device@1`) and `sun50i-a64-pine64-7inch-lcd.dtso` (`avoid_default_addr_size`). No dtc warnings for the Zero2 DTB or any h616 overlay. There is no yamllint/dt-schema here, so `dt_binding_check` was not run; the DT changes are a one-line include, an upstream node verbatim, and an overlay that only flips `dr_mode`/`status`.

## 5. What to test on the board (per item)

Boot the integration kernel (`uname -r` should show the 7.3.1 edge build) and keep a serial console attached.

**Item 1 — Ethernet reset after PHY init**
- `dmesg | grep -iE 'dwmac|stmmac|eth0|RTL8211'` → expect `dwmac-sun8i 5020000.ethernet eth0: ...` without `EMAC reset timeout`, PHY `RTL8211F Gigabit Ethernet` attached, `Link is Up - 1Gbps/Full`.
- Warm-reboot loop: `for i in 1 2 3 4 5; do sudo reboot; done` (one at a time, wait for boot) — after each boot `ip -br link show eth0` must show `UP` with carrier and `ping -c3 <gateway>` succeeds. This was the failure mode the Armbian patch fixed; the upstream version must behave identically.
- `sudo ip link set eth0 down; sudo ip link set eth0 up` 10× → link comes back each time, `dmesg` shows no `EMAC reset timeout`.
- Cold boot with the Ethernet cable unplugged, then plug it in after login: link must come up (`ip monitor link` shows `eth0: ... state UP`) — exercises the "reset needs the PHY RX clock" case the patch is about.

**Item 2 — Cedrus with IOMMU + SRAM C**
- `dmesg | grep -iE 'cedrus|video-engine|iommu|sram'` → expect `cedrus 1c0e000.video-codec: Device registered as /dev/video0` and **no** `Failed to claim SRAM` / `allwinner,sram` errors; `ls /sys/kernel/iommu_groups/*/devices/` must contain `1c0e000.video-codec`.
- `v4l2-ctl -d /dev/video0 --all | grep -A3 'Driver name'` → `cedrus`, `sun50i-h616-video-engine`.
- Decode test (needs `ffmpeg` with v4l2 request API or `gst-launch-1.0 ... v4l2slh264dec`): `ffmpeg -hwaccel drm -hwaccel_device /dev/dri/renderD128 -i sample_h264.mp4 -f null -` or `gst-launch-1.0 filesrc location=sample.mkv ! matroskademux ! h264parse ! v4l2slh264dec ! fakesink -v` → frames decode, `dmesg` stays free of `sun50i-iommu ... Unexpected ... fault`. An IOMMU fault would be the regression to look for (the old node bypassed the IOMMU).

**Item 3 — GPU devfreq**
- `ls /sys/class/devfreq/` → `1800000.gpu`; `cat /sys/class/devfreq/1800000.gpu/{governor,available_frequencies,cur_freq}` → `simple_ondemand`, `306000000 ... 600000000`, cur_freq 306000000 when idle.
- `dmesg | grep -iE 'panfrost|devfreq'` → `panfrost 1800000.gpu: clock rate = ...`, `mali-g31 id 0x7093 ...`; a single `Failed to register cooling device` info line is expected (no energy model), nothing else.
- Load: `glmark2-es2-wayland` / `glmark2-es2-drm` (or `kmscube` for a minute) while `watch -n1 cat /sys/class/devfreq/1800000.gpu/cur_freq` → frequency rises to 600000000 under load and falls back when idle; `cat /sys/class/devfreq/1800000.gpu/trans_stat` shows transitions.
- Voltage/thermal sanity: `cat /sys/class/regulator/regulator.*/name` to find `vdd-gpu-sys`, then its `microvolts` must track 810000–950000 with frequency; `cat /sys/class/thermal/thermal_zone*/type,temp` (gpu-thermal) stays well below critical during a 10-min glmark2 run; no `panfrost ... GPU fault`/`job timeout` in dmesg.

**Item 4 — USB-C host overlay**
- Default boot (no overlay): `cat /proc/device-tree/soc/usb@5100000/dr_mode` → `peripheral` (unchanged behaviour); `/proc/device-tree/soc/usb@5101000/status` → `disabled`.
- Power the board through the header (5V/GND on the 26-pin header), add `overlays=usb-otg-host` to `/boot/armbianEnv.txt`, reboot: `cat /proc/device-tree/soc/usb@5100000/dr_mode` → `host`; `lsusb -t` shows two extra root hubs (`ehci-platform`/`ohci-platform` at 5101000/5101400); plug a USB stick into the USB-C port with a C-to-A adapter that ignores CC → `dmesg` shows `usb 1-1: new high-speed USB device`, `lsblk` lists it. Do not power the board from the same USB-C port while testing (it would back-feed).
- IR (only with the 13-pin expansion board): `overlays=ir`, `ir-keytable` → `sunxi-ir` on `/sys/class/rc/rc0`, `ir-keytable -t` prints events for a remote. Without the expansion board nothing to test; confirm `/proc/device-tree/soc/ir@7040000/status` is `disabled` by default.

**Item 6 — s2idle begin/end, DPM watchdog**
- `cat /sys/power/mem_sleep` → `[s2idle]`; arm a wake alarm at the next full minute + 1: `sudo rtcwake -m no -s 90 && cat /proc/driver/rtc | grep alrm` (expect `alrm_pending: yes`/`alarm_IRQ: yes`), then `echo mem | sudo tee /sys/power/state`. Board must resume by itself; `dmesg | grep -E 'PM: suspend (entry|exit)|psci'` → `PM: suspend entry (s2idle)` ... `PM: suspend exit`, and **no** `psci: SYSTEM_SUSPEND` / `pm_set_suspend_via_firmware` related driver messages (e.g. no `xhci/ehci ... suspend via firmware` paths; `grep -c 'via firmware' <(dmesg)` → 0).
- Driver behaviour that previously depended on `pm_suspend_via_firmware()`: Ethernet (`eth0` link back within ~5 s after resume, `ping` works), SD card (`dmesg | grep mmc0` no re-init errors), uwe5622 Wi-Fi reconnects. Repeat 5 cycles.
- DPM watchdog: not enabled in the shipped config, nothing to test. For a test kernel with `CONFIG_DPM_WATCHDOG=y` (see §2 item 6), a deliberately hung device would produce `**** DPM device timeout ****` + a stack and the device name on the console/pstore instead of a silent hang.

**Regression sweep (all items)**: `journalctl -b -p warning..emerg | grep -viE 'known-benign'` compared with the pre-change board dump (`harness/analysis/board-dump-1.txt`), `systemd-analyze blame | head`, HDMI output + `aplay -l` (vendor AHUB unaffected), `iw dev` (Wi-Fi), `lsmod | grep -E 'panfrost|cedrus|dwmac'`.
