# Allwinner H616 datasheet: feature acceptance checklist for the Orange Pi Zero2

Source: *H616 Datasheet Revision 1.0* (Allwinner, 2019-12-30), chapter 2 "Features" (§2.1–2.11). The PDF is kept locally in
`docs/vendor/` (git-ignored, Allwinner copyright). Below, the claims are paraphrased; quotes are kept to a few words.
**[docs/spec-checklist.md](spec-checklist.md) remains the primary acceptance list.** This file adds the SoC capabilities that the
orangepi.org page does not list. Where a row is the same as a spec-checklist row, it says "tracked" and does not repeat the detail.

Audit date: 2026-11-03. Our tree: armbian-build `stonking-orangepizero2` cf62ac65a (`patch/kernel/archive/sunxi-7.3`), built tree
`kernel-check/work-vdec/linux-7.3.1` (`.config` and DTs). Board: image kernel 7.3.1 `#12` (built 2026-11-03 00:29 UTC). The board
checks were read-only: `/proc/device-tree`, `dmesg`, `/sys`, `/proc/crypto`, `v4l2-ctl --list-formats[-out]` and `vulkaninfo --summary`.

Board wiring evidence: Zero2 schematic v1.3 (`kernel-check/scratch/zero2-sch/sch.pdf`, text dump `sch3.txt`). Sheet 9
"CARD-USB-DEBUG-EXT26-HDMI" routes nets **PC5 PC6 PC7 PC8 PC9 PC10 PC11 PC14** to the 26-pin header, together with TWI3
(PH4/PH5), SPI1 (PH6–PH9) and UART5 (PH2/PH3). The DT uses PC0/PC2/PC3/PC4 for the SPI NOR, PC12/PC13 for the LEDs and PC16 for the
USB1 VBUS switch. All PI pins go to the RGMII PHY (RTL8211F). PG0–PG9 carry the SDIO WiFi and UART1 BT, and PG10–PG19 hold the
WiFi/BT control lines plus the 32 kHz clock (GPIO ASSIGNMENT page). The datasheet's own pin-mux table (§4.3) is used to check which
functions can reach a free pin.

Status legend: **OK** = verified on the board · **OK\*** = driver + DT present, not functionally verified · **PARTIAL** = works
with a known gap · **GAP** = no driver/DT/config in our tree, or a test shows it fails · **N/A** = not wired out on the Zero2
(evidence given), or exists only for the secure world.

## 2.1 CPU architecture

| Feature | Datasheet claim | Driver/DT state in our tree | Verified on board? | Status | Next step |
|---|---|---|---|---|---|
| 4× Cortex-A53 | quad-core | mainline DT, PSCI, cpufreq-nvmem | yes: 4 CPUs, DVFS 480–1512 MHz | OK | tracked (spec-checklist CPU row) |
| ARMv8, 64-bit execution | AArch64 | arm64 kernel | yes | OK | — |
| **32-bit execution state** | "64 and 32bit execution states" | **`# CONFIG_COMPAT is not set`** in `linux-sunxi64-edge.config`, so AArch32 EL0 binaries cannot run | no | **GAP** | **W6**: set `CONFIG_COMPAT=y` (+ `COMPAT_VDSO` needs an arm32 cross compiler); test a static armhf binary |
| TrustZone | supported | TF-A lts-v2.14.11 BL31 runs in the secure world (PSCI, suspend) | yes (PSCI, SYSTEM_SUSPEND) | OK | — |
| NEON / Advanced SIMD | supported | `asimd` in `/proc/cpuinfo` Features | yes | OK | — |
| LPAE | supported | AArch32 feature. arm64 uses 48-bit PA (`CONFIG_ARM64_PA_BITS=48`) | n/a | N/A (arm64 kernel; only relevant to a 32-bit kernel) | — |
| VFPv4 FPU | supported | `fp` in Features | yes | OK | — |

## 2.2 GPU architecture

