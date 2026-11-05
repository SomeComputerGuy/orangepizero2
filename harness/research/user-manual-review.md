# H616 User Manual review against our code (status.md item 7)

Date: 2026-11-05. Source: *H616 User Manual Revision 1.0* (Allwinner, 2019-12-28, 831 pp.),
`docs/vendor/H616_User_Manual_V1.0.pdf` (git-ignored, Allwinner copyright; claims below are paraphrased, page = printed
page number = PDF page). Text dump for the review: `kernel-check/scratch/um/um-pg.txt` (git-ignored, each line prefixed
with its page).

Code reviewed: armbian-build `stonking-orangepizero2` 8546e5fc1 (kernel `patch/kernel/archive/sunxi-7.3`, 811 patches,
patched tree `kernel-check/work-umreview/linux-7.3.1`), U-Boot v2026.10 + `patch/u-boot/v2026.10-sunxi64`
(tree `kernel-check/work-uboot/u-boot`), TF-A lts-v2.14.11 + `patch/atf/atf-sunxi64`, `docs/datasheet-checklist.md`,
`harness/research/impl-emac-jumbo.md`, `impl-small-gaps.md`, `impl-audio-tve.md`. Worktree: `wt-umreview`.
Method: register offsets, bit fields, parents/dividers and limits used by the code compared with the register
descriptions; all DTSI `reg`/`interrupts`/`dmas` compared with the memory map (§3.1), the GIC table (§3.8) and the DMA
DRQ table (§3.9). CCU, U-Boot, TF-A, memory map/GIC by the main review; A/V+DMA, EMAC/IOMMU/thermal/RTC/timers/CE/SID and
TWI/UART/SPI/PWM/LRADC/CIR/PIO in three parallel passes, findings re-read before the fixes were made.

## Summary of defects and branches

All branches are on `stonking-orangepizero2` b9df5096b (rebased; patch files carry `Assisted-by: LLM`), one commit each, **not merged, not pushed**. They were
build-checked together (local branch `test/um-review-all` = all nine merged, see "Build check").

| # | Defect | Manual | Effect today | Branch | Commit |
|---|---|---|---|---|---|
| 1 | CCU `emac-25m` parent is ahb3 with no /24 | §3.3.5.86 p.104 | clk_summary reports 200 MHz for the 25 MHz EPHY clock (AC300/EMAC1 boards); wrong clock-tree dependency | `fix/sunxi-h616-ccu-emac-25m` | 738b17d79 |
| 2 | IOMMU master 6 (G2D) not handled (flush, prefetch, IRQ, reset, permissions use masters 0-5) | §3.12.3 table 3-8 p.207, per-master regs default 0x7F | latent (no G2D node); blocks W25 | `fix/sunxi-h616-iommu-g2d-master` | 4653460cb |
| 3 | 8250_dw probes DW DLF/RE_EN at 0xc0/0xb4, which are RS485_CTL/DBG_DLH on the H616 | §9.2.6.18-20 p.620 | divisor truncated (153600 baud +8.5 %, 76800 +2.8 %); TIOCSRS485 "succeeds" but does nothing; fraction bits written into RS485_CTL | `fix/sunxi-h616-uart-dw-ext-regs` | 1111c84ee |
| 4 | TWI CLK_DUTY (TWI_CCR bit 7, reset 1 = 40 %) cleared by i2c-mv64xxx | §9.1.6.6 p.587 | 400 kHz: tLOW 1.25 µs < 1.3 µs fast-mode minimum (header I2C only) | `fix/sunxi-h616-twi-fast-mode-duty` | 863ecfb92 |
| 5 | SPI_TCR SDM/SDC sample mode never programmed on H616 (only for parts without clock control) | §9.3.6.2 p.636 | always half-cycle-delayed sampling; wrong at ≤24 MHz and ≥80 MHz (NOR at 40 MHz unaffected) | `fix/sunxi-h616-spi-sample-mode` | 5b15a201b |
| 6 | pwm-sunxi-enhance: bound-pair DIV_M width 0 (never cleared), PRESCAL_K loop allows 256 (8-bit field), bypass bit never cleared | §9.9.6 pp.788-799 | wrong div after reconfiguration; ~0.7 s periods 256x too short; stuck raw-clock output | `fix/sunxi-h616-pwm-enhance-regs` | a6224709e |
| 7 | S/PDIF module clock lacks CLK_SET_RATE_PARENT | §8.3 table 8-6 p.527, TX_CFIG p.532; §3.3.5.91 | S/PDIF alone (spdif-out overlay) runs at a wrong rate (~24 kHz for 48 kHz from the reset PLL) unless codec/AHUB retuned pll-audio first | `fix/sunxi-h616-spdif-clk-rate` | e11e400f6 |
| 8 | Codec node `reg` size 0x31c, RAMP_REG is at 0x31c | §8.4.6.56 p.566 | works only because ioremap rounds to a page | `fix/sunxi-h616-codec-reg-size` | ca6e35a59 |
| 9 | dwmac-sun8i RX_TH 32/64 encoding swapped (00 = 64, 01 = 32) | §6.5.10 p.409 | none (RX threshold mode is never used with RX csum offload); generic dwmac-sun8i, other SoCs share the IP | `fix/sunxi-dwmac-sun8i-rx-th` | f8773fb2a |

