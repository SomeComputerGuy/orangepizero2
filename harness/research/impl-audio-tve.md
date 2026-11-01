# Orange Pi Zero2 (H616) — analog mic capture (A) and composite TV-out (B) on Armbian sunxi-7.3 (Linux 7.3.1)

Date: 2026-11-01. Worktree: `/home/aruni/orangepizero2/wt-audio` (shares `.git` with `armbian-build`).
Base: `armbian/build` main `27a7f72`. Author of all commits: Arun Iyengar <aiyengar1990@gmail.com>
(the repo's prepare-commit-msg hook adds `Assisted-by:`/`Signed-off-by:` trailers). Nothing pushed, no board access from this environment: everything below is build-tested only.

## 0. Summary

| Item | Result |
|---|---|
| (A) analog MIC capture on the H616 codec | **Not implementable: the hardware does not exist.** The H616 audio codec is DAC-only (no ADC, no MIC pins) and the Zero2 PCB routes no microphone net. No code written, no `sunxi/h616-codec-capture` branch created (nothing honest to put on it). Details in §1. |
| (B) composite TV-out (CVBS) from the H616 TVE | Implemented as a 6-patch kernel series + Zero2 expansion-board overlay on branch `sunxi/h616-tve` (= `wt-audio-integration`). New `sun8i_tve` DRM encoder driver, TCON TOP clock-source plumbing, DE33 YUV output, CCU tweak, binding, DT. Compiles clean (see §5). Needs a TV to confirm. |

## 1. Hardware facts (verified from primary sources, not from the task statement)

**H616 audio codec has no capture path.**
- Allwinner H616 User Manual V1.0 (`H616_User_Manual_V1.0_cleaned.pdf`, fetched via web.archive.org since linux-sunxi.org blocks non-browser clients; text extracted with a stdlib-only PDF string dump, see §6), §8.4.1 "Audio Codec ... features": *"Supports 8 kHz to 192 kHz DAC sample rate; ... One differential LINEOUTP/N or single-end LINEOUTL/R output"*. No ADC, no MIC bias, no MIC input is listed. The memory map (§8) has `Audio Codec 0x05096000` and a separate `DMIC 0x05095000` (digital PDM microphone interface) — that is the only microphone input the SoC has.
- Vendor kernel (`orangepi-xunlong/linux-orangepi`, branch `orange-pi-5.4-sun50iw9`, `sound/soc/sunxi_v2/snd_sun50iw9_codec.c`): every capture entry point is `SND_LOG_WARN(HLOG, "unsupport capture")`; the ADC register names in its header are shared boilerplate.
- Mainline: Chen-Yu Tsai, "ASoC: sun4i-codec: Set quirks.playback_only for H616 codec" (2026-07-14, Fixes: 9155c321a1d0, applied to the sound tree for-7.2 as d9e96f859de3, Acked-by Jernej Škrabec) — the 7.3.1 driver already has `.playback_only = true` for `allwinner,sun50i-h616-codec`.
- Orange Pi Zero2 schematic (`kernel-check/scratch/zero2-sch/sch.pdf`, v1.3, text dump): SoC balls `LINEOUTL G19`, `LINEOUTR G20`, `TV_OUT J21`, `VCC_TV H20`; the "13 PIN CONNECTOR" sheet carries `USB1-DP/DM, USB1-DRVVBUS, IR-RX, USB2-DM/DP, USB3-DM/DP, LINEOUTR, LINEOUTL, TV-OUT`. The string `MIC` occurs only inside `PMIC`. There is no microphone net on the board.
- Official Orange Pi Zero2 user guide (`official_OrangePi_Zero2_user_guide.pdf`, decoded in `kernel-check/work-audio/vendor/opz2_guide.txt`): p.8 *"13 pin GPIO header with 2 USB Host, IR pin, TV-out, Audio and GPIO ports"*; p.9 *"Note: The Orange Pi Zero2 does not support MIC Input on the expansion board."*

Conclusion for (A): the expansion board's mic jack is wired to nothing on a Zero2 (the H3-based Orange Pi Zero had MIC1 on the header). The requested `arecord`/loopback test cannot succeed on any software. The only microphone option on H616 is the DMIC block (not on the 13-pin header; it would need a PDM mic on the 26-pin header, pinmux check, and a `sun50i-h616-dmic` driver — out of scope).

**H616 TV encoder.**
- It is an on-chip TVE (unlike the H6, which needed the external AC200). It is *not* the A10/H3 "sun8i-h3-tv-encoder" IP that the Armbian H3/H5 patches drive: the vendor BSP builds `de_tve_sun8iw11.c` (R40/V40 lineage) for `CONFIG_ARCH_SUN50IW9`, with `TVE_TOP_SUPPORT`, `TVE_DEVICE_NUM 1`, `TVE_DAC_NUM 1`.
- Memory map (UM §1): `TVE_TOP 0x06520000-0x06523FFF`, `TVE0 0x06524000-0x06527FFF`, `TCON_TV0 0x06515000`, `TCON_TV1 0x06516000`. Interrupt 100 = TVE (GIC_SPI 68, unused).
- CCU (UM §3 and mainline `ccu-sun50i-h616.c`): `TVE0_CLK_REG 0x0BB0` (parents PLL_VIDEO0 1x/4x, PLL_VIDEO1 1x/4x, M 1-16, N 1/2/4/8), `TVE_BGR_REG 0x0BBC` (bit0 TVE_TOP gating, bit1 TVE0 gating, bit16 TVE_TOP reset, bit17 TVE0 reset). Mainline already has `CLK_TVE0`, `CLK_BUS_TVE_TOP`, `CLK_BUS_TVE0`, `RST_BUS_TVE_TOP`, `RST_BUS_TVE0`; only `CLK_PLL_VIDEO1` was not exported to DT.
- Clocking (UM §7.2 TCON_TV): *"TCON_TV_CLK is produced by internal frequency division. If deflick function is enabled, TCON_TV_CLK is one-eighth of TVE_CLK; if deflick is disabled, TCON_TV_CLK is one-sixteenth of TVE_CLK."* The TCON TOP `TCON_TV_SETUP` register (0x00) has `tv0_clk_src` (bit0) / `tv1_clk_src` (bit4): 0 = CCU, 1 = TVE (vendor `de_lcd_type.h`, `tcon1_tv_clk_enable()`).
- Which TCON feeds the TVE: vendor `tcon_feat.c` for sun50iw9: device 0/1 = LCD, **device 2 = HDMI (TCON_TV0), device 3 = TV (TCON_TV1)**. `tcon1_tv_clk_enable(sel=3)` sets `tv1_clk_src = TV_CLK_F_TVE`.
- Colour: the TCON TV CEU on H616 cannot convert RGB→YUV (UM 7.1.6.17: `CEU_COEF_MUL_VALUE ... only can be 0 or 1`), and the vendor disables it for TV. DE33 has no post-blend DCSC (that is DE2); the vendor DE330 blends in YUV (`bld out_ctl.fmt_space`) and converts every channel with its CCSC (`de_ccsc_apply(in, out)`, tables in `de_csc_table.c`). Hence patch 3 below.
- DAC calibration: 10-bit value in SID efuse, vendor cell `tvout` at `reg = <0x2c 8>` (same offset convention as the `ths_calibration@14` cell mainline already uses), used as `(word >> 16) & 0x3ff`, default 625 when blank. Programmed into `TVE_TOP DAC_CFG0[25:16] CALI_IN`.
- Output stage: `TV_OUT` goes straight from the SoC ball to the header; the schematic text shows no buffer/op-amp (passives cannot be read from the text dump, so a series resistor/filter cannot be excluded). `VCC_TV` is on the PMIC sheet next to `AVCC/ALDO2/ALDO3`; the mainline Zero2 DT keeps all AXP305 LDOs always-on, so no regulator handling was added.
- Modes: the DRM analog TV helper provides exactly `720x480i` (NTSC) and `720x576i` (PAL) at 13.5 MHz, interlaced — matching the vendor 480I/576I tables (`TVE_000 = 0x00300000` = DAC upsample 216 MHz, i.e. 16 × 13.5 MHz, deflicker off).

Nobody has posted mainline H616 TVE support: lore search blocked (403) from here, but `jernejsk/linux-1` branches `h616-*` (incl. `h616-integration-v1`, Jul 2026) still only carry the unchanged `sun4i_tv.c`, and the Feb/Jul 2025 H616 display series on linux-arm-kernel (R. Walklin, Jernej) do not include a TVE.

## 2. Design of (B)

Pipeline: mixer0/1 → TCON TOP → **TCON TV1** → **TVE0 → DAC → TV-OUT**. HDMI stays on TCON TV0.

1. `clk-sunxi-ng-h616-prepare-tve-clock.patch` — export `CLK_PLL_VIDEO1` (11) to `dt-bindings/clock/sun50i-h616-ccu.h`; add `CLK_SET_RATE_NO_REPARENT` to `tve0`. Reason: `ccu_mux_helper_determine_rate()` scans parents in order and takes the first exact match, so a 216 MHz request would otherwise pick and re-rate `pll-video0` (HDMI). With DT `assigned-clock-parents = <&ccu CLK_PLL_VIDEO1>` the TVE lives on pll-video1 (min 288 MHz → the framework will use e.g. 432 MHz / 2).
2. `drm-sun4i-tcon-top-select-tve-clock-source.patch` — `sun8i_tcon_top_set_tv_clk_src(dev, tcon, from_tve)` writes `TCON_TV_SETUP` bit0/bit4; `sun8i_r40_tcon_tv_set_mux()` calls it for TCON ids 2/3 with `encoder_type == DRM_MODE_ENCODER_TVDAC`. The TCON still does its own `clk_set_rate(tcon-ch1, 13.5 MHz)` on the (now unused) CCU `tcon-tv1` clock; harmless.
3. `drm-sun4i-mixer-support-yuv-output-on-de33.patch` — `sun50i_engine_ops` gets `apply/disable_color_correction` (DE33 only): blender `OUTCTL[9:8] fmt_space = YUV`, background/pipe0 fill colour `0xff108080`, `mixer->output_yuv`. `sun8i_csc_config()` now looks at the owning mixer: RGB planes → `RGB2YUV` (BSP `r2y[0]`, full RGB → limited BT.601), YUV planes → pass-through if already BT.601 limited, else `YUV2YUV` (BSP `y2yl2l`/`y2yf2l` into limited BT.601, with the existing YVU column swap). DE33 UI channels also get `sun8i_csc_config()` (they have a CCSC at `0x800 + ch*0x20000` too). `sun4i_crtc_mode_set_nofb()` requests the output colour space from the encoder type *before* the planes of the commit are programmed (drm commit order is crtc mode_set → planes → encoder enable; the per-layer CSC would otherwise lag one commit). DE2/A10 behaviour is unchanged (their callbacks are idempotent).
4. `dt-bindings-display-add-h616-tv-encoder.patch` — `allwinner,sun50i-h616-tv-encoder.yaml`: reg `tve`/`top`, clocks `bus`/`mod`/`top`, resets `tve`/`top`, `nvmem-cells` "calibration", input `port`. (`dtschema` is not installed here, so `dt_binding_check` was not run.)
5. `drm-sun4i-add-h616-tv-encoder.patch` — new `drivers/gpu/drm/sun4i/sun8i_tve.c` (`CONFIG_DRM_SUN8I_TVE`, default `DRM_SUN4I`, depends on `DRM_SUN8I_MIXER`), component like `sun4i_tv.c`:
   - bind: deassert `top` then `tve` resets, enable `top`/`bus`/`mod` clocks (mod stays on while bound because TCON TV1's pixel clock is derived from it), read calibration, program TVE TOP DAC regs exactly as the BSP (`DAC_MAP = OUT0/TVE0`, `CFG1 = 0x23a` REF_EXT_SEL+REF2 0.40 V+REF1 1.00 V, `CFG2 R_SET = 0x10`, `CFG0 = CLOCK_INVERT | CALI_IN | LOW_BIAS(4) | BIAS_EXT_SEL`, DAC_EN off), `DRM_MODE_ENCODER_TVDAC` + `DRM_MODE_CONNECTOR_Composite`, `tv_mode` property NTSC/PAL (default PAL), `interlace_allowed`.
   - `atomic_mode_set`: `clk_set_rate(mod, crtc_clock × 16)` = 216 MHz.
   - `atomic_enable`: vendor 480I/576I register set written with named fields (CFG `0x0707000x`, `NOTCH` Y/C delay, chroma freq, porches 118/32 and 138/24, first line 22 / 525 or 625 lines, levels, burst 22/68/126, gains, sync 0x10, white 0x320, active line `hdisplay*2`, resync `BIT(29)|line 15|pixel 12`, PAL-only noise reduction `0x3a0 = 0x00030001`, NTSC-only `BYPASS_YCLAMP`), then `apply_color_correction`, DAC_EN, `GCTL = CLOCK_EN | ENABLE`.
   - `atomic_disable`: clear GCTL bits, DAC off, `disable_color_correction`.
   - Not implemented: cable detection (TVE has a DAC load detector, BSP polls it every 200 ms while the output is off) — connector always reports *connected*. Only CVBS; no S-video/YPbPr/VGA.
6. `arm64-dts-sun50i-h616-add-tv-encoder.patch` — `tve: tv-encoder@6524000` (disabled), `tcon_tv1_out_tve: endpoint@0` with `allwinner,tcon-channel = <1>` next to the existing HDMI `endpoint@1`, `tve_calibration: tve-calibration@2c { reg = <0x2c 0x4>; }` in `sid`, `assigned-clocks`/`assigned-clock-parents` to pll-video1.

Armbian glue (not kernel patches): `overlay_64/sun50i-h616-orangepi-zero2-expansion.dtso` (enables `&ir` and `&tve`; header comment documents the no-MIC fact), `config/kernel/linux-sunxi64-edge.config` `CONFIG_DRM_SUN8I_TVE=y`, `series.conf` block appended at the very end (the patches must follow `0702-...` (CCU/dt-bindings), `patches.drm/004x` (TCON TOP/TV/DT), `drm-sun4i-support-the-h3-and-h5-tv-encoders.patch` (mixer) and the `7000-7006` A523 patches (`uses_rcq` in `sun8i_mixer`)).

## 3. Branches and commits

| Branch | Commits (on top of `27a7f72`) |
|---|---|
| `sunxi/h616-tve` | `cce6763` sunxi-7.3: add Allwinner H616 TV encoder (composite video) support; `8f829e3` sunxi-7.3: add Orange Pi Zero2 expansion board overlay (IR, TV-out) |
| `wt-audio-integration` | same two commits (linear, = `sunxi/h616-tve`) |
| `sunxi/h616-codec-capture` | not created — see §1 |

Files (all under `patch/kernel/archive/sunxi-7.3/` unless noted):
`patches.armbian/clk-sunxi-ng-h616-prepare-tve-clock.patch`, `patches.armbian/drm-sun4i-tcon-top-select-tve-clock-source.patch`, `patches.armbian/drm-sun4i-mixer-support-yuv-output-on-de33.patch`, `patches.armbian/dt-bindings-display-add-h616-tv-encoder.patch`, `patches.armbian/drm-sun4i-add-h616-tv-encoder.patch`, `patches.armbian/arm64-dts-sun50i-h616-add-tv-encoder.patch`, `overlay_64/sun50i-h616-orangepi-zero2-expansion.dtso`, `overlay_64/Makefile` (dtbo registered, like the other sunxi overlays), `series.conf`, `config/kernel/linux-sunxi64-edge.config`.

The six patches are real `git format-patch` output (From/Date/Subject/body/Signed-off-by, upstream-style messages) with Armbian's `index 111111111111..222222222222` convention; the generating git history is kept in `/home/aruni/orangepizero2/kernel-check/work-audio/tve-src.git` (bare, baseline = 7.3.1 + full Armbian series, then one commit per patch) for rebasing/upstream submission (in sync with the exported patches).

## 4. Upstreamability notes

- Patches 1, 2, 4, 5, 6 are shaped for linux-sunxi review. Expect review questions on: the undocumented bits copied from the BSP (`GCTL` bit31 semantics, `CFG` bit18, `RESYNC` bit29, `NR 0x3a0`), the fixed `/16` relation (TVE clock as a real clock-mux parent of `tcon-top-tv1` with a fixed-factor divider would be the "clk framework" way; the explicit TCON TOP bit + TVE rate set was chosen as the smaller, deterministic change), and whether `CLK_SET_RATE_NO_REPARENT` belongs on `tve0` or whether the TCON TV clocks should get it too.
- Patch 3 is the one most likely to be reworked upstream (Jernej's DE33 planes work is still being restructured; a generic "engine output format" API would be preferable to re-using the color-correction callbacks). It is self-contained and only affects DE33 when a TVDAC encoder is attached.
- Sibling conflict check: `wt-kernel` touched `sun50i-h616-orangepi-zero.dtsi`, EMAC, Cedrus, PM, USB overlay; `wt-wifi` the uwe5622 driver. None of them touch `sun50i-h616.dtsi` display nodes, `drivers/gpu/drm/sun4i`, `ccu-sun50i-h616.c` or the series.conf tail, so a linear integration should apply without conflicts (not attempted here; those trees must not be touched by this agent).

## 5. Compile results

Tooling: `ARMBIAN=/home/aruni/orangepizero2/wt-audio WORK=/home/aruni/orangepizero2/kernel-check/work-audio /home/aruni/orangepizero2/kernel-check/build-kernel.sh` (unchanged script; ccache shared).

- `STAGE=patch`: 690 patches applied, 0 failed (before adding mine); the final full run below re-applies the series including the 6 new patches.
- Incremental checks during development (in the patched tree, Armbian `linux-sunxi64-edge.config` + `olddefconfig`): `make W=1 drivers/gpu/drm/sun4i/` → 0 errors, 0 warnings; `olddefconfig` resolves `CONFIG_DRM_SUN8I_MIXER=y`, `CONFIG_DRM_SUN8I_TCON_TOP=y`, `CONFIG_DRM_SUN8I_TVE=y`; `allwinner/sun50i-h616-orangepi-zero2.dtb` builds without dtc warnings; decompiled DTB shows `tv-encoder@6524000` with `assigned-clock-parents = <&ccu 11>`, `nvmem-cells`, the `tcon_tv1_out_tve` endpoint and `tve-calibration@2c`.
- Full `STAGE=all` run with the final patches (`kernel-check/work-audio/stage-all2.log`, `build.log`): **696 patches applied, 0 failed; `build exit: 0`** (Image + modules + Zero2 DTB); 9 C warnings, all pre-existing and unrelated (sunxi-sysinfo, axp20x, sunxi-addr, panel-simple, fdt_address, uwe5622, sunxi_sid); `drivers/gpu/drm/sun4i/sun8i_tve.o` built in. Two environment hiccups, neither caused by the patches: the first attempt (`stage-all.log`) died with "Cannot create temporary file in /tmp/: No space left on device" because the shared 31 GB tmpfs was 96% full of other agents' `mmdebstrap` rootfs builds (rerun with `TMPDIR` on disk — the script itself is unchanged), and the second attempt's trailing dtbs step was skipped because another agent rewrote `build-kernel.sh` at 23:20 while bash was still reading it.
- `STAGE=dtbs` with the current script (`stage-dtbs.log`): `dtbs exit: 0`, 17 dtc warnings all pre-existing in `sun50i-a64-pine64-7inch-lcd.dtso` / `sun50i-h5-nanopi-r1s-h5.dts`, **54 H616 overlays built** (53 before + `sun50i-h616-orangepi-zero2-expansion.dtbo`), `DT_CHECK ok` for `tv-encoder@6524000`, `tve-calibration@2c`, `tcon_tv1_out_tve`. Applying the overlay to the built Zero2 DTB with `scripts/dtc/fdtoverlay` succeeds and flips both `tv-encoder@6524000` and `ir@7040000` to `status = "okay"` (result kept as `work-audio/z2exp.dtb`).
- Not run: `dt_binding_check` (no `dtschema` on this host), `checkpatch.pl` (not requested; patches follow kernel style, 80-col).

## 6. Sources used

- Allwinner H616 User Manual V1.0 (cleaned), `https://web.archive.org/web/2024id_/https://linux-sunxi.org/images/2/24/H616_User_Manual_V1.0_cleaned.pdf` → `kernel-check/work-audio/vendor/H616_User_Manual_V1.0_cleaned.pdf`; register text dumps `um_strings.txt`, `um_tve_regs.txt` (TVE register bit tables), chapters used: 7.2 TCON_TV, 7.3 TVE, 8.4 Audio Codec, 3 CCU, 1 memory map. (The H616 datasheet could not be fetched — linux-sunxi 404s for non-browsers, Wayback returns 500.)
- Vendor sources (GPL, used as documentation only): `orangepi-xunlong/linux-orangepi` @ `orange-pi-5.4-sun50iw9`: `drivers/video/fbdev/sunxi/disp2/tv/{de_tve_sun8iw11.c,de_tvec.h,drv_tv.c,drv_tv.h}`, `disp2/disp/de/{disp_tv.c,disp_al_tcon.c,disp_features.c}`, `lowlevel_v33x/{tcon_feat.c,disp_al_de.c,tcon/de_lcd.c,tcon/de_lcd_type.h}`, `lowlevel_v33x/de330/{de_rtmx.c,de_bld.c,de_bld_type.h,de_ccsc.c,de_csc_table.c,de_fmt.c}`, `sound/soc/sunxi_v2/snd_sun50iw9_codec.{c,h}`, `arch/arm64/boot/dts/sunxi/{sun50iw9.dtsi,sun50i-h616-orangepi-zero3.dts}` — all in `kernel-check/work-audio/vendor/`.
- Orange Pi Zero2 user guide: `https://cdn.shopify.com/s/files/1/0252/6615/9704/files/official_OrangePi_Zero2_user_guide.pdf` → `vendor/opi_zero2_guide.pdf`, decoded text `vendor/opz2_guide.txt`. Zero2 schematic text: `kernel-check/scratch/zero2-sch/sch3.txt` (fetched by the kernel agent).
- Mainline references in the patched tree: `sun4i_tv.c` (A10 TVE), Armbian `drm-sun4i-support-the-h3-and-h5-tv-encoders.patch`, Jernej's `patches.drm/0041,0043,0046` (H616 TCON TOP/TV/DT), `sun8i_csc.c` (DE3/DE33 CSC layout), `sun8i_tcon_top.c`, `drm_modes.c`/`drm_probe_helper.c` (analog TV modes), `ccu-sun50i-h616.c`, `ccu_mux.c` (determine_rate/NO_REPARENT).
- Upstream status: patchew `20260714113304.270224-1-wens@kernel.org` (H616 codec playback_only), `jernejsk/linux-1` branch list, linux-arm-kernel H616 display series (Feb/Jul 2025).

## 7. Open hardware questions (cannot be settled without the board)

1. Does the picture appear and lock at all — i.e. are the BSP-derived constants (DAC bias/ref values, `GCTL` bit31, 216 MHz upsample, resync 15/12) right for an interlaced 13.5 MHz TCON input? The BSP's own NTSC/PAL default path uses 27 MHz progressive input + deflicker (`/8`); this driver uses the BSP's *480I/576I* variant (`/16`, no deflicker) to match the DRM analog modes and the A10/H3 drivers. If the image rolls or shows doubled fields, the alternative is a `/8` + deflicker mode (TCON at 27 MHz, `LP_CTL 0x380 = 0x300`, `GCTL` deflick bits 13:10).
2. Colours: the DE33 YUV path (blender fmt_space + per-channel CCSC) has never been exercised in mainline. Wrong colours (green/magenta cast) point at the CSC coefficients/channel order; a grey-scale-only or blank picture at TVE but HDMI fine points at the blender `fmt_space` bit.
3. Whether `tcon_tv1` really is the TVE source on the H616 (derived from the vendor feature table; the manual does not state it). If the connector appears but the screen stays black with everything enabled, try moving the TVE endpoint to `tcon_tv0_out` (HDMI then must use TCON TV1 — the TCON TOP HDMI mux already supports that).
4. DAC calibration efuse contents on this particular Zero2 (dump `/sys/bus/nvmem/devices/sunxi-sid0/nvmem` offset 0x2c); a blank efuse falls back to 625 like the BSP.
5. Cable detection values (`AUTO_DETECT_*`) — untested, not wired up.
6. HDMI + TVE at the same time: both outputs active with independent PLLs is the design intent; verify HDMI does not flicker when the TVE mode is set (clock summary below).

## 8. Exact board test steps (coordinator)

Build the kernel/image from `wt-audio-integration` (or apply the two commits on the integration branch). Then on the board:

```sh
# 1. enable the overlay (Armbian naming: prefix sun50i-h616- is implicit)
sudo sed -i 's/^overlays=.*/& orangepi-zero2-expansion/; t; $a overlays=orangepi-zero2-expansion' /boot/armbianEnv.txt
grep overlays /boot/armbianEnv.txt && sudo reboot

# 2. driver and pipeline came up?
dmesg | grep -iE 'sun8i-tve|tv-encoder|sun4i-drm|tcon|mixer'
ls /sys/bus/platform/drivers/sun8i-tve/            # expect 6524000.tv-encoder
sudo cat /sys/kernel/debug/clk/clk_summary | grep -E 'pll-video[01]|tve0|tcon-tv[01]|tcon-top-tv[01]|bus-tve'

# 3. connector and modes (libdrm-tests)
modetest -M sun4i-drm -c            # expect "Composite-1  connected", modes 720x576i / 720x480i, prop "TV mode"
modetest -M sun4i-drm -e            # TVDAC encoder, possible crtcs

# 4. PAL test pattern (CONN/CRTC ids from step 3; "TV mode" enum: 0=NTSC 3=PAL)
modetest -M sun4i-drm -w <CONN>:"TV mode":3 -s <CONN>@<CRTC>:720x576i
# 5. NTSC
modetest -M sun4i-drm -w <CONN>:"TV mode":0 -s <CONN>@<CRTC>:720x480i
# 6. YUV plane path (overlay plane, checks the YUV2YUV/pass-through CSC)
modetest -M sun4i-drm -s <CONN>@<CRTC>:720x576i -P <PLANE>@<CRTC>:720x576@NV12

# 7. fbcon on the TV (kernel cmdline, optional): video=Composite-1:720x576i,tv_mode=PAL

# 8. register sanity while the pattern is up (devmem2 or busybox devmem)
sudo devmem 0x06510000            # TCON TOP TV_SETUP: expect bit4 set (TCON TV1 clock from TVE)
sudo devmem 0x06524000            # TVE GCTL: expect 0x80300001
sudo devmem 0x06520028            # TVE TOP DAC_CFG0: bit0 DAC_EN set, [25:16] calibration
sudo cat /sys/kernel/debug/dri/0/state | grep -A30 'connector\[.*Composite'

# 9. HDMI unaffected? keep an HDMI monitor attached during 4/5 and check clk_summary pll-video0 did not change.
```

Expected: `clk_summary` shows `tve0` at 216000000 under `pll-video1` (432 MHz or another multiple), `tcon-top-tv1` enabled; the TV shows the modetest colour bars with correct colours (red/green/blue order) and stable sync. Capture (A) cannot be tested — see §1.

Debug knobs if it fails: `drm.debug=0x1f` on the cmdline (`DRM_DEBUG_DRIVER` lines "Enabling the TV Output", "Switching mixer output to YUV"); `/sys/kernel/debug/regmap/6524000.tv-encoder-tve/registers` and `.../6524000.tv-encoder-tve-top/registers` for live register dumps.
