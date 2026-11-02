# orangepi-build mining for the Orange Pi Zero2 (H616 / sun50iw9)

Date: 2026-11-02. Research only: no board, serial, network, sudo or `~/orangepi5` access; no vendor
script was executed (debs unpacked with `dpkg-deb -x`, kernel trees are blobless sparse checkouts).

## 0. What was fetched

| Item | Where (local) | Upstream ref |
|---|---|---|
| orangepi-build (shallow, both branches) | `kernel-check/dl-upstream/orangepi-build` (worktree = `next`) | `main` `f00cd197b4a9873f36093d4f4748b733642059a7` ("buster: fix debian-archive-keyring.gpg"); `next` (= HEAD) `a95129bf30ea11886cc35f08ebb3e69695a26656` ("rk3588: Ubuntu 26.04 / Debian 13 with Linux 6.18"). Only these two branches exist (`git ls-remote`). |
| linux-orangepi `orange-pi-4.9-sun50iw9` | `kernel-check/dl-upstream/linux-orangepi/orange-pi-4.9-sun50iw9` (+ `.files` full path list) | `0cd0547ea405b84b5b60fbc92978ac1bc2b68055` (2022-05-17, "Update uwe5622 driver") |
| linux-orangepi `orange-pi-5.4-sun50iw9` | `.../orange-pi-5.4-sun50iw9` | `3a4a29414d558664847202f4d8919b8ab8bcf4a8` (2026-08-25, still maintained) |
| linux-orangepi `orange-pi-6.1-sun50iw9` | `.../orange-pi-6.1-sun50iw9` | `71144529b0334d1488624c41d0d3ba0cb03dd4c1` (2024-07-10) — a **mainline-based** 6.1.31 tree, not a BSP |
| Vendor CedarC/gst-omx debs (fetched by orangepi-build for other Allwinner families) | `harness/research/ve-encoder/dl/orangepi-build/` (see `PROVENANCE.txt`, `SHA256SUMS*`) | `orangepi-xunlong/rk-rootfs-build` `t527_packages` `6a1bb8b6…`, `sun60iw2_packages` `7b6d78d4…` |

Other branch refs seen (not cloned): linux-orangepi `orange-pi-5.13-sunxi64` `e5d69c78…` (orangepi-build **main**'s
`current` for Zero2), `orange-pi-5.16-sunxi64` `1a0c42b1…` (commented-out option in `next`). u-boot-orangepi
`v2018.05-sun50iw9` `27309625…` (legacy/current BSP U-Boot), `v2021.10-sunxi` `0b91e222…` (next),
`v2021.07-sunxi` `427bcfef…` (main/current).

### Which kernel/U-Boot the vendor build uses for `BOARD=orangepizero2`

From `external/config/boards/orangepizero2.conf` + `external/config/sources/families/sun50iw9.conf`:

| orangepi-build branch | BRANCH | Kernel | Kernel config | U-Boot / boot chain |
|---|---|---|---|---|
| next (default `KERNEL_TARGET="next"`) | legacy | `orange-pi-4.9-sun50iw9` (4.9.170) | `linux-sun50iw9-legacy.config` | `v2018.05-sun50iw9` + boot0 + `monitor.fex` (vendor BL31) via `dragonsecboot` |
| next | current | `orange-pi-5.4-sun50iw9` (5.4.125) | `linux-sun50iw9-current.config` | same BSP chain, `monitor.fex-linux5.4` + `optee.fex`; on arm64 hosts only a prebuilt u-boot deb is copied (`scripts/compilation.sh:116`) |
| next | next | `orange-pi-6.1-sun50iw9` (6.1.31) | `linux-6.1-sun50iw9-next.config` | mainline-style `v2021.10-sunxi` + upstream TF-A pinned at `4b9be5abfa8b1a7c7e00776da01768d3358e648a` (`PLAT=sun50i_h616 DEBUG=1`) |
| main | legacy / current | 4.9-sun50iw9 / `orange-pi-5.13-sunxi64` | `linux-5.13-sunxi64` | `v2018.05-sun50iw9` / `v2021.07-sunxi` + TF-A master |