| Feature | Datasheet claim | Driver/DT state | Verified on board? | Status | Next step |
|---|---|---|---|---|---|
| Mali-G31 | "G31" (no MP count) | panfrost, `gpu@1800000`, OPP 306–600 MHz | yes: SHADER_PRESENT=0x1 | OK | tracked |
| OpenGL ES 1.0 / 2.0 / 3.2 | supported | Mesa 26.2.4 panfrost: ES 3.1; ES1 not built (Ubuntu `-Dgles1=disabled`) | yes | PARTIAL | tracked (spec-checklist GPU row) |
| **Vulkan 1.1** | supported | `mesa-vulkan-drivers` (panvk) shipped (005aa71). Mesa 26.2.4 `panvk_physical_device.c` **refuses arch v6/v7 (Bifrost) unless `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1`**, and `get_api_version()` returns **1.0** for `PAN_ARCH < 10` | yes (2026-11-03): without the env var only llvmpipe is listed ("panvk is not well-tested on v7"). With it: `Mali-G31 MC1`, panvk, **apiVersion 1.0.354, conformanceVersion 0.0.0.0** | **GAP** | new item **W1**: decide the route (Mesa panvk Bifrost work up to 1.1, or Arm's DDK as for GLES 3.2/OpenCL 2.0); short term, document the env var |
| OpenCL 2.0 | supported | rusticl: OpenCL 3.0 / OpenCL C 1.2 | yes | PARTIAL | tracked |

## 2.3 Memory subsystem

### 2.3.1 Boot ROM

| Feature | Datasheet claim | Driver/DT state | Verified on board? | Status | Next step |
|---|---|---|---|---|---|
| Boot from SD (SMHC0) | supported | U-Boot SPL on SD | yes | OK | — |
| Boot from eMMC (SMHC2) | supported | — | — | N/A: no eMMC. SDC2 pins PC5/PC6/PC8–PC11/PC14 go to the 26-pin header (sch. sheet 9), PC0 = SPI NOR, PC13 = LED | — |
| Boot from raw NAND | supported | — | — | N/A: no NAND, same pins as above (NAND_WE/CLE/CE0/CE1 = PC0/PC2/PC4/PC3 hold the SPI NOR) | — |
| Boot from SPI NOR | supported | U-Boot on the 2 MB SPI NOR, BROM boots "sunxi SPI" | yes | OK | tracked |
| Boot from SPI NAND | supported | — | — | N/A: the SPI0 chip select carries the soldered SPI NOR, and SPI1 is not a BROM boot device | — |
| Secure boot / secure BROM loads only certified firmware | supported | not configured (needs the ROTPK burned into eFuse) | no | N/A by decision: the eFuse burn is **irreversible** and would lock the board to signed images | user decision (W27). Normal boot = OK |
| Mandatory upgrade through SMHC0 and USB (FEL) | supported | BROM FEL over USB0 (USB-C). U-Boot `fel` boot target is present | no (power-only USB-C cable) | OK\* | new item **W9**: with a USB-C data cable, `sunxi-fel version` + `sunxi-fel uboot` |

### 2.3.2 SDRAM

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| 32-bit DDR3/DDR3L/DDR4/LPDDR3/LPDDR4 | supported | Zero2 = DDR3, x32, 720 MHz (`CONFIG_DRAM_CLK=720`); other types do not apply to this PCB | yes | OK (DDR3) / N/A (other types) | — |
| Up to 4 GB | supported | board has 1 GB | yes (1 GB) | OK (board population) | — |

### 2.3.3 NAND flash

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| ONFI 2.0/Toggle 2.0, 80-bit ECC/1 KB, 1K–32K pages, 8-bit bus, 2 CE/2 RB, SLC/MLC/TLC/EF-NAND, SDR/Toggle DDR/ONFI DDR | supported | `nand-controller@4011000` in the DTSI (disabled) | — | N/A: no NAND on the Zero2 (pins, see 2.3.1) | — |

### 2.3.4 SMHC

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| SMHC0 SD 3.0, 4-bit, SDR50 at 3.3 V | supported | `mmc@4020000`, sunxi-mmc | yes: 50 MHz, 4-bit, SD high-speed, 3.30 V (`/sys/kernel/debug/mmc0/ios`) | OK | — |
| SMHC0 SDR 150 MHz at 1.8 V / DDR 50 MHz | supported | no `vqmmc-supply`. The PF bank (`vcc-pf`) and the card rail are fixed 3.3 V regulators (ALDO1/DCDCE) shared with other banks | — | N/A: the board cannot switch the SD I/O to 1.8 V (DT regulators. The PCB tap is unconfirmed from the schematic text) | — |
| SMHC1 SDIO 3.0, 4-bit | supported | `mmc@4021000` + UWE5622, `mmc-ddr-1_8v`, vqmmc 1.8 V | yes: 50 MHz, 4-bit, **SD high-speed timing at 1.80 V** | PARTIAL | new item **W10**: add `sd-uhs-sdr104`/`sd-uhs-ddr50` (if the UWE5622 supports them), check that `ios` shows UHS, re-run the WiFi iperf |
| SMHC2 eMMC 5.1, 8-bit, HS200/DDR | supported | `mmc@4022000` (disabled) | — | N/A: no eMMC (2.3.1) | — |
| HW CRC, block size 1–65535 | supported | controller feature used by sunxi-mmc | implied by SD/SDIO OK | OK | — |

## 2.4 Video engine

### 2.4.1 Video decoding

Cedrus `/dev/video0` OUTPUT formats on the board (2026-11-03): `MG2S S264 S265 VP8F VP9F AVS2 SVC1 MG4S S263 SPKS`. CAPTURE formats:
`P010 AS01 NV12 ST12 NV21 YU12 YV12 AS12`. Patch series: `patches.media/h616-vdec/` (33 patches, series.conf l. 784–816).

| Datasheet format | Claim | Cedrus fourcc | Driver source | Bit-exact test evidence on our board | Status | Next step |
|---|---|---|---|---|---|---|
| H.265 Main10@L5.1 | 4K@60 or 6K@30 | `S265` (+P010/AS01 out) | upstream + Jernej P010 + ours (6K, AFBC recon) | **yes**: 4K Main 600/600, Main10 P010 600/600 (`e57bc497…`), 8-bit 6K 120/120 (impl-vdec §9, impl-vdec-main10-perf §0) | PARTIAL | tracked (6K Main10 OOM, 60 Hz display) |
| VP9 Profile 2 | 4K@60 | `VP9F` | Jernej VP9 + P010 | **yes**: P2 600/600 (`1e40c2b3…`), P0 600/600 | PARTIAL | tracked |
| AVS2 JiZhun 10-bit | 4K@60 | `AVS2` | ours (`media-cedrus-add-AVS2-decoding`), non-upstream uAPI | **no** (first board runs in progress. No 10-bit reference decoder) | PARTIAL (WIP) | tracked |
| H.264 BP/MP/HP@L4.2 | 4K@30 | `S264` | upstream + 256-bit DDR fix | **yes**: 4K High 300/300 (`2f51f88f…`), 42.0 fps | OK | tracked |
| H.263 BP | 1080p@60 | `S263` | Jernej `h616-mpeg4` (non-upstream uAPI) | **none** | OK\* | **W2** |
| MPEG-4 SP/ASP@L5 | 1080p@60 | `MG4S` | Jernej `h616-mpeg4` | **none** | OK\* | **W2** |
| MPEG-2 MP/HL | 1080p@60 | `MG2S` | upstream + `mpeg2-fix-field-pictures` | early only: "MPEG-2 … bit-exact" in the first status (bfb5155, 2026-11-01). That was on the pre-series kernel, no vector list or md5 is recorded, and there was no field-picture test | OK\* | **W2** (re-run with the current series, include field pictures) |
| MPEG-1 MP/HL | 1080p@60 | `MG2S` (the MPEG-2 engine decodes MPEG-1. The V4L2 MPEG-2 uAPI has no MPEG-1 flag) | upstream | **none**. Mapping **unconfirmed**: needs a userspace that sends MPEG-1 through the MPEG-2 stateless API (GStreamer `v4l2slmpeg2dec` caps / FFmpeg v4l2request mpeg1 hwaccel to check) | OK\* (unconfirmed) | **W2** |
| Xvid | 1080p@60 | `MG4S` (Xvid = MPEG-4 ASP) | Jernej `h616-mpeg4` | **none** | OK\* | **W2** |
| Sorenson Spark | 1080p@60 | `SPKS` | Jernej `h616-mpeg4` | **none** | OK\* | **W2** |
| VP8 | 1080p@60 | `VP8F` | upstream + Jernej (>2048 px, frame-size check) | early only: "VP8 … bit-exact" (bfb5155, pre-series kernel, 720p/1080p, no vectors recorded). Patch says Jernej tested 2560x1440/3840x2160 on H616 | OK\* | **W2** |
| AVS/AVS+ JiZhun | 1080p@60 | **none** | nothing anywhere (vendor libVE: AVS runs in the H.264 engine, mode 1, impl-vdec §1) | — | **GAP** | **W20**: new uAPI + cedrus backend, RE from `libawavs.so`/libVE |
| WMV9/VC-1 SP/MP/AP | 1080p@60 | `SVC1` (WMV9 = VC-1 Main) | Jernej `h616-cedrus` (non-upstream uAPI) | **none** on our board (Jernej's commit cites SMPTE conformance streams) | OK\* | **W2** |
| JPEG ("HFIF" [sic]) | 45 MPPS | **none** | VE JPEG block at VE+0xE00 (`VE_MODE` bit 5, vendor `cedar_ve` IRQ path). No V4L2 driver on any sunxi | — | **GAP** | **W21**: stateful/stateless JPEG decode in cedrus |
| Decode up to 4K@60 (general) | 4K@60 | — | see rows above | 8-bit HEVC 81.8 fps tiled, AFBC10 83.9 fps (VE-bound) | PARTIAL | tracked |

**Formats with no bit-exact test evidence on our board:** H.263, MPEG-4 SP/ASP, Xvid, Sorenson Spark, VC-1/WMV9 (all have a
driver), MPEG-1 (mapping unconfirmed), AVS2 (runs in progress), AVS/AVS+ and JPEG (no driver). MPEG-2 and VP8 have only an early
undocumented pass on the old kernel. Userspace: GStreamer 1.28 has no VC-1/MPEG-4/H.263/Spark/AVS2 elements, so these need the
Jernej FFmpeg fork (`v4l2request-mpeg4`) that `harness/research/vdec-perf/build-ffmpeg.sh` already builds statically.

### 2.4.2 Video encoding

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| H.264 BP/MP/HP | supported | no driver (encoder RE: `harness/research/ve-encoder/`) | no | GAP | tracked |
| I/P frames, single reference | supported | — | no | GAP | add to the encoder acceptance (`ve-encoder/SPEC.md`) |
| MJPEG / JPEG baseline | supported | no driver | no | GAP | JPEG snapshot tracked. **MJPEG stream** not tracked → W22 |
| 4096×4096 max H.264 | 16 MP | — | no | GAP | W22 (SPEC.md lists only 4K@25) |
| H.264 4K@25 | supported | — | no | GAP | tracked |
| JPEG 1080p@60 snapshot | supported | — | no | GAP | tracked |
| CBR/VBR, 256 kbit/s–100 Mbit/s | supported | — | no | GAP | W22 |
| 8 ROI regions | supported | — | no | GAP | W22 (V4L2 has no ROI control. Needs a uAPI) |

## 2.5 Video and graphics

### 2.5.1 Display engine (DE33)

Our DE33 is the regmap-based Armbian `patches.drm/0032–0048` (Jernej) + TVE YUV patch. The LibreELEC 0200–0285 gap analysis is in
`harness/research/vdec-perf/de33-afbc-plan.md`. AFBC Stage A is in progress in `wt-de33`.

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| Output up to 4096×2048 | supported | sun4i-drm DE33 mixer0/1 bound. dw-hdmi allows 594 MHz | no display yet | OK\* | tracked (HDMI 4K@60) |
| 6 alpha-blending channels, 4 overlay layers each | supported | sun50i_planes exposes the VI/UI planes; per-channel layers not all exposed | no | OK\* | W11 (plane count check with `modetest -p` on a display) |
| Independent scaler per channel | supported | **`sun50i_planes.c` `.scaler_mask = 0`** (TODO), so there is no DE33 scaling and VI planes get the no-YUV format list | no | **GAP** | in the DE33 plan (LE 0214–0220, 0231). Make sure `wt-de33` Stage A covers it |
| Porter-Duff blending | supported | pixel blend mode property (cleanup patch) | no | OK\* | W11 |
| AFBC buffers | supported | missing (LE 0246–0250) | no | GAP | in progress `wt-de33` (implied by the spec-checklist 4K60 decode rows) |
| Keystone correction | supported | none (no driver anywhere) | no | GAP | W23 |
| Input formats: semi-planar/planar YUV422/420/411, **P010/P210**, ARGB8888…RGB565 | supported | RGB formats on UI planes. **YUV not exposed on H616 VI planes** (no scaler). P010/P210 missing | no | PARTIAL | DE33 plan (scaler chain + LE 0233/0241). P010/P210 → W12 |
| 3D: frame packing / top-bottom / side-by-side | supported | no stereo-mode handling in sun4i-drm/dw-hdmi glue | no | GAP | W24 |
| 10-bit processing path for HDR | supported | missing (LE 0256–0285: bus format, formatter, 10-bit RGB/YUV out) | no | GAP | **W12** (DE33 plan Stage B) |
| SDR/HDR10/HLG EOTF + colour-space conversion | supported | CSC for BT.601/709 RGB↔YUV only. No EOTF/HDR metadata path in the mixer | no | GAP | W12 |
| SmartColor 3.3 (detail/edge, colour, contrast, de-noise) | supported | none (vendor `disp2` only) | no | GAP | W23 |
| Write-back (dual display, Miracast) | supported | missing (`sun50i_wb.c`, LE 0235–0238) | no | GAP | W23 |
| Output YUV444/422/420/RGB444, 10/8-bit | supported | RGB 8-bit to HDMI. YUV out only for TVE (our patch). 4:2:0/4:2:2/10-bit missing | no | PARTIAL | W12 |
| Register Configuration Queue (RCQ) | supported | missing (LE 0223–0230. Deliberately skipped in the DE33 plan) | no | GAP | W23 (only needed if regmap latching fails, plan §risks) |

### 2.5.2 De-interlacer (DI)

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| Offline m2m de-interlace, 8-bit NV12/NV21/YV12/YUV422 in/out, 32×32–2048×1280, weave/motion-adaptive, TNR, film-mode detection, 1080p60 @150 MHz | supported | **no DT node, no driver for H616**. `CONFIG_VIDEO_SUN8I_DEINTERLACE=y` matches only `allwinner,sun8i-h3-deinterlace` (other IP). Jernej `jernejsk/linux-1` branch `h616-deinterlace-v1` (DI300) exists, unposted. Vendor 5.4 `drivers/char/sunxi-di/drv_div3x/` | no | **GAP** | **W13**: pull Jernej's `h616-deinterlace-v1`, add the DT node (`iommus = <&iommu 1>`), test with GStreamer `v4l2convert`/FFmpeg `deinterlace_v4l2m2m` |

### 2.5.3 Graphic 2D (G2D)

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| 2048×2048 layers, YUV/P010/P210/P410/Y8/RGB formats, flip, 0/90/180/270 rotation | supported | **none**: no mainline or community driver, no DT node. Vendor 5.4 `drivers/char/sunxi_g2d/` (`g2d@1480000`, SPI 90, IOMMU master 6). `CONFIG_VIDEO_SUN8I_ROTATE=y` is the A83T rotator (different IP, no H616 node) | no | **GAP** | **W25**: clean-room V4L2 m2m (rotate/scale/CSC) driver from the vendor GPL source |

## 2.6 System peripherals

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| Timer0/Timer1 (32-bit down, 8 prescalers) | supported | `timer@3009000`, sun4i-timer (`CONFIG_SUN4I_TIMER=y`). Clockevent `sun4i_tick`, clocksource `timer` | yes (registered) | OK | — |
| Watchdog | 12 timeouts, IRQ, reset | sunxi-wdt 16 s, systemd watchdog | yes | OK | — |
| AVS0/AVS1 33-bit A/V sync counters | supported | no Linux driver anywhere | no | GAP | W26 (low value: expose as a clocksource/counter device or document) |
| High-speed timer (56-bit) | supported | `hstimer@3005000` in the DTSI, but **`CONFIG_SUN5I_HSTIMER` is not set**: the symbol is `bool … if COMPILE_TEST` and only arm32 `ARCH_SUNXI` selects it. Not in `available_clocksource` (`arch_sys_counter timer`) | yes (absent) | **GAP** | **W3**: select `SUN5I_HSTIMER` for arm64 sunxi (Kconfig patch), check `available_clocksource` lists `hstimer` |
| RTC (day/h/m/s counters) | supported | sun6i-rtc `rtc0`. No backup battery on the Zero2 | yes | OK | — |
| RTC: 32.768 kHz from HOSC-calibrated RC | supported | sun6i-rtc-ccu handles the internal/external osc32k | no (which source is in use was not read) | OK\* | W14 (read `clk_summary` osc32k parent) |
| RTC alarm wake-up | supported | rtcwake | yes: 100/100 suspend cycles | OK | — |
| RTC 16 general-purpose registers | supported | not exposed (U-Boot/TF-A may use them) | no | OK\* (no user interface needed) | — |
| GIC-400 (16 SGI, 16 PPI, 160 SPI) | supported | `interrupt-controller@3021000` | yes | OK | — |
| DMA (16 ch, 8–64-bit, LLI, pause) | supported | sun6i-dma (`dma-sun6i-dma-add-sun50i-h616-support.patch`) bound to `3002000.dma-controller` | yes (bound, used by SPI/audio) | OK | — |
| CCU: 12 PLLs, RC osc + 24 MHz DCXO, gating/reset | supported | ccu-sun50i-h616 | yes | OK | — |
| Thermal: 4 sensors (GPU, VE, CPU, DDR) | supported | sun8i-thermal, 4 zones | yes: `gpu/ve/cpu/ddr-thermal` read | OK | — |
| Thermal: ±3 °C accuracy, averaging | supported | calibration from SID | no (accuracy not measured) | OK\* | W14 (compare with an IR thermometer, optional) |
| Thermal: over-temperature alarm / shutdown interrupts | supported | sun8i-thermal uses only the data IRQ. Trips are software (passive 85, critical 110) | no | PARTIAL | W14 (low: the HW alarm IRQ is unused, software trips cover it) |
| CPU configuration (core reset, status, debug) | supported | PSCI hotplug, cpuidle via TF-A | yes | OK | — |
| IOMMU: hardware VA→PA | supported | sun50i-iommu `30f0000.iommu` (+ our page-size and sibling-reset patches) | yes | OK | — |
| IOMMU masters DE, DI, VE_R, VE, G2D (parallel, bypass, prefetch, per-master IRQ) | supported | **only the VE uses it** (`iommus = <&iommu 3>, <&iommu 2>`, group 0 = `1c0e000.video-codec`). DE33 nodes have no `iommus` (LE 0702 adds `<&iommu 0>` on `planes@100000`). DI and G2D have no nodes | yes (`/sys/kernel/iommu_groups`) | PARTIAL | DE master in the DE33 plan (zero-copy AFBC). DI master with W13. G2D master with W25 |
| IOMMU 2-level TLB, PTW on miss, permission check | supported | used by the driver | yes (VE perf counters, impl-vdec-main10-perf §1) | OK | — |

## 2.7 Video output

### 2.7.1 TVE

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| 1-ch CVBS, NTSC and PAL | supported | our `sun8i_tve` (DRM TVDAC), `tv-encoder@6524000` (disabled until the `orangepi-zero2-expansion` overlay), `CONFIG_DRM_SUN8I_TVE=y` | no (needs a TV + 13-pin board) | OK\* | tracked |
| Plug status auto-detect | supported | **not implemented**: the connector always reports connected (impl-audio-tve §2 item 5) | no | **GAP** | **W15**: DAC load-detect polling as in the BSP |

### 2.7.2 HDMI

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| HDCP 1.4 / HDCP 2.2 | supported | **none**: dw-hdmi has only the HDCP bypass config, no HDCP 1.4 auth and no HDCP 2.2 (needs the ESM firmware + keys). Vendor 5.4 has `HDCP/HDCP22` | no | **GAP** | W28 (likely blocked: needs Allwinner key provisioning) |
| DDC and SCDC (scrambling) | supported | dw-hdmi I2C master + SCDC | no display | OK\* | tracked (4K@60 row) |
| CEC engine | supported | `dw_hdmi_cec` loaded, `/dev/cec0` | partly (device present) | OK\* | tracked |
| 2D modes 480i…4K, up to 4K@60 | supported | dw-hdmi up to 594 MHz | no display | OK\* | tracked |
| 3D video up to 4K@30 | supported | no stereo-mode support in the glue | no | GAP | W24 |
| RGB888 / YUV444 / YUV422 output | supported | RGB only (the bus-format negotiation patches are missing) | no | PARTIAL | W12 |
| 8/10-bit colour depth | supported | 8-bit only | no | PARTIAL | W12 |
| HDR10 (CTA-861.3 / ST 2084 metadata) | supported | the dw-hdmi `hdr_output_metadata` infoframe exists in the core, but without a 10-bit DE path it is unusable | no | GAP | W12 |
| L-PCM up to 192 kHz | supported | vendor AHUB `ahub1` → HDMI card `HDMI` | no display | OK\* | tracked |
| IEC 61937 compressed passthrough | supported | vendor AHUB. Passthrough (non-audio bit, IEC958 controls) not checked | no | OK\* (unconfirmed) | W16 (AVR + `iec958` / `speaker-test -D hdmi:…,AES0=0x06`) |

## 2.8 Audio subsystem

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| Audio codec: 2 DAC channels, 8–192 kHz | supported | mainline sun4i-codec `allwinner,sun50i-h616-codec`, card `Codec` | no (needs the 13-pin board) | OK\* | tracked |
| Codec 16- and 20-bit samples | supported | `sun4i_codec_dai`: S16_LE and S32_LE with `sig_bits = 24`, so 20-bit audio fits the 32-bit container | no | OK\* | tracked (line-out row). Play a 24/32-bit file at 192 kHz in the same test |
| LINEOUT differential / single-ended | supported | single-ended LINEOUTL/R on the 13-pin header (sch.: LINEOUTL G19, LINEOUTR G20) | no | OK\* | tracked |
| Dynamic Range Controller (DRC) | supported | **no control** in sun4i-codec for H616 | no | GAP | W17 |
| 128×24 FIFO, thresholds, DMA/IRQ | supported | used by the driver | — | OK\* | — |
| Audio HUB: 2 DAMs | supported | vendor `sunxi_v2` AHUB. `ahub_dam_plat@5097000` bound, `ahub_dam_mach` disabled | no | OK\* | W18 |
| AHUB: 3 external I2S/PCM + 1 to HDMI | supported | only the HDMI I2S (`ahub1`) is wired up. **External:** I2S0 = PI0–PI4 (RGMII) → N/A. I2S2 = PG10–PG14 (WiFi/BT bank, 32 kHz clock to the module) → N/A (unconfirmed per pin). **I2S3 = PH5–PH9, reachable on the 26-pin header** (shared with SPI1/TWI3), no overlay | no | PARTIAL | **W18**: `ahub` I2S3 overlay for the header + a test with an I2S DAC/loopback |
| LJ/RJ/I2S/PCM/TDM, 8 ch 192 kHz, 16 ch 96 kHz | supported | vendor AHUB driver supports the formats | no | OK\* | W18 |
| DMIC (8 PDM mics, 8–48 kHz) | supported | `CONFIG_SND_SUN50I_DMIC=y` matches only `sun50i-h6-dmic`. No H616 node | — | N/A: DMIC_CLK/DATA0–3 exist only on PI0–PI4 (§4.3), which are RGMII on the Zero2 | — |
| OWA (S/PDIF) TX, IEC 60958, 16/20/24-bit | supported | `spdif@5093000` (`sun50i-h616-spdif`, sun4i-spdif) disabled. `spdif_tx_pin` = **PH4, which reaches the 26-pin header** (TWI3-SCK net) | no | OK\* (no overlay) | **W19**: `spdif-ph4` overlay + simple-audio-card, test with an optical/coax transmitter or a logic analyser |

## 2.9 Security engine

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| AES ECB/CBC (128/192/256), DES/TDES ECB/CBC | supported | sun8i-ce `ce_h616_variant`: `CE_OP_ECB, CE_OP_CBC` | yes: `ecb/cbc-aes-sun8i-ce`, `ecb/cbc-des3-sun8i-ce` in `/proc/crypto` | OK | — |
| AES CTS/CTR/CFB/OFB/CBC-MAC, DES CTR/CBC-MAC, XTS 256/512 | supported | **not in the H616 variant** (`op_mode` has only ECB/CBC). The driver has no XTS/CTR code paths for any variant | yes (absent) | **GAP** | W29 |
| MD5, SHA1/224/256/384/512 (HW padding) | supported | sun8i-ce hash | yes: `md5/sha1/sha224/sha256/sha384/sha512-sun8i-ce` | OK | — |
| HMAC-SHA1/256 | supported | no HMAC in sun8i-ce | yes (absent) | GAP | W29 |
| RSA 512–4096, ECC 160–521 | supported | no asymmetric support in sun8i-ce | yes (absent) | GAP | W29 |
| 160-bit PRNG | supported | **`ce_h616_variant` sets no `.prng`** (the H6 variant has `CE_ALG_PRNG_V2`). `CONFIG_CRYPTO_DEV_SUN8I_CE_PRNG` not set | yes: no `*-sun8i-ce` rng in `/proc/crypto` | **GAP** | **W4**: add `.prng = CE_ALG_PRNG_V2`, enable the config, test via AF_ALG rng |
| 256-bit TRNG | supported | `CE_ALG_TRNG_V2`, `/dev/hwrng` | yes: `rng_current = sun8i Crypto Engine TRNG` | OK | — |
| Internal DMA, task chains, 8 SG, secure/non-secure interfaces | supported | used by the driver (non-secure interface) | yes (implied) | OK | — |
| Security ID: eFuse chip ID, secure/non-secure zones | supported | sunxi-sid nvmem `sunxi-sid0` (speed bin, THS cal) | yes | OK (non-secure zone) | — |
| SMC (secure DRAM areas, DRM areas) | secure-only | TF-A configures it. Linux has no access by design | — | N/A (secure world) | — |
| SPC (secure property of peripherals) | secure-only | TF-A | — | N/A (secure world) | — |

## 2.10 External peripherals

### 2.10.1 USB

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| USB0 OTG: host HS/FS/LS (EHCI/OHCI) | supported | musb + `sun50i-h616-usb-otg-host` overlay (ehci0/ohci0) | no | OK\* | tracked in status.md (USB-C). Not a spec-checklist row → W9 |
| USB0 OTG: device HS/FS, 8 EPs | supported | musb `dr_mode = "peripheral"` | no (power-only cable) | OK\* | **W9**: gadget (ECM/ACM) with a data cable |
| USB1–3 host EHCI/OHCI HS/FS/LS | supported | ehci1-3/ohci1-3 okay (USB1 on-board A port, USB2/3 on the 13-pin header per sch.) | controllers up, no device yet | OK\* | tracked |
| USB2 standby (wake) | "Only USB2 supports USB standby" | no wakeup source configured | no | OK\* (unconfirmed) | W30 (USB-keyboard wake from suspend on the 13-pin USB2 port) |

### 2.10.2 EMAC

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| EMAC0 10/100/1000, RGMII/RMII, MDIO | supported | dwmac-sun8i, RTL8211F, `rgmii-rxid` | yes: 1000 Mbit/s, iperf3 ~870–910 Mbit/s | PARTIAL | tracked (10/100 + soak) |
| EMAC1 10/100 with embedded EPHY | supported | `ethernet@5030000` disabled. AC300 PHY driver in config | — | N/A: the Zero2 has one RJ45, wired to the RTL8211F (sch. block "RTL8211F"). EPHY_TXP/N/RXP/N balls (A19–B21) appear only on the SoC symbol page. The text dump cannot prove they are unconnected → **unconfirmed** (prprep-emac1.md agrees: no EMAC1 on the Zero2) | — |
| Full/half duplex, filters, descriptor DMA, FIFOs | supported | stmmac | full duplex yes | OK\* (half duplex untested) | W31 (forced 10/100 half duplex, with the tracked 10/100 test) |
| Jumbo frames up to 16 KB | supported | stmmac max MTU for this variant not checked | no | OK\* | W31 (`ip link set end0 mtu 9000` + ping -s against the host) |

### 2.10.3 UART

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| UART0 (2-wire) debug | supported | 8250_dw `serial@5000000` | yes | OK | — |
| UART1 4-wire (BT, flow control) | supported | UWE5622 BT over UART1 with RTS/CTS | yes (hci0 up, scan) | OK | — |
| UART2–UART5 | supported | overlays (`uart2-ph`, `uart5`, …). UART5 on the header (PH2/PH3), UART2 on PH5–PH8 (header, shared with SPI1). UART3/4 only on PI (RGMII) → N/A | no | OK\* | tracked (26-pin header row) |
| 16550, 5–8 bits, 1/1.5/2 stop, parity, DMA, HW/SW flow control | supported | 8250_dw (the H616 FIFO-config series v5 is pending upstream) | no | OK\* | tracked (header loopback) |
| Up to 4 Mbit/s | supported | 8250_dw | no | OK\* | W32 (UART5↔UART2 loopback at 3/4 Mbit/s) |
| IrDA 1.0 SIR | supported | **no IrDA in 8250_dw/serial core** | no | GAP | W32 (low) |
| RS-485 / 9-bit mode | supported | 8250_dw has RS-485 (software RTS), 9-bit mode is DW-specific | no | OK\* | W32 |

### 2.10.4 SPI

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| SPI0 (NOR flash) | supported | spi-sun6i `sun8i-h3-spi` fallback, `jedec,spi-nor` 40 MHz, `mtd0` 2 MB | yes | OK | tracked |
| SPI1 on the 26-pin header | supported | overlays `spidev1_*` | no | OK\* | tracked |
| Master mode, modes 0–3, CS/CLK polarity, 64-byte FIFOs, IRQ/DMA, 3/4-wire, 1–32-bit frames | supported | spi-sun6i | partly (SPI0) | OK\* | tracked |
| Slave mode | supported | **no target mode in spi-sun6i** | no | GAP | W33 |
| Dual/Quad I/O | supported | **H616 matches `sun8i-h3-spi`, whose cfg has no `mode_bits`**. DUAL/QUAD are only on `sun50i-r329-spi`/A523 | no | GAP | **W5**: check whether the H616 has the R329 bit (UM SPI_BCC DRM bit). If yes, add an H616 cfg with DUAL (quad needs PC15/PC16 WP/HOLD: PC16 is the USB1 VBUS switch, so quad is N/A on SPI0) |

### 2.10.5 TWI

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| TWI0–TWI4 master, 100/400 kHz, repeated START, arbitration | supported | i2c-mv64xxx, nodes disabled + overlays. Header has TWI3 (PH4/PH5) and TWI2/TWI1/TWI4 alternatives on the PH header pins. TWI0 (PI5/6) and TWI1-on-PI are RGMII → N/A | no | OK\* | tracked (26-pin header row) |
| S_TWI0 | supported | `i2c@7081400` disabled | — | N/A: PL0/PL1 carry RSB to the AXP305 (`r_rsb` okay) | — |
| Slave mode, own address/general call | supported | **i2c-mv64xxx has no slave support** | no | GAP | W33 |
| 10-bit addressing | supported | i2c-mv64xxx supports 10-bit in master mode | no | OK\* | — |
| DMA in master mode | supported | mv64xxx has no DMA path | no | GAP | W33 (low value) |

### 2.10.6 CIR receiver

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| NEC IR receiver, 64×8 FIFO, ≤1 MHz sampling | supported | sunxi-cir (`sun6i-a31-ir` fallback), `ir@7040000` (enabled by the expansion overlay), IR-RX on the 13-pin header | no | OK\* | tracked (IR row) |

### 2.10.7 PWM

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| PWM1–4, output 0–24/100 MHz, 0–100 % duty, 1/65536 | supported | vendor `pwm-sunxi-enhance` (Armbian), overlays PH2/PH3 (header pins). PWM3/4 on PH0/PH1 = debug UART. PI variants = RGMII | no | OK\* | tracked (header row) |
| PWM23 pair: complementary output, dead-time | supported | vendor driver has `dead_time`/bind | no | OK\* | W34 (PH2+PH3 complementary pair on a scope/logic analyser) |
| Capture input + IRQ | supported | no capture in `pwm-sunxi-enhance` (mainline v10 series to check) | no | GAP | W34 |

### 2.10.8 LRADC

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| 1 channel, 6-bit, 2 kHz, key modes | supported | `lradc@5070800` (`sun50i-h616-lradc`) disabled, `KEYBOARD_SUN4I_LRADC=m`, overlay `sun50i-h616-keys` | — | N/A (unconfirmed): the LRADC ball (L18) shows up only on the SoC symbol. No key net or header pin for it in the schematic text, and the board has no keys | confirm from the PDF schematic image (sheet 5/6) |

### 2.10.9 TSC

| Feature | Datasheet claim | Driver/DT state | Verified? | Status | Next step |
|---|---|---|---|---|---|
| SPI/SSI TS input, 32 PID filters, 188/192/204, PCR, TSG, DVB-CSA 1.1/2.1 | supported | no driver, no DT node | — | N/A: TS0_* exist only on PI5–PI16 (§4.3), which are all RGMII on the Zero2 | — |

## 2.11 Package

| Feature | Datasheet claim | Status |
|---|---|---|
| TFBGA284, 0.65 mm pitch, 14×12 mm | mechanical | N/A |

## Status counts

Counted over the rows above (the decode table counts one row per datasheet format; the "4K@60 general" row is included):

| Status | Rows |
|---|---|
| OK | 32 |
| OK\* | 45 |
| PARTIAL | 15 |
| GAP | 40 |
| N/A | 16 |
| **Total** | **148** |

## New work items (not tracked in docs/spec-checklist.md), ranked by size

Size: **S** ≤ 1 day · **M** a few days · **L** 1–3 weeks · **XL** more than a month or blocked on outside work. The W numbers are
referenced from the tables above.

| # | Size | Item | Rows |
|---|---|---|---|
| W1 (S part) | S | Vulkan: document that panvk on G31 needs `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` and reports 1.0 non-conformant. Decide whether to set it image-wide | 2.2 |
| W3 | S | Select `SUN5I_HSTIMER` on arm64 sunxi so the 56-bit high-speed timer registers | 2.6 |
| W4 | S | CE PRNG on H616 (`.prng = CE_ALG_PRNG_V2` + `CONFIG_CRYPTO_DEV_SUN8I_CE_PRNG`) | 2.9 |
| W6 | S | `CONFIG_COMPAT=y` (AArch32 execution state) | 2.1 |
| W9 | S | USB-C data cable: FEL (`sunxi-fel`), musb gadget, OTG host overlay | 2.3.1, 2.10.1 |
| W19 | S | S/PDIF (OWA) TX overlay on PH4 (26-pin header) + test | 2.8 |
| W10 | S | SDIO UHS (SDR104/DDR50) for the UWE5622 on SMHC1 | 2.3.4 |
| W17 | S | Codec: DRC controls for the H616 DAC | 2.8 |
| W31 | S | EMAC0 jumbo frames + half duplex (with the tracked 10/100 test) | 2.10.2 |
| W32 | S | UART 4 Mbit/s and RS-485 loopback tests. IrDA = document as unsupported in Linux | 2.10.3 |
| W14 | S | RTC osc32k source, thermal accuracy and HW alarm IRQ (low value) | 2.6 |
| W16 | S | HDMI IEC 61937 passthrough test (needs an AVR) | 2.7.2 |
| W11 | S | DE33 plane/channel count and Porter-Duff check on a display | 2.5.1 |
| W5 | S–M | SPI dual I/O for the H616 (check the register, add a cfg) | 2.10.4 |
| **W2** | **M** | **Decode conformance for the formats without evidence**: MPEG-1, MPEG-2 (incl. field pictures), MPEG-4 SP/ASP, Xvid, H.263, Sorenson Spark, VC-1 SP/MP/AP (WMV9), VP8. Bit-exact md5 against FFmpeg software + 1080p@60 fps, using the existing static Jernej FFmpeg build and fluster where suites exist | 2.4.1 |
| W15 | M | TVE plug detection (DAC load detect) | 2.7.1 |
| W18 | M | AHUB I2S3 on the 26-pin header (overlay + test). Enable the DAM path | 2.8 |
| W30 | M | USB2 standby wake-up from suspend | 2.10.1 |
| W34 | M | PWM complementary/dead-time test. Capture input (vendor driver lacks it; check mainline v10) | 2.10.7 |
| W33 | M | SPI slave and I2C slave modes (driver work in spi-sun6i / i2c-mv64xxx) | 2.10.4, 2.10.5 |
| W22 | M | Extend `ve-encoder/SPEC.md` acceptance: MJPEG streams, 4096×4096, CBR/VBR 256k–100M, I/P single ref, 8 ROIs (needs a uAPI) | 2.4.2 |
| W26 | M | AVS0/AVS1 counters: expose them or document them as unused (low value) | 2.6 |
| W13 | L | De-interlacer (DI300): Jernej `h616-deinterlace-v1` + DT node + IOMMU master 1 + tests (weave/motion-adaptive, TNR, film mode) | 2.5.2 |
| W12 | L | DE33 10-bit/HDR path: P010/P210 planes, YUV 4:4:4/4:2:2/4:2:0 and 10-bit HDMI, HDR10/HLG metadata (LE 0256–0285, DE33 plan Stage B) | 2.5.1, 2.7.2 |
| W20 | L | AVS/AVS+ JiZhun decode (new stateless uAPI, H.264 engine mode 1, RE from vendor lib) | 2.4.1 |
| W21 | L | VE JPEG decode (VE+0xE00), 45 MPPS | 2.4.1 |
| W24 | L | HDMI/DE 3D formats (frame packing, top-bottom, SbS) | 2.5.1, 2.7.2 |
| W29 | L | CE: CTR/CTS/CFB/OFB/CBC-MAC/XTS, HMAC, RSA/ECC (sun8i-ce has none of these for any variant) | 2.9 |
| W1 (full) | XL | Vulkan 1.1 on Bifrost G31 (panvk JM work) or the Arm DDK route | 2.2 |
| W25 | XL | G2D driver (clean-room V4L2 m2m from the vendor GPL source) | 2.5.3 |
| W23 | XL | DE33 keystone, SmartColor 3.3, write-back, RCQ (no open code anywhere except LE write-back/RCQ) | 2.5.1 |
| W28 | XL / blocked | HDCP 1.4/2.2 (needs key provisioning + ESM firmware) | 2.7.2 |
| W27 | decision | Secure boot (irreversible eFuse burn) | 2.3.1 |

Already tracked elsewhere and therefore not listed: GLES 1.0/3.2, OpenCL 2.0, HEVC/VP9/AVS2/H.264 rows, H.264 4K@25 and
JPEG-snapshot encode, AFBC scanout (DE33 Stage A), HDMI 4K@60/audio/CEC, CVBS, line-out, USB host + USB boot, header
I2C/SPI/UART/GPIO/PWM, IR, Ethernet 10/100.