Patch files (in `patch/kernel/archive/sunxi-7.3/patches.armbian/`, each inserted in `series.conf` next to the related
patch so the branches merge without conflicts): `clk-sunxi-ng-h616-fix-the-emac-25m-clock-parent-and-divider.patch`,
`iommu-sun50i-handle-the-h616-g2d-master.patch`, `serial-8250_dw-do-not-probe-dw-dlf-and-rs485-on-h616.patch` (driver
quirk + `allwinner,sun50i-h616-uart` in the six UART nodes + binding enum), `i2c-mv64xxx-use-40-percent-duty-on-v536-in-fast-mode.patch`,
`spi-sun6i-program-the-sample-mode-on-the-h616.patch`, `pwm-sunxi-enhance-fix-div-m-prescaler-and-bypass.patch`,
`clk-sunxi-ng-h616-let-the-spdif-clock-set-the-pll-rate.patch`, `arm64-dts-sun50i-h616-cover-the-codec-ramp-register.patch`,
`net-stmmac-dwmac-sun8i-fix-the-rx-threshold-encoding.patch`.

Not branched (comment/doc only): `sun8i_tve.c` comment says the "new detect mode" bit is undocumented; it is
TVE_030 bit 31 DAC_AUTO_DETECT_MODE_SEL (§7.2, p.448). Upstream-only pinctrl issue (PIO_POW_MOD_SEL bit 12, below).

## Chapter by chapter

### 3.1 Memory map (pp.30-32), 3.8 GIC (pp.159-163)
- Every `reg` in `sun50i-h616.dtsi` matches the memory map. Every `GIC_SPI n` matches the GIC table (ID - 32):
  UART0-5 0-5, TWI0-4 6-10, SPI0/1 12/13, EMAC0/1 14/15, THS 19, LRADC 20, OWA 21, OTG/EHCI/OHCI 25-33, NAND 34, SMHC
  35-37, DMA 42, GPIOE 43, HSTIMER 45/46, TIMER 48/49, WDOG 50, GPIOC/F/G/H/I 52/54-57, IOMMU 61, HDMI 63, TCON_TV0/1
  66/67, DI 89, CE_NS 91, VE 93, GPU job/mmu/gpu 95-97, NMI 103, R_Alarm0 104, S_TWI0 105, CIR 106. **OK.**
- Not in the manual (harmless, all disabled or internal): `adc@5070000` (GPADC, SPI 18) and CCU 0x9EC, `tcon_lcd0/1`
  at 0x6511000/0x6512000 (SPI 64/65) and CCU 0xB60/0xB64/0xB7C/0xBAC, PIO IRQs 51/53 (banks A/D, "/" in the table),
  R_RSB SPI 109. These are T507/H618-family blocks; doc-only.
