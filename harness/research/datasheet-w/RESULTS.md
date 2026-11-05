# Datasheet W-items (docs/datasheet-checklist.md W1–W34): triage and state

Task state file (AGENT-RULES "Continuity"). Date 2026-11-05. Trees read: armbian-build `test-cumulative` (wt-cumulative,
c19 = 36e31fcb3), `userpatches/config-opiz2-printserver.conf`, built c17 tree `kernel-check/work-cumul/linux-7.3.1`
(`.config`, DTs, drivers, read-only). W7 and W8 do not exist in the checklist (numbering gap).

Categories: **done** (commit; merged = in test-cumulative) · **host now** (code work possible on the host) · **board** (needs a
board run, no extra hardware) · **hardware** (needs something the user must provide) · **larger** (M/L/XL driver work, not this
round) · **N/A** (not possible or removed upstream, with the reason).

## Triage

| W | Item | Triage | State / evidence | Next |
|---|---|---|---|---|
| W1 | Vulkan 1.1 (panvk G31) | hardware-free, **user decision + larger** | panvk needs `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` and reports 1.0 (impl-gpu-spec.md 4c). Not set image-wide: the user's call (status.md 5). Mesa work tracked in project-vulkan | coordinator/user: decide the env var; Mesa fork work (XL) |
| W2 | Legacy decode conformance | done + larger | fix/sunxi-h616-legacy-dec merged; MPEG-2 1080-line fix confirmed on HW (image 4321861ff). Open root causes: MPEG-4 interlaced B, Xvid half-pel GMC, WMV9 MP B, data partitioning | separate decode tasks (impl-legacy-decode.md) |
| W2b | MPEG-1 decode | done | fix/sunxi-cedrus-mpeg1-mg1s 8140b4eeb (merged c16), FFmpeg 0304/0309 | runner job 11 (project-mpeg1-mg1s) |
| W3 | High-speed timer | done (c82a0745c small-gaps, merged) + **board** | `CONFIG_SUN5I_HSTIMER=y`, `hstimer@3005000` in the c17 .config/DT. Driver uses 32 of 56 counter bits (optional small driver change) | **job 19**: `available_clocksource` lists `hstimer` |
| W4 | CE PRNG | **N/A** (closed) | mainline 7.3 has no `sun8i-ce-prng.c`/`CRYPTO_DEV_SUN8I_CE_PRNG` (removed, CVE-2026-80834); TRNG hwrng OK (`CRYPTO_DEV_SUN8I_CE_TRNG=y`) | row set to closed |
| W5 | SPI dual I/O | done (b01cc7712 + sample mode 5b15a201b, merged) + **board** | c17 DT: `spi-rx-bus-width = <2>` on the Zero2 flash | **job 19**: params `1S-1S-2S`, eGON.BT0 magic, two identical reads |
| W6 | CONFIG_COMPAT | done (400c85da1, merged) + **board** | c17 .config: COMPAT, KUSER_HELPERS, ARMV8_DEPRECATED, SWP/CP15/SETEND emulation all y. COMPAT_VDSO off (Armbian passes no CROSS_COMPILE_COMPAT) | **job 19**: static armhf busybox `uname -m` = armv8l (kernel-check/datasheet-w/busybox-armhf, Ubuntu stonking 1:1.38.0-3ubuntu4, sha256 d18300e7…) |
| W9 | USB-C FEL / gadget / OTG host | **hardware** | config present (musb dual-role, `USB_CONFIGFS*`, `USB_F_PRINTER`, `USB_G_*` as modules), overlay `usb-otg-host`, host has `/usr/local/bin/sunxi-fel` | user: a USB-C **data** cable |
| W10 | SDIO UHS | done (37a01e7b3, merged) + **board** | c17 Zero2 DT: 150 MHz, sdr50/ddr50/sdr104 | **job 19**: mmc1 `ios` timing, no mmc1 errors, WiFi scan |
| W11 | DE33 planes / Porter-Duff | **board** (count) + **hardware** (visual) | `pixel blend mode` property in sun4i-drm (blend-mode patch) | **job 19**: `modetest -p` plane count + blend property, no monitor; visual check needs an HDMI monitor (user) |
| W12 | DE33 10-bit / HDR / YUV out | **larger** (L) + hardware | LE 0256–0285 missing; needs an HDR-capable HDMI monitor to verify | DE33 plan Stage B |
| W13 | DI300 deinterlacer | done (feat/sunxi-h616-di-jpeg-avs + di300-std-controls + compliance-v2, merged) + **board** | board-tested 11-03 (§4.1); D6/D7 fixes untested since | **job 19**: device, IOMMU group, v4l2-compliance, weave round trips |
| W14 | RTC osc32k / thermal accuracy / HW alarm | done (osc32k answered) + **hardware** + larger | iosc-32k calibrated = datasheet row OK. Accuracy needs an IR thermometer (user). HW alarm IRQ: driver work, low value | none this round |
| W15 | TVE plug detection | done (TVE patch merged, "Composite disconnected" verified) + **hardware** | the connect transition needs a 75 Ω load / CVBS display (user) | user hardware |
| W16 | HDMI IEC 61937 passthrough | **hardware** | AVR needed | user hardware |
| W17 | Codec DRC controls | done (28e0e7bbd, merged) + **board** + hardware (listening) | | **job 19**: `amixer` lists ≥ 7 DRC controls; listening needs the 13-pin board (user) |
| W18 | I2S3 overlay + DAM path | done (79ef2101f merged) + **host now: done** (ahub-dam overlay, this task) + **board** + hardware (loopback) | **New overlay `sun50i-h616-ahub-dam`** on `fix/sunxi-h616-datasheet-w` 821dfb5bd (fork): `ahub_dam_mach` → control-only card `ahubdam` with the 13 `Src Select` routing/mixing controls (the datasheet's two DAMs). dtc (kernel flags) clean, fdtoverlay OK alone and with spdif-out + i2s3-ph on the c17 Zero2 DTB | **job 19**: cards `ahubi2s3` (play + capture) and `ahubdam` (13 controls), card order and `aplay -D default`. Loopback pin 21→24 / I2S DAC: user wiring |
| W19 | S/PDIF overlay + clock fix | done (79ef2101f + e11e400f6 642752bdc, merged) + **board** + hardware (receiver) | | **job 19**: card `SPDIF`, `spdif` clk = 24576000/22579200 Hz under `aplay` 48/44.1 kHz |
| W20 | AVS/AVS+ | done | board-verified 11-03 | — |
| W21 | JPEG decode | done (patches.media/h616-jpeg merged, 125.8 MPPS) + open | greyscale/4:1:1 refused to software; greyscale probe result to fold in (status.md 9) | gst-jpeg task |
| W22 | Encoder SPEC extension | **larger** (doc + encoder first) | no encoder driver yet (status.md 9: Kocialkowski uAPI route) | with the encoder task |
| W23 | Keystone / SmartColor / write-back / RCQ | **larger** (XL) | no open code except LE write-back/RCQ | — |
| W24 | 3D formats | **larger** (L) + hardware (3D display) | | — |
| W25 | G2D driver | **larger** (XL) | prerequisite IOMMU master-6 fix merged (4f711b354) | — |
| W26 | AVS0/AVS1 counters | **larger/doc** (M, low value) | no Linux consumer | document as unused or expose later |
| W27 | Secure boot | **N/A** (user decision, irreversible eFuse) | | — |
| W28 | HDCP 1.4/2.2 | **blocked** (keys + ESM firmware) | | — |
| W29 | CE CTR/XTS/HMAC/RSA/ECC | **larger** (L) | sun8i-ce has none for any variant | — |
| W30 | USB2 standby wake | **hardware** | needs the 13-pin expansion board + a USB keyboard (user) | user hardware |
| W31 | Jumbo + half duplex | done (jumbo merged, MTU 2018 tested, `OPIZ2_ETH_MTU` knob) + **board** (half duplex) + larger (16 KB) | | **job 19**: forced 100/10 half duplex, ping the host, autoneg restored |
| W32 | UART 4 Mbit/s / RS-485 / IrDA | done (RS-485/DLF fix 48491b60d merged) + **N/A** (4 Mbit/s: APB2 24 MHz → 1.5 Mbit/s max; IrDA removed from Linux) + **hardware** (loopback, em485 analyser) | rows updated | user: header jumpers (pins 8/10 ↔ UART2 PH5/PH6) + analyser |
| W33 | SPI / I2C slave modes | **larger** (M, driver) | spi-sun6i has no target mode, i2c-mv64xxx no slave | — |
| W34 | PWM pair / capture | **hardware + decision** (pair) + **larger** (capture) | Row corrected: pairs are 01/23/45; header PH2 = pwm2, PH3 = pwm1 (not a pair); pwm3 = PH0 (debug UART TX). Mainline pwm-sun8i v10 has no capture either | user decision (give up the console for a PH0+PH2 pair test) |

Kernel config: every W-relevant symbol is already on in the c17 `.config` (COMPAT set, SUN5I_HSTIMER, SPI_SLAVE/I2C_SLAVE cores,
SND_SUN4I_SPDIF, SND_SOC_SUNXI_AHUB(_DAM), VIDEO_SUN50I_DI300=m, CRYPTO_DEV_SUN8I_CE(+HASH+TRNG), USB gadget/configfs set). No
config change needed this round; `COMPAT_VDSO` stays off (toolchain). Image config (userpatches): nothing to add; the W1 env
var is the user's decision.

## What changed (this task)
- armbian-build branch `fix/sunxi-h616-datasheet-w` from test-cumulative 36e31fcb3, **one commit 821dfb5bd** (pushed to `fork`,
  not merged): `patch/kernel/archive/sunxi-7.3/overlay_64/sun50i-h616-ahub-dam.dtso` + Makefile entry. Checked with the
  kernel's dtc (`-@`, kernel warning set: clean) and `fdtoverlay` on the c17 Zero2 DTB together with spdif-out and i2s3-ph.
- Runner package `harness/research/datasheet-w/runner/` (dsw-job.sh, board-dsw.sh, HANDOFF.md), job
  `harness/runner-queue/19-datasheet-w.md` (18 was taken meanwhile by panfrost-softstop). Host-only inputs in
  `kernel-check/datasheet-w/` (git-ignored): `dtbo/` (spdif-out, i2s3-ph from the c17 build; ahub-dam from dtc),
  `busybox-armhf`.
- docs/datasheet-checklist.md: stale rows fixed (UM-review branches merged, JPEG/DI/MPEG-1 done, PWM pair pins, UART
  4 Mbit/s and IrDA N/A, W4 closed, W table).

## Open after job 19
- Read `logs/runner/checks.txt`: any FAIL names the item. `INFO asound cards` + `aplay -D default` decide whether
  `ahub_dam_mach` can go into the base DT (vendor parity) or must stay an overlay.
- Hardware the user must provide for the remaining S items: USB-C data cable (W9), HDMI monitor (W11/W12), AVR (W16),
  13-pin expansion board (W17 listening, W30 with a USB keyboard), S/PDIF receiver or logic analyser (W19), header jumpers
  (W18 loopback, W32 UART loopback), 75 Ω load/CVBS display (W15), IR thermometer (W14), decision on the PH0+PH2 PWM pair (W34).
- Optional small driver items: hstimer 56-bit clocksource read (W3); not blockers.