**There are no kernel or U-Boot patch files for sun50iw9 in orangepi-build** (`external/patch/` only holds
bootsplash/packaging/misc and `atf-sunxi64` H6 patches); all vendor changes live in the linux-orangepi /
u-boot-orangepi branches. The Zero2 U-Boot defconfig on `v2021.10-sunxi` is plain mainline (DRAM training
options, `PHY_REALTEK`, `SUN8I_EMAC`, `PWRLED=PC12`) — nothing we lack in 2026.10.

## 1. Findings by spec-checklist row

Legend for "Relevance": **portable** = GPL source we could adapt; **reference** = facts/values only;
**blob** = closed binary, black-box use only; **none** = nothing useful.

### CPU H616 quad A53 (cpuidle / suspend WIP)
- Vendor: idle state in both BSP DTs (4.9 `arch/arm64/boot/dts/sunxi/sun50iw9p1.dtsi:125`, 5.4 `sun50iw9.dtsi:125`):
  one `arm,idle-state`, `arm,psci-suspend-param = <0x0010000>`, entry 46 µs / exit 59 µs / min-residency 3570 µs,
  `local-timer-stop`, no cluster state — **already recorded in impl-pm.md**.
- New for PM: the vendor BL31 binaries `external/packages/pack-uboot/sun50iw9/bin/monitor.fex`
  ("v1.0(debug):05d6c57 Built 2021-10-28") and `monitor.fex-linux5.4` ("v1.0(debug):54937d5 Built 2021-12-13")
  contain `plat/sun50iw9p1/plat_pm.c`, `"cpuidle init version V1.0"`/`"V2.0"`, `standby_param`, `vcc-dram`. They are
  the only implementation of H616 CPU_SUSPEND/standby we can disassemble (binary only, Allwinner's TF-A fork). Copied
  to `ve-encoder/dl/orangepi-build/boot/`. 4.9 config: `CONFIG_SUNXI_CPU0IDLE=y`; 5.4: `drivers/char/sunxi_standby/`
  (`CONFIG_SUNXI_STANDBY_DEBUG=y`). The 4.9 tree carries `drivers/soc/sunxi/arisc/` but the sun50iw9 configs do not
  enable it (H616 has no ARISC, consistent with impl-pm.md).
- The vendor `next` (6.1) DT adds only `scpi_sram: scpi-sram@17c00` (`arm,scp-shmem`, 0x200) and enables
  `CONFIG_ARM_SCPI_PROTOCOL=y` but has **no** SCPI firmware node and no idle-states: mainline-path vendor images have
  no cpuidle either.
- Relevance: reference + blob. **Recommendation (PM):** disassemble `monitor.fex-linux5.4` `plat_pm.c` paths
  (`aarch64-linux-gnu-objdump -b binary -m aarch64`, load address from the boot_package header) to confirm which
  R_CPUCFG CPUIDLE registers the vendor writes for power-state 0x0010000 and how standby gates DRAM; use it only as a
  register-sequence oracle for our native TF-A implementation.

### GPU Mali-G31 MP2 (GLES 3.2) / OpenCL 2.0
- Vendor kernels: Arm kbase `modules/gpu/mali-bifrost/driver` **r20p0-01rel0** (5.4 `.../midgard/Kbuild:24`), sunxi
  platform glue `platform/sunxi/mali_kbase_config_sunxi.c` (GPL). 6.1 (next) uses panfrost (`CONFIG_DRM_PANFROST=m`),
  GPU node `status = "disabled"` + overlay `sun50i-h616-gpu.dts`, OPP table commented out.
- Vendor GPU DVFS (5.4 Zero3 DT, `gpu@1800000 operating-points`): 600/576/540/504/456/420/384/360/336/306 MHz,
  **all at 950 mV** (Armbian's `sun50i-h616-gpu-opp.dtsi` scales 810-950 mV for the same frequencies).
- **No Mali userspace blob (libmali) for G31 and no OpenCL ICD anywhere in orangepi-build for sun50iw9**; the only
  libmali is `libmali-sunxi-r3p0` (Mali-400/Utgard, H3, armhf). Desktop images install stock `glmark2-es2-x11`.
- Relevance: none for the GLES/OpenCL rows. **Recommendation (gpu):** stay on Mesa panfrost + rusticl; nothing to take.
  If any GPU instability appears at 306-504 MHz with Armbian's lower voltages, the vendor's flat 950 mV is the
  known-good fallback.

### Decode H.265 Main10@L5.1 4K@60 / 6K@30, and H.264 4K@30
- Vendor stack: `drivers/media/cedar-ve/cedar_ve.c` (`/dev/cedar_dev`, GPL) + userspace CedarC (OMX/`libvdecoder`).
  5.4 copy is byte-identical to `ve-encoder/dl/vendor-cedar_ve-5.4-sun50iw9/cedar_ve.c` (already have). 4.9 version
  (1937 lines vs 2442) copied to `dl/orangepi-build/src/linux-orangepi-4.9-sun50iw9/cedar-ve/`. Vendor VE clock
  window `VE_CLK_HIGH_WATER 900` / `LOW_WATER 100` MHz, rate chosen by userspace via `IOCTL_SET_VE_FREQ`.
- Vendor 6.1 (mainline path) Cedrus: compatible `allwinner,sun50i-h616-video-engine` → **`sun50i_h6_cedrus_variant`
  (incl. `CEDRUS_CAPABILITY_H265_10_DEC`) at `mod_rate = 600000000`**; a separate `sun50i_h616_cedrus_variant`
  without 10-bit exists but is unused. Our 7.3.1 tree also maps H616 to the H6 variant, at 648 MHz.
- **No CedarC for sun50iw9 is shipped by orangepi-build** (re-confirms ve-encoder/PLAN.md §2.1). New: orangepi-build
  pulls a **glibc aarch64 CedarC for T527** (`rk-rootfs-build` `t527_packages`, `libcedarc_1.0_arm64.deb`) whose
  `libawvp9HwAL.so`, `libawvp9Hw.so`, `libvencoder.so`, `libvenc_base.so`, `libvdecoder.so` carry **DWARF built
  `-g -O0`**, and whose `libawvp9HwAL.so` references `AW_SOC_H616` / `AW_SOC_H313` (Vp9hw.c line 2425) — i.e. one
  CedarC build covers H616. `libawh265.so` logs "the chip(%llx) is not support 10bit-stream" and
  "VE version: %llX" (10-bit gating is by IC version).
- Relevance: blob (DWARF reference). **Recommendation (vdec):** use the T527 `libawh265.so`/`libawh264.so` (stripped
  of DWARF but same generation) and the DWARF libs to (1) find the IC-version table that enables 10-bit and confirm
  H616's VE id passes it, (2) read the H.265 10-bit output-format/afbc register usage; Cedrus already exposes
  `H265_10_DEC`, so the 10-bit gap is userspace/format plumbing + validation, not a missing driver.

### Decode VP9 Profile 2 4K@60
- Vendor kernel: **only the 4.9 BSP has a VP9 driver**: `drivers/media/cedar-vp9/google_vp9.c` (Allwinner, GPL-2.0+,
  "0.01alpha", `/dev/googlevp9_dev`, compatible `allwinner,sunxi-google-vp9`). Its DT node
  (`sun50iw9p1.dtsi:583`): `vp9@01c00000`, reg `0x01c00000/0x1000` + SRAM-ctl `0x03000000` + CCU `0x03001000`,
  `interrupts = <GIC_SPI 90>`, `clocks = <&clk_pll_ve>` only, `iommus = <&mmu_aw 2 1>`. It is **disabled** in both
  the vendor defconfig (`# CONFIG_VIDEO_GOOGLE_VP9_DECODER_SUNXI is not set`) and orangepi-build's legacy config.
  The 5.4 BSP (the production H616 kernel, still updated in 2026) **has no `cedar-vp9` at all**; it instead declares a
  second VE instance `ve1: ve1@1c0e000 { compatible = "allwinner,sunxi-cedar-ve"; iommus = <&mmu_aw 2 1>; }` and gives
  GIC SPI 90 to **G2D** (`g2d@1480000`). Mainline 7.4's H616 VE node likewise uses `iommus = <&iommu 3>, <&iommu 2>`.
  Mainline H616 CCU has no VP9 clock/reset (H6 has `vp9_clk` 0x6c0 / `RST_BUS_VP9` 0x6cc).
- Interpretation: the 4.9 node is an H6 copy-paste (wrong IRQ for H616). Together with `AW_SOC_H616` appearing in
  `libawvp9HwAL.so` (the VE-integrated "AL" VP9 decoder, as opposed to `libawvp9Hw.so` which opens Hantro
  `/tmp/dev/hx170`), the evidence says **H616 VP9 is decoded by the Cedar VE itself (IOMMU master 2 = VE's second
  port), not by a separate Hantro G2 block**. Not board-verified.
- Relevance: reference + DWARF blob. **Recommendation (vdec):** do not pursue hantro `sun50i-h6-vpu-g2` for H616.
  Reverse-engineer VP9 from `t527 libawvp9HwAL.so` DWARF (your `avs2-regs-libawavs2.txt` cites an Android-29 build;
  if `libawvp9HwAL.pahole.txt` has the same origin, the T527 glibc build is `-O0` with full locals and is easier to
  follow). Cheap board check: devmem-read 0x01c00000
  (G2 ID register on H6) with VE/VP9 clocks on — a bus error or zeros confirms no G2.

### Decode AVS2 JiZhun 10-bit 4K@60
- Vendor: no kernel component (AVS2 runs on the VE, H.265 slot). Userspace `libawavs2.so` in both new debs
  (T527: 68000 B, no DWARF; sun60iw2: 69624 B, DWARF but VE2 generation). vdec already has an Android DWARF copy.
- Relevance: blob. **Recommendation (vdec):** diff the T527 `libawavs2.so` register writes against your
  Android-derived `avs2-regs-libawavs2.txt` to check that the H616-generation layout matches.

### Encode H.264 4K@25 / 1080p@60 and JPEG snapshot
- Vendor kernel side: same `cedar_ve` (encoder IRQ flags `en_irq_flag`, `jpeg_irq_flag`) — already in dl.
- New userspace: **T527 CedarC "stable_v1.3.0_common" glibc aarch64 encoder split** — `libvencoder.so` (DWARF),
  `libvenc_base.so` (DWARF), `libvenc_common.so`, `libvenc_h264.so` (242 KB, 156 exported syms, strings
  "video encoder h264 version1/version2", `SetIspRegister_old_version`, "IcVersion %x don't support this
  eGopMode"), `libvenc_h265.so`, `libvenc_jpeg.so`, `libVE.so` (reads VE 0xf0/0xe0/0xe4 for `ic_version`),
  `libMemAdapter.so`, plus `vencoder.h` (42 KB) headers. This is the **same split library set PLAN.md §2.1 said was only
  available inside the TrimUI H618 firmware**, here as a public download. The sun60iw2 (A733/T736, VE2) deb adds a
  `demoVencoder` binary and DWARF `libvenc_codec.so` but is the wrong engine generation.
- Relevance: blob (A/B oracle + DWARF). **Recommendation (encoder):** check `EncAdapterGetICVersion`/the IC-version
  switch in T527 `libvenc_h264.so` for the H616 VE version; if accepted, this replaces the TrimUI-firmware option for
  the PLAN §4.6 A/B run (with the `/dev/cedar_dev` shim; note `libVE.so` also wants `/dev/sunxi_soc_info` for chip id).

### HDMI 2.0a 4K@60 (+ HDMI audio, CEC)
- Vendor 5.4: `drivers/video/fbdev/sunxi/disp2/hdmi2/` (Allwinner/Synopsys DW-HDMI, GPL), `CONFIG_HDMI2_DISP2_SUNXI`,
  `HDMI2_CEC_SUNXI`, `HDCP/HDCP22`. PHY values for `CONFIG_ARCH_SUN50IW9` in `hdmi_core/api/phy.c` (`phy301[]`):
  our 7.3.1 `sun50i_h616_{mpll_cfg,cur_ctr,phy_config}` already match them at 74.25/148.5/297 MHz, **but at 594 MHz
  the vendor differs**: `OPMODE_PLLCFG = 0x1A7C` (ours `0x1a40`), and after the standard writes it does
  `phy_write(dev, 0x17, 0x8006)` only when `pixel_clock == 594000` (`phy.c:~1659`; mainline writes nothing to 0x17 for
  H616). PLLGMPCTRL is forced to 3 on sun50iw9 (matches ours). `config.h` also sets `CCMU_PLL_VIDEO2_BIAS_ADDR
  0x03001350` for sun50iw9.
- Vendor 6.1 (mainline path) uses the same DE33/TCON-TOP/dw-hdmi stack as Armbian (nothing newer than our patches).
- HDMI audio (vendor AHUB): `asound.state.sun50iw9-next` routes `I2S1OUT Switch = true`, `I2S1 Src Select =
  APBIF_TXDIF0`; the vendor ships `hdmi-audio.service` → `/usr/bin/inithdmiaudio <wav> -D 2` (tinyalsa player blob,
  `external/packages/blobs/sunxi/h616/inithdmiaudio`) and on 4.9 `orangepi-hardware-optimization` plays a wav on
  `hw:2,0` at boot — i.e. the vendor needs a "first play" to wake HDMI audio.
- Relevance: reference. **Recommendation (display/whoever owns HDMI; route via audio/tve):** when 4K@60 is tested and
  shows no lock/sparkles, try the vendor 594 MHz values (`0x1a7c` + PHY reg 0x17 = 0x8006) as a one-line experiment in
  `sun8i_hdmi_phy.c`. For HDMI audio verification, set the AHUB mixer to the vendor's I2S1/APBIF_TXDIF0 routing and
  expect a possible first-open glitch.

### TV CVBS PAL/NTSC
- Vendor: `drivers/video/fbdev/sunxi/disp2/tv/` (4.9 and 5.4; `CONFIG_TV_DISP2_SUNXI=y` only in the 4.9/legacy
  config, **off in the 5.4 current config**, absent in 6.1). Zero2 4.9 DT: `tv0@01c94000` reg `0x06520000/0x100`
  (TVE_TOP) + `0x06524000/0x3fc` (TVE0), `dac_src0 = 0`, `dac_type0 = 0` (CVBS), `interface = 1`,
  **`status = "disabled"`**; disp node `dev1_output_type = 2` (TV), `screen1_output_mode = 0xb` (PAL).
- Already fully mined by impl-audio-tve.md (sun8i_tve driver written). Relevance: reference.
  **Recommendation (audio/tve):** nothing new; note the vendor itself ships TV-out disabled on Zero2 and dropped it
  from its 5.4 image, so there is no vendor image to A/B against except 4.9 legacy.

### Audio 3.5 mm line-out (13-pin)
- Vendor: 4.9 `sound/soc/sunxi/` `CONFIG_SND_SUN50IW9_CODEC` (DT `lineout_vol = 0x1a`, `pa_ctl_level = 1`,
  `pa_msleep_time = 100`, `ramp_func_used = 1`, `adcdrc/adchpf` keys are boilerplate); 5.4 `sound/soc/sunxi_v2/`;
  6.1 `sound/soc/sunxi/sun50iw9-codec.c` plus mainline `sun4i-codec`. No capture (confirmed by impl-audio-tve.md).
- Relevance: reference. **Recommendation (audio/tve):** for the line-out test use the vendor default
  `lineout_vol = 0x1a` as the reference level; nothing to port.

### WiFi 802.11ac (859 / UWE5622) and BT 5.0
- Vendor kernel: `drivers/net/wireless/uwe5622/` in all three branches (`CONFIG_AW_WIFI_DEVICE_UWE5622`,
  `WLAN_UWE5622=m`, `SPRDWL_NG=m`) — Armbian's armbian/uwe5622 is the maintained derivative.
- BT userspace, **new and important:** orangepi-build carries the **GPL-2.0 source of the `sprd` hciattach protocol**:
  `external/cache/sources/hcitools/hciattach_sprd.c` (806 lines; reads `/lib/firmware/bt_configure_pskey.ini` +
  `bt_configure_rf.ini`, BD address from `/sys/class/addr_mgt/addr_bt`, `marlin3_pskey` table, registered in
  `hciattach.c:1198` as `{"sprd", …, 115200, 1500000, FLOW_CTL, DISABLE_PM, …, sprd_init, sprd_post}`) and
  `hciattach_sprd_2.c` (variant deriving the BD address from `/sys/class/net/wlan0/address` with bytes 0/1 +1), with a
  BlueZ-5.10-style `Makefile`, `lib/`, `hciconfig`, `hcitool`, `btmon` (`NOTICE`: GPLv2).
- Blobs: `external/config/optional/families/sun50iw9/_packages/bsp-cli/usr/bin/hciattach_opi` sha256
  `d0dbdabb…f9111d` (199632 B, GCC Debian 8.3.0) **= the blob Armbian installs for us**; the newer generic
  `external/packages/blobs/bt/hciattach/hciattach_opi_arm64` (`5f0c2f7a…a8f5b`, 204744 B, GCC 10.2.1) reads
  `/vendor/etc/bt_configure_*.ini` — not suitable. Service: `aw859a-bluetooth.service` = `hciattach_opi -s 1500000
  /dev/ttyBT0 sprd` (identical to ours). WiFi firmware is not in orangepi-build (comes from `orangepi-xunlong/firmware`).
- Relevance: **portable** (hciattach source). **Recommendation (wifi/bt):** build `hciattach` from
  `external/cache/sources/hcitools` (or port `hciattach_sprd.c` into BlueZ's `tools/hciattach.c`) to replace the
  closed `hciattach_opi` blob; this also lets us debug the pskey/LE-feature handshake for the BT 5.0 row from source
  rather than btsnoop. Diff behaviour against `harness/research/hciattach_opi.btsnoop`.

### 3× USB 2.0 host (2 via 13-pin) incl. USB boot; USB-C OTG
- Vendor 6.1 Zero2 DTS enables `ehci1-3`/`ohci1-3`, `ehci0/ohci0` disabled, `usbotg dr_mode = "peripheral"` (same
  comment as mainline), and ships overlay **`arch/arm64/boot/dts/allwinner/overlay/sun50i-h616-usb0-host.dts`**
  (usbotg `dr_mode = "host"`, enable usbphy/ehci0/ohci0). Same overlay exists in 5.4 (`.../sunxi/overlay/`).
- Relevance: portable (trivial DT). **Recommendation (kernel/DT owner):** h616-patch-landscape.md noted Armbian has no
  Zero2 usb0-host overlay; take this one (rename to `.dtso`) so the Type-C port can be tested as host too.

### 26-pin header I2C/SPI/UART/GPIO, PWM
- Vendor overlays (5.4 and 6.1): `ph-i2c1..4`, `pi-i2c0..2`, `ph-uart2/5`, `pi-uart2..4`, `ph-pwm12/34`,
  `pi-pwm1..4`, `spi0-spidev`, `spi1-cs0[-cs1]-spidev`, `disable-leds`, `disable-uart0`, `powerkey` (5.4). PWM driver in
  6.1 is the same vendor `pwm-sunxi-enhance` Armbian carries. Test helper `external/packages/bsp/common/usr/local/bin/
  test_pwm.sh` (exports pwm0, 20 ms period, 50 % duty). GPIO tooling: `install_wiringop` (wiringOP `gpio readall`).
- Relevance: reference. **Recommendation (kernel/DT owner):** Armbian already has equivalent overlays; use
  `test_pwm.sh`'s values for the PWM check.

### 13-pin IR receiver
- Vendor 4.9: `s_cir@07040000`, `interrupts = <GIC_SPI 106>`, supply `vcc-pl` 3.3 V, enabled by default, with
  power-key table (`ir_power_key_code0 = 0x40`, `ir_addr_code0 = 0xfe01`, …); U-Boot `sys_config` `[ir_boot_recovery]`
  uses NEC address `0xfe01` with key codes 0x11/0x19/0x4c — i.e. **the Orange Pi remote is NEC, address 0xfe01**.
  5.4: `drivers/media/rc/sunxi-ir-rx.c` (`CONFIG_IR_RX_SUNXI`); 6.1: mainline `sunxi-cir` (`CONFIG_IR_SUNXI=m`) with
  `&ir { status = "okay" }` in the Zero2 DTS + `sun50i-h616-ir.dts` overlay; image installs `ir-keytable lirc`.
- Relevance: reference. **Recommendation (kernel/DT owner):** mainline driver suffices; consider enabling `&ir` in
  the Zero2 DTS as the vendor 6.1 does, and test with `ir-keytable -p nec -t` expecting scancodes `0xfe01xx`.

### Ethernet, SPI flash, TF card, DDR3, LEDs, power, debug UART (already OK/PARTIAL)
- Nothing new: the vendor `next` uses mainline `dwmac-sun8i`; LED triggers in `orangepi-hardware-optimization` are
  for other boards. The BSP `sys_config_orangepizero2.fex` only feeds boot0 (DRAM tables, `dcdc2/aldo1` for
  axp1530/axp806); not relevant to mainline.

## 2. Vendor drivers we lack (exact paths)

| Driver | Branch / path | Status vs our 7.3.1 | Use |
|---|---|---|---|
| Google/Hantro VP9 char driver | 4.9: `drivers/media/cedar-vp9/{google_vp9.c,google_vp9.h,vp9_mem_list.h}` | none; disabled by vendor, probably not H616 hardware | reference (copied) |
| Cedar VE char driver | 4.9/5.4: `drivers/media/cedar-ve/` | Cedrus instead | reference (copied) |
| disp2 TV encoder | 4.9/5.4: `drivers/video/fbdev/sunxi/disp2/tv/` (12 files) | our new `sun8i_tve` | reference |
| disp2 HDMI 2.0 (DW + HDCP2.2 ESM + CEC) | 5.4: `drivers/video/fbdev/sunxi/disp2/hdmi2/` (83 files) | mainline dw-hdmi | 594 MHz PHY values |
| Vendor codec/AHUB | 4.9 `sound/soc/sunxi/`, 5.4/6.1 `sound/soc/sunxi_v2/`, 6.1 `sound/soc/sunxi/sun50iw9-codec.c` | Armbian carries sunxi_v2 AHUB | none new |
| G2D, DI (deinterlace v3x), sysinfo, standby | 5.4: `drivers/char/sunxi_g2d/`, `drivers/char/sunxi-di/drv_div3x/`, `drivers/char/sunxi-sysinfo/`, `drivers/char/sunxi_standby/` | not on spec | DI: jernejsk `h616-deinterlace-v1` exists |
| Mali kbase r20p0 | 4.9/5.4: `modules/gpu/mali-bifrost/driver/` | panfrost | none |
| sunxi IR rx/tx | 5.4: `drivers/media/rc/sunxi-ir-rx.c`, `sunxi-ir-tx.c` | mainline sunxi-cir | none |
| hciattach sprd | orangepi-build `external/cache/sources/hcitools/hciattach_sprd.c` | blob today | **port** |

Not found anywhere in the vendor trees: an AVS2 kernel driver (AVS2 is VE + userspace), a separate VP9 driver in the
production 5.4 kernel, an H616 CVBS driver in the mainline-based 6.1 tree, a Mali-G31 userspace/OpenCL blob.

## 3. Files worth extracting for encoder/decoder reverse-engineering

All in `harness/research/ve-encoder/dl/orangepi-build/` (provenance and checksums in `PROVENANCE.txt`,
`SHA256SUMS`, `SHA256SUMS.extracted`; none duplicates an existing file under `harness/research` or `kernel-check`).

| File (under `x/t527_packages_jammy_libcedarc_libcedarc_1.0_arm64/usr/lib/aarch64-linux-gnu/` unless noted) | Why |
|---|---|
| `libawvp9HwAL.so` (381992 B, DWARF `-O0`, refs `AW_SOC_H616`) | VE-integrated VP9 decoder, H616 code path — **vdec** |
| `libawvp9Hw.so` (360904 B, DWARF) | Hantro hx170 (G2/googlevp9) path, to rule it out — vdec |
| `libawh265.so`, `libawh264.so`, `libawavs2.so`, `libvdecoder.so` (DWARF), `libvideoengine.so`, `libVE.so` | IC-version gating for 10-bit, AVS2 layout cross-check — vdec |
| `libvencoder.so` + `libvenc_base.so` (DWARF), `libvenc_h264.so`, `libvenc_jpeg.so`, `libvenc_common.so`, `libMemAdapter.so`, `usr/include/vencoder.h` | public glibc split encoder for the PLAN §4.6 A/B run — **encoder** |
| `libOmxVenc.so` / `libOmxVdec.so` / `libOmxCore.so` + `x/t527_packages_jammy_gst-omx…/…/libgstomx.so`, `etc/xdg/gstomx.conf` | vendor GStreamer path (component names) if an OMX A/B pipeline is wanted |
| `x/sun60iw2_…/usr/bin/demoVencoder`, `vdecoderdemo`, `libvenc_codec.so` (DWARF) | VE2-generation; only for cross-generation naming of encoder stages |
| `src/linux-orangepi-4.9-sun50iw9/cedar-vp9/`, `cedar-ve/`, `sun50iw9p1.dtsi` | 4.9 kernel ABI (`VP9_IOCTL_*`, `IOCTL_GET_IOMMU_ADDR`) and DT |
| `boot/monitor.fex-linux5.4`, `boot/monitor.fex-linux4.9` | vendor BL31 (PM, not VE) |
| `x/libcedrus1_…/usr/lib/aarch64-linux-gnu/libcedrus.so.1` (+ `-dev` headers) | LGPL A10-era VE helper; low value (source already in `dl/jemk-cedrus`) |

## 4. Licences

- linux-orangepi drivers and DTs: GPL-2.0 (headers say "either version 2 … or later" for cedar-vp9/cedar-ve).
- hcitools (incl. `hciattach_sprd.c`): GPL-2.0 per `NOTICE` (the sprd file itself has no header).
- CedarC libs, gst-omx Allwinner OMX IL, `monitor.fex`, `optee`, `hciattach_opi`, `inithdmiaudio`: no licence file;
  Allwinner/Orange Pi proprietary binaries. Black-box/DWARF use for interoperability only; do not redistribute or
  copy code.
- libcedrus: LGPL-2.1+. gst-omx: LGPL-2.1.