- Unused interrupts: TVE SPI 68 (driver polls), AHUB SPI 24 (vendor driver has none), DMIC SPI 22 (no node),
  GPU_EVENT SPI 94, PWM SPI 16 (capture, W34).

### 3.2 CPUX configuration (pp.33-44) — TF-A
- TF-A `sunxi_cpucfg_ncat.h` uses C0_CTRL_REG0 (0x09010000 + 0x10) bits 27:24 AA64nAA32 and RVBAR 0x40-0x5C: match
  §3.2.5.2/§3.2.5.6. **OK.**
- Our CPU_SUSPEND/SYSTEM_SUSPEND patches also use R_CPUCFG 0x07000400 + 0x100..0x110 (CPUIDLE enable/pend/wake/
  status), the PRCM and the DRAM controller (MCTL_STATR/PWRCTL/SWCTL). **None of these are described in the manual**
  (no R_CPUCFG, R_PRCM or DRAMC register chapter): cannot be verified from it; they are verified on the board
  (100/100 suspend cycles).

### 3.3 CCU (pp.45-124)
- PLL limits: every PLL has N = FACTOR_N + 1 with FACTOR_N ≥ 11 (N ≥ 12); the driver uses `_SUNXI_CCU_MULT_MIN(8, 8, 12)`
  everywhere. PLL_CPUX 200 MHz-3 GHz, P only below 288 MHz (driver forces P = 1, U-Boot clamps to ≥288 MHz).
  PLL_AUDIO: 7.5 ≤ N/M0/M1 ≤ 125 and 180 MHz-3 GHz VCO; the two SDM table entries (N 22/40, M0 = 2) are inside.
  The probe sets LOCK_ENABLE (bit 29) and OUTPUT_ENABLE (bit 27) on all PLLs as §3.3.3 requires. **OK.**
- Parents/dividers checked register by register (0x500-0xC4C) against the driver: CPUX/PSI/AHB3/APB1/APB2 muxes
  (RC16M = `iosc`), MBUS, DE/DI/G2D, GPU0/GPU1 (PLL_PERI_BAK = PERI0(2X)/M, probe M = 3 → 400 MHz), CE, VE (3-bit M),
  DRAM, NAND/SPI (5 parents), SMHC (3 parents, mainline's extra /2 post-divider is the known new-timing-mode
  modelling), OWA/DMIC/AHUB (pow-2 N at 9:8), codec 1X/4X (4-bit M), USB0-3 (OHCI 12M source forced to 00), HDMI
  (video0/video0-4x/video2/video2-4x), HDMI slow, CEC (32K or PERI0(2X)/36621), TCON_TV0/1 + TVE0 (video0/1 ×1/×4, M+N),
  HDCP (PERI0/PERI1 1X), resets at bit 16+ and USB PHY resets at bit 30. **OK except:**
  - **Defect 1 (fixed):** EPHY_25M (0x970) = PLL_PERI0(1X)/24 with gates at bits 31/30; driver parent was ahb3.
  - IOMMU_BGR (0x7BC) documents only the gate bit; the driver/DT use a reset at bit 16 (`RST_BUS_IOMMU`, same as H6).
    Board read below.
  - PLL_AUDIO modelling (doc-only, latent): the manual has hs = 24·N/M1 and 4X = 24·N/M0/M1/P. The driver's
    `pll-audio-hs` is N/P with M0 = 2 not modelled, so with the SDM table rates its rate equals the real 4X output and
    `pll-audio-4x` = hs/1 is correct, but mux index 3 ("PLL_AUDIO(hs)") is really ~6x (P·M0) higher than the kernel
    believes, and a non-table rate is computed 2x too high. Nothing selects index 3 today (AHUB pins 4x, codec/OWA use
    1x/2x, ties pick the lower index). Keep it that way; not changed, because the H616 codec rate hack in
    `0702-...digital-audio-node.patch` depends on the current numbers.
  - Not modelled (missed features, low): 0x0F20 24M/27M clock output (27M needs PLL_CSI, which has no register in
    this manual), 0x0F04-0x0F10 PLL lock debug and frequency detect, PLL_PAT spread spectrum (only audio SDM is used).
  - Manual typo: register list gives TCON_TV1 at 0x0B80; the description (and our code) use 0x0B84.
  - The manual recommends gating PLLs with OUTPUT_ENABLE rather than ENABLE (§3.3.3.6); sunxi-ng gates with bit 31.
    Doc-only (mainline behaviour, no observed problem).
