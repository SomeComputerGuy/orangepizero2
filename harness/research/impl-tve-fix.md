# H616 TV-out (TVE) boot loop: root cause and fix

Branch `fix/sunxi-h616-tve` (worktree `/home/aruni/orangepizero2/wt-tve`), based on stonking-orangepizero2 6b59b07c6.
Status: built, and **verified on the board on 2026-11-03** (trial kernel Image.tve1 on the image-4321861ff rootfs; see "Board trial").

## Symptom (board, 2026-11-03, image 4321861ff)

With `overlays=orangepi-zero2-expansion` (which enables `&tve` and `&ir`), every boot follows the same sequence:
1. fbcon modesets Composite-1 on crtc-1 (mixer1 → TCON TV1 → TVE).
2. `[CRTC:72:crtc-1] vblank wait timed out` (WARN) appears, then a chain of 10 s `flip_done timed out` errors.
3. The board resets about 55 s after the kernel starts, then repeats.

The reset comes from the image's systemd `RuntimeWatchdogSec=15` (userpatches/customize-image.sh) feeding the 16 s
sunxi-wdt. fbcon holds the console across the commit timeouts, so PID 1 stalls on console output and stops
petting the watchdog. Panfrost's `-110` probe failure in the same window is collateral.

Contained test (overlay + `video=Composite-1:d`, then a forced modeset):
- Clocks were correct: pll-video1/tve0 at 216 MHz, tcon-tv1/tcon-top-tv1 at 13.5 MHz, and TCON_TV_SETUP = 0x10
  (TV1 clock from the TVE).
- TCON TV1 was enabled (GCTL 0x80000003, TCON1_CTL 0x80100160), but its line counter (0x065160FC) stayed at 0 and
  IRQ 99 never fired.
- Selecting the CCU clock source at runtime did not help either.

## Root cause: wrong TCON TV1 clock gate bit on the H616

TCON TOP GATE_SRC (0x06510020) read **0x11100000**: bits 28 (HDMI source), 24 and 20.
- Mainline `sun8i_tcon_top` takes its gate bits from the R40: `TCON_TOP_TCON_TV0_GATE` 20,
  **`TCON_TOP_TCON_TV1_GATE` 24** and DSI 16. Armbian `patches.drm/0041` (H616 TCON TOP) reuses them, with only
  `has_tcon_tv1 = true`.
- The H616 BSP (`linux-orangepi` orange-pi-5.4-sun50iw9, `lowlevel_v33x/tcon/de_lcd_type.h`,
  `union tcon_clk_gate_reg_t`) lays the register out differently: `dsi0_clk_gate` 16, `dsi1_clk_gate` 17,
  `tv0_clk_gate` 20, **`tv1_clk_gate` 21**, `hdmi_src` 29:28. `tcon1_tv_clk_enable(sel = 3)` sets
  `tv1_clk_src = TVE` and `tv1_clk_gate`.
- On the H616, bit 24 therefore gates nothing. The `tcon-top-tv1` clk reports enabled while TCON TV1 gets no clock:
  no line counter, no vblank, no IRQ.
- HDMI was never affected, because the TV0 gate (bit 20) is the same on both SoCs. That is why only the TV path broke.
- The H616 User Manual V1.0 does not document TCON TOP at all, so the BSP is the only reference.

The other suspects checked out:

| Suspect | Finding |
|---|---|
| TCON TOP TV clock source | Selected correctly (0x00 bit4) |
| Port mux (PORT_SEL 0x1C) | 0x32, i.e. DE0 → TCON TV0 (2) and DE1 → TCON TV1 (3), as the BSP's `de_port*_perh` |
| Bus gates | bus-tcon-tv1, bus-tve0 and bus-tve-top on |
| Resets | Deasserted (registers read back) |
| IRQ line | 99 = 6516000 per DT (GIC SPI 67) |