- U-Boot `clock_sun50i_h6.c` for the H616: PLL_PERI0 0xa8003100 (2X = 1.2 GHz, lock/output enable), PSI and AHB3
  0x03000002 (200 MHz), APB1 0x03000102 (100 MHz), APB2 = OSC24M, MBUS PERI0(2X)/3 = 400 MHz, CPU AXI/APB 0x301,
  PLL_CPUX sequence (lock-enable off, output gate off, N, enable, lock, 20 µs, output on) = §3.3.3.5. CE clock in our
  U-Boot TRNG driver = PERI0(2X)/4 = 300 MHz = the CE maximum (§10.1.3.12). All within the CE clock requirement
  (AHB ≤ 200, MBUS ≤ 400, CE ≤ 300 MHz). **OK.**
- U-Boot `clk-sunxi-add-h6-h616-ce-gates-and-reset.patch`: CE 0x680 bit 31, BGR 0x68C bit 0 / reset bit 16, MBUS
  gate 0x804 bit 2. **OK.**

### 3.5 System configuration (p.133-135)
- SYS_CFG documents only VER_REG 0x24 and EMAC_EPHY_CLK_REG0 0x30. dwmac-sun8i uses 0x30 TX/RX delay (12:10 max 7,
  9:5 max 31), RGMII/RMII bits, TX clock source: **OK**. Bit 27 XMII_SEL and 31:28 are never set (EMAC0 works with 0).
  EMAC1 0x34, SRAM C mapping 0x04 and the thermal SRAM bit at 0x0 bit 16 are not documented. Doc-only.

### 3.6 Timer / watchdog (pp.136-149), 3.7 High-speed timer (pp.150-158)
- sun4i-timer offsets, IRQs, OSC24M source and prescalers; watchdog layout, key 0xA57, 0.5-16 s table. **OK.**
- hstimer: register layout = the D1 offsets that `timer-sun5i` uses, IRQs 45/46, clock AHB1 (`bus-hstimer` parent
  `psi-ahb1-ahb2`). Counter is 56-bit, driver uses the low 32 bits (wraps every ~21 s at 200 MHz). W3 Kconfig patch +
  `CONFIG_SUN5I_HSTIMER=y` are merged (fix/sunxi-h616-small-gaps). **OK**, board check pending (list below).
- AVS0/AVS1 counters (0xC0-0xCC, CCU 0x740 gate): no driver, W26 unchanged.

### 3.9 DMA (pp.164-192)
- DRQ table (pp.166-167) vs. every `dmas`: OWA 2, AHUB0/1/2 3/4/5 (HDMI `ahub1` = 4, i2s3 overlay = 5), codec 6,
  NAND 10, UART0-5 14-19, SPI0/1 22/23, TWI0-4 43-47, S_TWI0 48; DMIC RX 7 unused. 16 channels, 49 request lines.
  The H616 cfg (`dma-sun6i-dma-add-sun50i-h616-support.patch`) = the H6 cfg: bursts 1/4/8/16, widths 8-64 bit,
  end-of-list 0xFFFFF800, max segment 2^25-1, AUTO_GATE 0x28 = 0x4 (MCLK only). DESC_ADDR has high bits but
  DMA_PARA has none, so not using the A100 `has_high_addr` path is right. **OK.**

### 3.10 Thermal sensor (pp.193-204)
- Base, SPI 19, 4 sensors (GPU, VE, CPU, DDR), offsets, acquire 48 / period 480 = manual defaults. Manual formula
  T = (data - 3255) / (-12.401) °C; the driver's fit differs by +0.2 °C at 50 °C and +0.4 °C at 100 °C (inside ±3 °C).
  **OK.** Alarm/shutdown thresholds and their IRQs unused (W14, software trips cover it).

### 3.12 IOMMU (pp.206-254)
- Masters: 0 DE, 1 DI, 2 VE_R, 3 VE, 4-5 reserved, 6 G2D (table 3-8). DT: DE33 planes `<&iommu 0>`, deinterlace
  `<&iommu 1>`, VE `<&iommu 3>, <&iommu 2>`. Register offsets, page-table formats and permission bits match; our
  page-size and sibling-reset patches are consistent. **Defect 2 (fixed):** master 6.
- datasheet-checklist row "only the VE uses it" is stale (DE and DI are wired in the DT now).

### 3.13 RTC (pp.275-290)
- 16-bit linear day counter (`RTC_LINEAR_DAY`), no external 32k crystal input, internal-RC calibration register and
  the driver's rate formula, 32k fanout source/gate/divider. **OK.** The driver writes alarm config 0x50, which the
  H616 manual does not list (harmless). Board: osc32k = calibrated `iosc-32k` (impl-small-gaps 8e).

### 4.4 Video decoding / 4.5 encoding (pp.299-307)
- Feature lists only, no VE registers. One new row already recorded in the checklist (MPEG-4 SP/ASP max 3840x2160).

### 5.1 DRAMC (p.308)
- Overview only (DDR3/DDR3L/DDR4/LPDDR3/LPDDR4, 2 CS, 32-bit, up to 4 GB). No registers: U-Boot `dram_sun50i_h616.c`
  and our `sunxi-dram-h616-ddr3-jedec-init-delays` / `-retry-transient-training-failures` patches cannot be checked
  against this manual.

### 6 EMAC (pp.394-418)
- Base, IRQs 46/47, register offsets 0x00-0xD0, MDC divider (bits 22:20, /16../128 → 1.56 MHz from 200 MHz),
  normal-descriptor layout. **OK.** TX_CTL1 bit 2 (TX_NEXT_FRM, set by the driver) is undocumented.
- **Defect 9 (fixed, inert):** RX_TH encoding.
- **Jumbo frames — correction for impl-emac-jumbo.md** (it said the EMAC chapter was missing):
  - RX_CTL0 (0x24, p.408): bit 30 frame-length control, bit 29 JUMBO_FRM_EN, bit 28 strip FCS, bit 27 check CRC.
    TX_CTL0 (0x10, p.406): bit 30 frame-length control.
  - Length limits: control = 0 → 2048 bytes, or 10240 with JUMBO_FRM_EN; control = 1 → 16384 bytes. JUMBO_FRM_EN alone
    accepts 9018-byte frames without a giant-frame error (p.403).
  - FIFOs: TX 4 KB, RX 16 KB (p.394).
  - Descriptor buffer-size field is 11 bits (≤ 2047 bytes) for RX and TX (pp.399-400), despite "4 KB per
    descriptor" in the overview; larger frames must span descriptors (FIRST/LAST), the RX frame-length field is 14 bits.
  - So: the branch fix/sunxi-h616-emac-jumbo (maxmtu 2018, single descriptor) matches the hardware as the
    driver uses it; "up to 16 KB" needs frame-length control = 1 plus multi-descriptor RX/TX in the stmmac normal
    descriptor path (and, by inference, TX threshold mode above the 4 KB TX FIFO, i.e. no TX csum offload).

### 7.2 TVE (pp.435-458)
- TVE_TOP DAC map/CFG0-2 and encoder registers 0x000-0x03C, 0x0F8-0x13C, 0x380/0x3A0 match; chroma words
  0x21F07C1F (NTSC) / 0x2A098ACB (PAL); 216 MHz clock (table 7-4) = crtc clock × 16. Load detection (W15) present in the
  tree (new mode + DAC0 enable, status 0x038). **OK.**