## Fixes (patches.armbian, appended after the H616 TVE block in series.conf)

1. `drm-sun4i-tcon-top-fix-the-h616-tcon-tv1-clock-gate.patch`
   - Adds a `tcon_tv1_gate` field to the quirks and sets it to bit 21 on the H616. R40 keeps bit 24.
   - This is the actual fix: TCON TV1 should run and raise vblanks.
2. `drm-sun4i-sun8i-tve-report-the-composite-connector-from-dac-load-detection.patch` (makes the failure non-fatal)
   - The connector had no `.detect`, so it was always "connected" and fbcon lit it on every boot.
   - It now programs the DAC load detector as the BSP does (`tve_low_dac_autocheck_enable()`):
     - 0x0F8 = 0x200, 0x0FC = 0x0A3C00FF (20 ms × 10), 0x03C = 0x9999;
     - 0x030 = new-detect-mode bit31 | DAC0 enable;
     - the encoder clock (GCTL bit31) stays on while bound, across mode set and disable.
   - `.detect` reads 0x038 bits 1:0. A value of 1 means connected, anything else means disconnected. The connector is polled.
   - Without a TV, Composite reads disconnected, so neither fbcon nor any other client enables it. The expansion
     overlay (and with it IR) boots even if TCON TV1 were still broken.
   - The feature is not dropped: a TV is detected automatically, and the output can always be forced with
     `video=Composite-1:e` or the sysfs `status` attribute.

**Not fixed (and why):** a missing vblank on any CRTC still costs 10 s per commit, and fbcon on such a CRTC can still
starve PID 1. That is generic DRM/fbcon behaviour. With fix 2 the Composite CRTC is never touched unless a TV is
present or the user forces it; with fix 1 it gets vblanks.

**Unverified until the board run:**
- whether bit 21 really starts TCON TV1;
- what the detector reads with no load (it must not read 1);
- detection with a real TV, which needs a TV and the 13-pin board, so it stays pending even after the trial.

## Host checks

WORK=kernel-check/work-tve/kb, `ARMBIAN=wt-tve`:
- STAGE=patch: 805 applied, 0 failed on the baseline. With the two fixes: **807 applied, 0 failed**.
- STAGE=all: build exit 0, **0 C warnings**; dtbs exit 0 (17 dtc warnings, all pre-existing and not H616); 57 H616 overlays.
- DT_CHECK ok for `tv-encoder@6524000` and `tcon-top@6510000`.
- `make W=1 drivers/gpu/drm/sun4i/`: rc 0, **0 warnings** (`work-tve/kb/w1-sun4i.log`).
- Trial artifacts in kernel-check/vdec-serve:
  - `Image.tve1` (sha256 502c0fc22f447d57…)
  - `modules-tve1.tgz` (5dfec88e028d1cc4…, top dir 7.3.1/, INSTALL_MOD_STRIP=1)
  - `CONFIG_DRM_SUN8I_TVE=y` and sun4i-drm built in, so the fix lives in the Image.
- Note: the first cold build in this new WORK path re-fetched the 7.3.1 tarball into work-tve/kb/dl (the same
  upstream tarball). The first build in a new WORK is ccache-cold because of hash_dir.

Branch commit: `fix/sunxi-h616-tve` 6936ed2f9 (author Arun, `Assisted-by: Claude:claude-opus-5-5`). Not pushed.

## Board plan (one shot, about 25 min): harness/tve-trial/run-trial.sh

1. `install`
   - Image.tve1 + modules-tve1.tgz via install-kernel.sh, which arms vdec-fallback: it restores the image kernel at
     300 s without `/run/vdec-ok`.
   - The image DTB is kept: no DT changes; the overlay already enables `&tve`.
   - Also ships the client, devmem.py and observe.sh, and backs up armbianEnv.txt.