- Doc-only: CFG 0x004 bits 18/17 and resync bit 29 are written (as the vendor driver does) although marked
  reserved; debounce 0x9999 where only bits 3:0 exist for DAC0; AUTO_DETECT_CFG1 0x0a3c00ff is ~80 ms pulse period
  (comment says 20 ms; manual suggests polling every 200 ms). TVE IRQ (SPI 68, TVE_030 bit 16) could replace polling.
  The manual lists PAL-D and NTSC-M only; the driver offers exactly those.

### 7.3 HDMI (p.459)
- Feature list only. Adds two items to the datasheet's list: YUV 4:2:0 output and HBR passthrough (new rows below).

### 8.1 Audio HUB (pp.463-512)
- Vendor `sunxi_v2` offsets match the register list (RST/GAT bits, APBIF TX/RX, I2S n×0x100, DAM 0xA00+n×0x80).
  Manual typo: CHMAP2/3 listed at 0x274/0x278, described at 0x27C/0x280 (the driver uses the latter). **OK.**
- Doc-only: TX FIFOs are 3 × 64×32-bit and RX 3 × 128×32-bit; DT `tx_fifo_size = <128>` is wrong but only printed in a
  debug log (maxburst 8 either way).

### 8.2 DMIC (pp.513-525)
- N/A on the Zero2 (pins only on PI = RGMII). Base 0x05095000, SPI 22, DRQ 7; no H616 node/match.

### 8.3 OWA / S/PDIF (pp.526-538)
- CTL (RST bit 0, GEN bit 1; MCLKDIV/MCLKEN moved to 9:5/bit 3, bit 2 is LOOP, never written), TX_CFIG 0x04,
  FCTL 0x14, INT 0x1C, TX FIFO 0x20, CNT 0x24, CHSTA 0x2C/0x30, 128×24 TX FIFO, 16/20/24-bit, TX only, DRQ 2. **OK**
  except **defect 7 (fixed):** module clock rate propagation.

### 8.4 Audio codec (pp.539-567)
- DPC, FIFOC (FS 31:29, FIFO_MODE, TX_TRIG, SAMPLE_BITS), DAC_REG 0x310, MIXER 0x314, RAMP 0x31C, DRC/HPF bits from
  small-gaps item 7 (DAP_CTRL 31/29/28, DRC_CTRL 6/5/4/3/1/0). **OK** except **defect 8 (fixed):** reg size.
- Doc-only: the DAI says `sig_bits = 24`, but the FIFO is FIFO_I[19:0] and the feature list says 16/20-bit: real
  resolution is 20 bits. DRC delay/look-ahead (DRC_CTRL bit 2, 13:8) not exposed.

### 9.1 TWI (pp.573-593)
- `clk_n_base_0` formula = TWI_CCR. Bases, IRQs, DRQs. **OK** except **defect 4 (fixed):** duty cycle.
- TWI_DRV packet/DMA engine (0x200-0x304) and slave mode unused (W33): the `dmas` on the i2c nodes serve only TWI_DRV.

### 9.2 UART (pp.594-622)
- **Defect 3 (fixed).** The pending upstream H616 UART series (James Hilliard v5, h616-patch-landscape.md) uses the
  same `allwinner,sun50i-h616-uart` compatible; check whether it also skips these probes before carrying both.
- 256-byte FIFOs, no CPR register (that series covers it). IrDA exists in hardware (MCR[7:6] = 01), no Linux
  support: GAP unchanged.
- Max baud (W32): APB2 parents OSC24M/RTC32K/PSI/PERI0(1X), M 1-4, N 1/2/4/8 (§3.3.5.49): neither 48 nor 64 MHz is
  possible, so 3 and 4 Mbit/s are not reachable; 1.5 Mbit/s at 24 MHz. Correction to impl-small-gaps 8d: 921600 baud
  (table 9-5, 75 MHz) is reachable with APB2 = PERI0(1X)/8, a clock shared with all UARTs and TWIs.

### 9.3 SPI (pp.623-649)
- W5 re-verified: SPI_BCC 0x38 bit 29 Quad_EN, bit 28 DRM (dual RX, only with Quad_EN = 0), DBC 27:24, STC 23:0;
  spi-nor 1-1-2 reads send the command single and the data rx-only with DRM: correct. FIFO 64 bytes, max 100 MHz,
  CCR CDR1/CDR2/DRS. **OK** except **defect 5 (fixed):** sample mode.
- Uncertain: BCC has no dual-TX bit but the H616 cfg advertises `SPI_TX_DUAL` (copied from R329). The Zero2 uses only
  `spi-rx-bus-width = <2>`, so it is unaffected. Not changed.

### 9.6 Port controller (pp.689-760)
- Bank stride 0x24, DRV +0x14 (2 bits/pin), PULL +0x1C, EINT 0x200 + n·0x20; PH0-PH10 function numbers and our pin
  groups. **OK.** R_PIO `s_rsb` (function 2 on PL0/PL1) is not documented (works on the board).
- Upstream issue, not a Zero2 defect: PIO_POW_MOD_SEL (0x340) puts PF, PH and VCC-IO on bit 12, but pinctrl-sunxi
  writes `BIT(bank)` (reserved bits 5/7 for PF/PH, never bit 12). On the Zero2 PF/PH are 3.3 V (reset value 0 is right);
  PC bit 2, PG bit 6 (1.8 V, set) and PI bit 8 are right. No branch.

### 9.7 LRADC (pp.761-766), 9.8 CIR (pp.767-777)
- LRADC: r329 variant fits (Vref = 3/4 · 1.8 V, 2 kHz). The `sun50i-h616-keys` overlay assumes a 1.8 V aldo1
  (Zero2W); on the Zero2 aldo1 is 3.3 V, so the overlay would compute a wrong vref. Row stays N/A (no keys); documented.
- CIR: 8 MHz base, SCS = 0 → 125 kHz sampling (≤ 1 MHz), 64-byte FIFO, thresholds. **OK.**