2. `phaseA`: trial kernel without the overlay. Regression check: HDMI connector, no flip_done/WARN/Oops.
3. `phaseB`: adds `overlays=orangepi-zero2-expansion` and reboots.
   - **PASS = uptime > 120 s**: the watchdog loop is gone.
   - Composite-1 must read *disconnected* with no TV.
4. `observe` (observe.sh). Observables:
   - GATE_SRC bit 21 set while Composite is active;
   - TCON TV1 line counter (0x065160FC) changing between two reads;
   - IRQ 99 count rising;
   - TVE 0x030 = 0x80000001 and 0x038 bits 1:0 ≠ 1 with no TV;
   - forced XR24 and NV12 on Composite-1 at 720x576i completing 100 flips at the field/frame rate, with no
     `flip_done` or `vblank wait` errors;
   - connector back to disconnected after release.
5. If phaseB loops: `recover` interrupts U-Boot via /dev/ttyOPIZ2 (`tools/uboot-noovl.py`), boots without
   overlays and drops the overlay line.
6. `restore`
   - restores the original armbianEnv, the Image symlink to vmlinuz-7.3.1-edge-sunxi64, and removes the trial
     modules (7.3.1 dir);
   - reboots and checks `DRAM: 1024 MiB` plus the image kernel.


## Board trial (2026-11-03, 08:0x–08:33 UTC)

Run with harness/tve-trial/run-trial.sh in order: install, phaseA, phaseB, observe, restore. `recover` was not
needed. Raw data: harness/tve-trial/results-20261103/tve-out/.

- **phaseA** (trial kernel 7.3.1, no overlay): boots; 0 flip_done/vblank/WARN/Oops; HDMI connector present
  (disconnected, no sink).
- **phaseB** (`overlays=orangepi-zero2-expansion`): tv-encoder `okay`; **uptime 123 s, no watchdog loop (PASS)**.
  With no TV, Composite-1 is *disconnected*, so fbcon did not touch it.
- **observe**:

| Observable | Idle (no TV) | Composite forced on | After release |
|---|---|---|---|
| TCON TOP GATE_SRC | 0x00000000 | **0x00200000 (bit 21)** | 0x00000000 |
| TCON TOP TV_SETUP / PORT_SEL | 0 / 0 | 0x10 (TV1 clock from TVE) / 0x30 (DE1 → TCON TV1) | 0x10 / 0x30 |
| TCON TV1 line counter (0x065160FC) | 0x10000000 static | **0x5000003F → 0x500000F3 (running)** | static (disabled) |
| IRQ 99 (6516000.lcd-controller) | 0 | **262**, then 375 | 375 |
| TVE AUTO_DETECT_EN / STATUS | 0x80000001 / 0x0 | 0x80000001 / 0x0 | 0x80000001 / 0x0 |
| Composite-1 | disconnected | connected (forced) | disconnected |

- **Forced flips, 720x576i PAL, 100 flips each:**
  - XR24 on the mixer1 primary plane: 49.999 flips/s, sd 0.034 ms, 0 gaps.
  - NV12 on the mixer1 VI plane (the DE33 YUV-output path): 49.994 flips/s, 0 gaps.
  - One flip per field (50 fields/s), as expected for interlaced output.
  - No flip_done, vblank-wait or WARN messages.
- **restore:** original armbianEnv; Image → vmlinuz-7.3.1-edge-sunxi64; `/lib/modules/7.3.1` restored to the
  jpegfix modules another agent had left there (saved at install and moved back); trial files removed. After the
  reboot, serial shows `DRAM: 1024 MiB` and the image kernel is running.

**Result:**
- Fix 1 (GATE_SRC bit 21) makes TCON TV1 run and raise vblanks.
- Fix 2 keeps Composite off when no TV is attached, so the expansion overlay (TV-out + IR) boots.
- **Still pending (needs a TV + the 13-pin board):**
  - the picture itself (levels, colour, PAL/NTSC timing);
  - load detection reporting *connected* with a TV attached.