### 9.9 PWM (pp.778-799)
- The manual lists PWM1-4 only (PWM23 pair with dead zone). PCCR gating bit 4, source 8:7 (OSC24M/APB1), DIV_M /1-/256,
  bypass 5/6, PCR prescale 7:0, ACT_STA 8, PPR, PDZINTV 15:8 match the vendor driver. APB1 is hard-coded as 100 MHz
  (true with U-Boot's APB1 0x03000102). **Defect 6 (fixed).** Not fixed: the bound pair returns -EINVAL instead of
  trying div_m > 1 (complementary periods stop at ~0.7 s). Capture missing (W34).

### 10.1 Crypto engine (pp.819-830), 10.2 SID (p.831)
- Task descriptor, algorithm IDs (TRNG 0x1C, PRNG 0x1D), modes, key sizes, word addresses, data-length units, error
  register, clock limits: match sun8i-ce and our U-Boot TRNG driver. The manual lists everything W29 counts as missing
  (AES CTR/CTS/OFB/CFB/CBC-MAC/XTS, DES CTR/CBC-MAC, HMAC-SHA1/256, RSA 512-4096, ECC 160-521): confirmed hardware
  features. PRNG exists in hardware; it stays N/A by upstream decision (impl-small-gaps item 3).
- SID: one paragraph, no eFuse map: the calibration offsets (0x14 THS, 0x2C TVE, 0x0 speed bin) cannot be checked.

## Build check

Local branch `test/um-review-all` (all nine branches merged, not pushed), `kernel-check/build-kernel.sh` `STAGE=all`,
`WORK=kernel-check/work-umreview`, ccache (`run-umreview-all.log`):
- `patches applied: 820, failed: 0` (811 + 9); the branches merge into each other without conflicts.
- `Image modules` + Zero2 DTB: build exit 0, **0 C warnings**; all DTBs + 57 H616 overlays built, the dtc warnings are
  the pre-existing nanopi-r1s-h5/pine64 ones.
- All eight touched objects compiled; `W=1` rebuild of them: no new warnings (the two `reg_width set but not used`
  in pwm-sunxi-enhance.c lines 168/189 are identical on the unpatched file).
- Zero2 DTB: six UART nodes `"allwinner,sun50i-h616-uart", "snps,dw-apb-uart"`, codec `reg = <0x5096000 0x320>`.
- The build ran on the pre-rebase commits; the rebase onto b9df5096b changed only patch headers (Assisted-by line).


## New acceptance rows (added to docs/datasheet-checklist.md)

| Row | Test |
|---|---|
| CCU EPHY 25 MHz | `clk_summary`: `emac-25m` 25000000 under `pll-periph0` (with defect 1) |
| IOMMU master 6 | prerequisite of W25: G2D node with `iommus = <&iommu 6>` works without faults |
| UART divisor / RS-485 | UART5↔UART2 loopback at 153600 and 921600 baud (921600 needs APB2 = 75 MHz via assigned-clocks); TIOCSRS485 drives RTS (em485) on a logic analyser |
| TWI fast mode | TWI3 at 400 kHz: scope tLOW ≥ 1.3 µs |
| SPI1 sample mode | spidev loopback at 10 MHz and 50/80 MHz |
| PWM | complementary PWM2/3 with dead zone after reconfiguring from a larger to a smaller div_m; single-channel 700 ms period |
| S/PDIF | 44.1 and 48 kHz out with nothing else having played since boot (receiver or logic analyser) |
| HDMI | YUV 4:2:0 output (fold into W12); IEC 61937 HBR passthrough up to 1536 kHz (extend W16) |
| Codec | 20-bit effective resolution (S32 at 192 kHz plays, msbits reported) |
| TVE | connect/disconnect a 75 Ω load: connector status changes within the 10 s poll |
| EMAC | frames up to 16 KB need frame-length control + multi-descriptor stmmac (W31 extension); today MTU 2018 |

## Still open
- Board tests of all nine fixes (none can be exercised on the image kernel; most need wiring or other boards).
- PLL_AUDIO hs modelling (doc-only, latent), SPI `SPI_TX_DUAL` flag, PWM bound-pair div_m search, pinctrl
  PIO_POW_MOD_SEL bit 12 (upstream), TVE IRQ instead of polling, codec `sig_bits`, AHUB `tx_fifo_size`.
- Registers the manual does not describe: R_CPUCFG/R_PRCM (TF-A suspend), DRAMC, SID map, VE/GPU.

## Board results

**Not run.** The board lock was held by other agents (opencl-fixes, desktop-ffmpeg, vulkan-test) for the whole
review window (two queued attempts, 40 + 30 min). None of the findings depend on a board read; the fixes are
justified by the manual text. The read-only script is ready: `harness/analysis/um-review/board-reads.sh`
(`harness/ssh.sh 'bash -s' < harness/analysis/um-review/board-reads.sh`, about 5 s, no writes). It settles:
- CCU 0x030017BC bit 16 sticks at 1 → the IOMMU reset bit is real despite the manual (else it is a no-op);
  0x03001970 / `clk_summary` `emac-25m` (200 MHz today, 25 MHz with fix 1); PLL_AUDIO 0x03001078/0x03001178,
  OWA/codec/AHUB clocks 0x03001A20/A50/A54/A60 (boot audio PLL state behind fix 7).
- UART0/UART1 0x050000C0 / 0x050004C0 (RS485_CTL): non-zero low bits = the DW DLF code wrote a fraction there
  (fix 3); 0x050000B4 DBG_DLH.
- PIO_POW_MOD_SEL 0x0300B340-0x0300B350 (expect bit 6 = 1 for the 1.8 V PG bank, bit 12 = 0).
- small-gaps board tests that need no wiring: `available_clocksource` lists `hstimer` (W3), spi-nor params
  `1S-1S-2S` + mtd0 sha256 `711306f6…e933` (W5), mmc1 `ios` UHS timing (W10), `osc32k-fanout` enabled, DRC/HPF
  controls present (W17).
