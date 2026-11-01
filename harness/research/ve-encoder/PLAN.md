# Allwinner H616 Video Engine H.264 encoder on mainline Linux — Phase 1 research and plan

Date: 2026-11-01. Board: Orange Pi Zero2 (H616), Armbian mainline 7.3.1
(`/home/aruni/orangepizero2/kernel-check/work/linux-7.3.1`). Host-only research;
the board was not touched. Downloads are under `dl/` (one directory per source);
helper scripts under `tools/`.

## 0. Approach and legal framing (stated once)

We reverse-engineer the vendor stack **as hardware documentation**: register map,
init/encode sequences, which parts of the bitstream are produced by hardware versus
software, ISP/scaler programming, DMA buffer layouts. We then write a **clean-room
driver from that documentation**. We do not decompile `libvencoder.so`/`libawh264.so`
and re-emit the result as C: a literal decompile-and-rewrite is a derivative work of
Allwinner's copyrighted code and would be unmergeable; a documented register interface
plus a fresh implementation is exactly how Cedrus (decoder) got upstream. The preferred
observation technique is **black-box register tracing** of the vendor library (run it
against a fault-trapped register window, log every MMIO access), which produces facts
about the hardware without reading or disassembling vendor code. A project that did
precisely this for the H616 in October 2026 (Hardened-BliKVM, see 1.6) has already
published a clean-room H616 encoder register description, so much of the RE is done.

Open-source inputs we may read and (licence permitting) adapt: jemk/cedrus
(GPL-2.0+/LGPL-2.1+), Bootlin's `cedrus/h264-encoding` (GPL-2.0), Allwinner's own
LGPL-2.1 publications (`allwinner-zh/media-codec` 2015, `Allwinner-Homlet/H6-CedarC`
2018), the vendor GPL kernel driver `cedar_ve.c`, linux-sunxi wiki documentation, and
the Hardened-BliKVM register description (its kernel module is GPL-2.0-only; its docs
and Rust code are GPL-3.0, so we may use the documentation as facts but must not copy
GPL-3.0 code into a GPL-2.0 kernel driver).

---

## 1. Prior-art inventory

### 1.1 linux-sunxi wiki (register documentation, A10..H5 generation)

* "Video Engine Registers" (`A10/VE`), "VE Register guide", "Video_Engine",
  "CedarX/Reverse_Engineering": https://linux-sunxi.org/A10/VE ,
  https://linux-sunxi.org/VE_Register_guide , https://linux-sunxi.org/Video_Engine ,
  https://linux-sunxi.org/CedarX/Reverse_Engineering (live site blocks scripted fetch
  with 403/anti-bot; archived text saved to `dl/sunxi-A10_VE.txt`, raw HTML in
  `dl/*.archive.html`).
* Register blocks documented: general (0x000), MPEG (0x100), H264 dec (0x200), VC1
  (0x300), RMVB (0x400), HEVC (0x500), **ISP (0xa00)** and **AVC encoder (0xb00)**;
  `MACC_VE_CTRL` bits 3:0 engine select (0xb = AVC encoder on old parts), bit 6 "Enable
  ISP (1633 and newer)", bit 7 "Enable AVC encoder (1633 and newer)", `VE_VERSION` at
  0xf0 (upper 16 bits). The ISP/AVC tables (0xa00 PIC_SIZE, 0xa04 STRIDE, 0xa08 CTRL,
  0xa0c TRIG, 0xa2c SCALER_SIZE, 0xa30/0xa34 scaler offsets, 0xa38 SCALER_FACTOR,
  0xa70/0xa74 output, 0xa78/0xa7c input/thumb, 0xae0/0xae4 SRAM port; 0xb04
  JPEG/H264 CTRL, 0xb08 QP, 0xb10 ME, 0xb14 IRQ ctrl, 0xb18 TRIG, 0xb1c STATUS, 0xb20
  BITS_DATA, 0xb50/54/58 MAD/residual/header-bit statistics, 0xb80..0xb90 VLE
  start/end/offset/max/length, 0xba0/0xba4 ref, 0xbb0/0xbb4 rec, 0xbb8/0xbbc sub-pixel
  "small luma", 0xbc0 MB_INFO, 0xbe0/0xbe4 SRAM port) are reproduced in
  `dl/sunxi-A10_VE.txt` lines 2422-2900.
* Known VE versions (0xf0 >> 16): A10 0x1623, A20 0x1625, A33/H3 0x1680 (H3 family is
  "0x1633 and newer" for the new enable bits), V3s/S3 0x1681, H5 0x1718. **H6 and H616
  are not on the wiki** — see 3.4 for what we established.

### 1.2 jemk/cedrus (Jens Kuske, 2013-2015) — the original userspace RE encoder

* https://github.com/jemk/cedrus (17 commits; `h264enc/` added 2014-01-11, last encoder
  commit 84c5e373d7 2015-01-18 "Add NV16 input"). Clone: `dl/jemk-cedrus/`.
  `common/ve.c`+`ve.h` are LGPL-2.1+ (register names/offsets, engine select via
  `/dev/cedar_dev` mmap); `h264enc/h264enc.c` is the GPL PoC encoder.
* Programs: A10/A20 era (engine select `0x0013000b`), with the H3 fix (version >=
  0x1633 needs `0x001300C0 | engine`) carried in forks (uboborov/h264_encoder_H3,
  danielkucera/FFmpeg `cedrus264`, avafinger ffmpeg builds, gtalusan/gst-plugin-cedar).
  Limitations: I/P only, constant QP, NV12/NV16 only, SPS/PPS/slice header composed in
  software and pushed through the hardware bit writer (0xb20/0xb18).
* Catalogue of all the H3-era forks with commentary: hataketsu/h3-cedar-h264-encode
  `RESEARCH.md` (2026-06, https://github.com/hataketsu/h3-cedar-h264-encode).

### 1.3 Bootlin / Paul Kocialkowski

* Blog, 2023-11: "Open-source Linux kernel support for the Allwinner V3/V3s/S3 H.264
  video encoder" https://bootlin.com/?p=17914 — kernel branch
  https://github.com/bootlin/linux/tree/cedrus/h264-encoding (top commit
  4e9497947c56, 2023-11-10 "media: cedrus: Add support for H.264 encoding on the
  V3/V3s/S3", preceded by "Add encoder infrastructure" 11bfd77ae1 and "Rework the driver
  in preparation for encoding support" cc8f8edb44), userspace tool
  https://github.com/bootlin/v4l2-cedrus-enc-test. Sources saved in
  `dl/bootlin-cedrus-h264enc/` (`cedrus_regs.h` 39 KB with full ISP/AVC field
  definitions; `cedrus_enc_h264.c` 44 KB). Features: CABAC, I/P, direct QP controls
  only; **no rate control, no ISP scaling/CSC**, headers written by the driver via the
  bit writer. Architecture: one platform device, shared M2M device, **two video nodes
  (decoder + encoder)** sharing the single half-duplex engine. Only the V3s variant has
  the encode capability; Bootlin says other generations have "different (yet rather
  similar)" encoders. Not submitted upstream because no stateless-encoder uAPI exists.
  Issue #1 on the test tool (2024-01, "H616 Cedrus Encoder") shows an Orange Pi Zero2
  user failing at opening the media device — nothing H616-specific was attempted.
* Talks: FOSDEM 2024 "V4L2 Stateless Video Encoding: Hardware Support and uAPI"
  (https://archive.fosdem.org/2024/events/attachments/fosdem-2024-3090-v4l2-stateless-video-encoding-hardware-support-and-uapi/slides/22199/v4l2-stateless-video-encoding_rGq1vIt.pdf
  , saved `dl/slides/`), Linux Media Summit 2025 "V4L2 Stateless Video Encoding uAPI"
  (https://hverkuil.home.xs4all.nl/summit2025/Paul%20Kocialkowski%20-%20Stateless%20Video%20Encoding%20uAPI.pdf),
  Linux Media Summit 2026 (Nice, 2026-05-26, 60-minute slot) "V4L2 Stateless Video
  Encoding uAPI Progress Update"
  (https://paulk.fr/talks/2026-linux-media-summit/2026-linux-media-summit-v4l2-stateless-video-encoding-uapi-progress-update.pdf).
  The PDFs use CID fonts; no text extractor is installed on the host (no pdftotext /
  pypdf), so they were summarised from search snippets and the event pages.
* lore thread opening the uAPI discussion (2023-07):
  https://lore.kernel.org/linux-media/ZK2NiQd1KnraAr20@aptenodytes/ (lore is behind an
  Anubis proof-of-work wall for scripted fetch; read it interactively).

### 1.4 Status of the V4L2 encoder uAPIs (judgement)

* **Stateless encoder uAPI: still not merged (as of 2026-11).** RFCs: Collabora
  Andrzej Pietrasiewicz "H.264 stateless encoder RFC 0/6" 2023-11-16 (Hantro H1 on
  STM32MP25, GStreamer `v4l2slh264enc`) https://lwn.net/Articles/951733/ ; Hugues Fruchet
  VP8 H1 stateless encoding RFC 2023-10; Marco Felsch (Pengutronix) "VC8000E H.264 V4L2
  Stateless Encoder" RFC 2025-05-02 https://lwn.net/Articles/1020012/ ("uAPI handling
  still needs to be figured out"). Media Summit 2025 recap (Collabora,
  https://www.collabora.com/news-and-blog/blog/2025/06/23/linux-media-summit-2025-recap/):
  direction is a **hybrid — stateless encoding via compound controls + requests, paired
  with a stateful rate controller implemented in the kernel**, ideally one shared C
  implementation across drivers. 2026 summit had a progress update; no merged uAPI.
* **Stateful encoder uAPI: stable and documented**
  (`Documentation/userspace-api/media/v4l/dev-encoder.rst`), used by mtk-vcodec-enc,
  amphion, wave5, etc. GStreamer `v4l2h264enc` and FFmpeg `h264_v4l2m2m` consume it.
* Judgement: for the Cedrus VE the kernel must compose headers (hardware bit writer)
  and choose per-frame QP anyway, so a **stateful M2M encoder with in-kernel rate
  control is the mergeable route today**, and the RC/header code is exactly what the
  envisaged hybrid stateless API would also need in-kernel. Design the engine layer
  (Bootlin's `cedrus_engine` split) so the uAPI front end can be swapped later. Expect
  maintainers (Hans Verkuil, Nicolas Dufresne, Paul Kocialkowski — Cedrus co-maintainer)
  to ask that question; have the answer ready. Note the two independent 2025-2026
  stateful implementations for this very engine family (1.6, 1.7) as evidence of demand.

### 1.5 Allwinner's own published sources

* Vendor kernel driver `cedar_ve.c` (GPL-2.0), branch `orange-pi-5.4-sun50iw9`
  (used by Orange Pi's "current" images for H616; `orange-pi-4.9-sun50iw9` is "legacy";
  the `orange-pi-6.1-sun50iw9` branch has **no** cedar driver — only mainline Cedrus
  in `drivers/staging/media/sunxi/cedrus`). Path `drivers/media/cedar-ve/` (hyphen):
  `cedar_ve.c` (sha256 bf869bc5…ebe8b), `cedar_ve.h` (2606aca4…63d4f), saved in
  `dl/vendor-cedar_ve-5.4-sun50iw9/` with the vendor `sun50iw9.dtsi`.
  Facts it yields: compatible `allwinner,sunxi-cedar-ve`; it `io_remap_pfn_range`s the
  whole 0x01c0e000 register window into the process (uncached), i.e. **the blob programs
  registers directly**; ioctl ABI enum (`IOCTL_ENGINE_REQ/REL`, `IOCTL_WAIT_VE_DE`
  (decoder IRQ), `IOCTL_WAIT_VE_EN` (encoder IRQ), `IOCTL_WAIT_JPEG_DEC`,
  `IOCTL_RESET_VE`, `IOCTL_SET_VE_FREQ` (100..900 MHz), `IOCTL_GET_IOMMU_ADDR`/
  `IOCTL_MAP_DMA_BUF` for dma-buf → IOMMU address, `IOCTL_FLUSH_CACHE_RANGE`,
  `IOCTL_POWER_SETUP/SHUTDOWN` via PRCM 0x258/0x264); IRQ handler: with mode-register
  bit 7 set it treats the IRQ as **AVC encoder** (status 0xb1c & 0xf, enables 0xb14 &
  0x7), bit 6 alone as ISP (0xa10/0xa08), bit 5 as JPEG decoder at 0xe00 (sun50i),
  else decoder by bits 3:0; probe clears syscon bit 0 and syscon+4 bit 24 ("give SRAM
  to VE"); clocks `bus_ve`,`ve`,`mbus_ve`; reset `RST_BUS_VE`; DT: IRQ GIC_SPI 93,
  `iommus = <&mmu_aw 3 1>` plus a second node `ve1` with `<&mmu_aw 2 1>` ("just use to
  add iommu master" — the VE has two IOMMU masters, matching mainline's H6 fix).
* `allwinner-zh/media-codec` (2015, **LGPL-2.1**): partially open CedarX. Contains
  source for the encoder *framework* (`sunxi-cedarx/SOURCE/vencoder/vencoder.c`,
  `venc_device.c` dlopens `libcedar_vencoder.so` — the codec itself was a blob) and,
  importantly, Allwinner's own **`video_enc_reg.h`** (H264ENC_* register offsets
  0x00..0x40: PICINFO, PARA0/1/2, MEPARA, INT_ENABLE, STARTTRIG, STATUS, PUTBITSDATA,
  OVERTIMEMB, CYCLICINTRAREFRESH, RC_INIT, RC_MAD_TH0..3, RC_MAD_SUM, bitfield structs)
  and `common/ve.c`. Clone: `dl/allwinner-zh-media-codec/`.
* `Allwinner-Homlet/H6-CedarC` (2018-03-29, commit d92ffcb, **LGPL-2.1**): the
  vendor's H6 libVE source (`ve/veAw/veAw.c`, `ve/include/veAwTopRegDef.h`): top-level
  register bitfield structs (mode select, reset incl. `encoder_reset`, status, counters,
  SRAM port, output format), the IC-version algorithm (`0xf0`; if zero, 64-bit
  `(0xe0 << 32) | 0xe4`, H6 = `0x3101000012010`, default VE freq 552 MHz), and the
  per-chip policy table (`sole_venc`, lock bits). Clone: `dl/Allwinner-Homlet-H6-CedarC/`.
  No encoder codec source.
* libcedarc mirrors: aodzip/libcedarc (2020-06-01, from the Lindenis V536 SDK;
  CedarC-v1.1.9 branch, May 2017) and CalvinXu17/libcedarc (2023-05-22, A133/sun50iw10
  build with `libvenc_codec.so`). Both contain headers (`include/vencoder.h` — full
  encoder API incl. CBR/VBR/AVBR, ROI x8, cyclic intra refresh, SVC skip, long-term ref,
  profile/level, VUI, JPEG/EXIF, VP8, H265) and blob `.so` files for many ABIs. No
  licence file. Clones: `dl/libcedarc-aodzip/`, `dl/libcedarc-CalvinXu17-a133/`.
* Allwinner H616 brief (https://www.allwinnertech.com/uploads/pdf/20200409170709ca.pdf):
  H.264 encode BP/MP/HP, up to 4K@25, CBR/VBR (as summarised by BliKVM).

### 1.6 Hardened-BliKVM (woffko, 2026-10) — the H616 encoder *has been* clean-room RE'd

* https://github.com/woffko/Hardened-BliKVM (repo GPL-3.0; `kernel/hardened-blikvm-ve/`
  is GPL-2.0-only). BliKVM v4 is an **H616** board on Armbian 5.19.4. Docs saved in
  `dl/blikvm-docs/`: `h616-hardware-h264-feasibility.md` (9 KB),
  **`h616-ve-h264-encoder.md` (134 KB: sources, register maps, lab method, full lab
  record, "The H616's register description")**, `h616-ve-encoder-driver-v1.md`.
* Method (their "Clean room" section): read open sources; run the vendor
  `libvencoder.so` (aodzip glibc aarch64 build, sha256 68b7908b…9aa74) **without an
  engine**, against a fault-trapping stand-in register window with made-up buffer
  addresses, on the board, as an unprivileged user; log every MMIO access; never
  disassemble. Their `tools/ve-trace` is the tracer.
* Key hardware facts established on H616 (all confirmed on real hardware):
  * `0xf0` reads 0; `0xe0 = 0x00033010` (decoder IP), `0xe4 = 0x00012011` (encoder IP)
    → composite `0x3301000012011`. H6 is `0x00031010/0x00012010`. **H616 encoder is one
    revision after H6**; the vendor library drives H5/H6 identically and the H616 engine
    accepted that programming. (Independently, codebutler/rgsp-cast reports IC version
    `0x3301000012011` on the H700/"sun50iw9" Anbernic RG SP.)
  * Engine select: **new form only** — mode reg `0x000` bits 7 (encoder) and 6 (ISP)
    with decoder field 7, after pulsing `0x004` bit 24 (encoder reset); reads
    `0xc0000007` at power-on, `0xc00000c7` selected. Old `0x0013000b` form does nothing.
  * Register layout of 0xa00/0xb00 is the **V3s (Bootlin) map**; writable-bit masks per
    register tabulated (V1.5). Differences from V3s/H3: all **encoder-block address
    registers (0xb60, 0xb80/84, 0xb9c, 0xba0..0xbc8) take `addr >> 8` (units of 256
    bytes)**; ISP input addresses 0xa78/0xa7c/0xa80 stay byte addresses; `0xa00`/`0xa2c`
    hold the *visible* size in units of 8 px (1920x1080 → 240 x 135) rather than
    macroblocks; extra `0xa14` stride copy; `0xb08` gets bit 27 and no chroma QP offset;
    `0xb10 = 0x00011000`; `0xb8c` counts in 65536-bit units; `0xb3c` (4th MAD
    threshold) absent; the stream end 0xb84 is honoured (engine stalls with status bit
    1, writes nothing past it).
  * Timing (engine, trigger→IRQ): 1920x1080 I 7.0 ms / P 7.2 ms; 1280x720 3.1/3.3 ms;
    independent of QP and CPU load. A frame can be re-encoded deterministically against
    the same reference (they run 2 passes/frame for RC within 33 ms).
  * Quality: within ~0.2 dB PSNR of x264 ultrafast at 2.5-8 Mbit/s on their sequences;
    worse on fast-scrolling text (motion search window ≈16 px horizontal, 40 up, 8-12
    down; "wide" mode bit 4 of 0xb10 reaches 36 px down).
  * Limits: P frames need width ≥ 13 MB; their driver caps at 1920x1088 (not a hardware
    limit; T527 does 4K with a 0xbc4 line buffer).
  * Software side of the vendor stack: SPS/PPS/slice headers composed by the library and
    pushed through the bit writer; **per-frame QP decided by the library** (with the
    hardware RC assist regs 0xb2c/0xb30-38, a 0xb9c RC buffer, and statistics
    0xb50/54/58 read back); one reference, baseline/main/high differ only in headers
    and the CABAC bit.
* Their driver (`ve_enc.c`, char device, GPL-2.0-only, 5.19, no IOMMU, no V4L2) is a
  design reference for buffer sizes and the frame sequence, not something we copy.

### 1.7 Other 2024-2026 efforts

* **matheusants/sunxi-venc-t527** (2026-05, no licence file; SPDX GPL-2.0 headers):
  https://github.com/matheusants/sunxi-venc-t527 — stateful **V4L2 M2M H.264 encoder**
  (`/dev/video2`) for the T527 (sun55iw3, Cedrus `sun55i-a523` family) on the BSP 5.15
  kernel, register values "verified against vendor libvenc_h264.so" by register trace;
  shares the VE with Cedrus via an exported semaphore + IRQ dispatch hack; up to 4K
  (0xbc4 line buffer for width > 2048); 1080p ≈ 81 fps, 4K ≈ 27 fps at 792 MHz;
  leaky-bucket RC in kernel; GStreamer/FFmpeg/VAAPI (libva-v4l2-request) integration.
  Its `sunxi_venc_regs.h` shows the T527 needs `VE_CTRL = 0xc01300c7`, `VE_MODE(0x004)
  = 0x100` and six "init" registers (0x1c/0x30/0x40/0x80/0x84/0x88) that on H616 are
  simply the power-on defaults BliKVM read back. Clone: `dl/sunxi-venc-t527/`.
* **"sasa" patch** (Armbian forum topic 26551, 2025-09-29): `linux-6.12.28-cedrus-enc.patch`
  adds **JPEG and H.264 stateful encoding to Cedrus** (GStreamer `v4l2h264enc`,
  `v4l2jpegenc`), tested T113 (JPEG) and A40 (JPEG+H264), V3s confirmed by piernov
  (2025-11) with an extra capabilities patch; author states it does **not** work on
  H616/T507 ("encoders were updated"), which we now know means the `>>8` addressing and
  size units, not a new register map. Attachments need a forum login
  (`dl/armbian-sasa-cedrus-enc/README.txt`); ask the user to download them.
  https://forum.armbian.com/topic/26551-video-encoder-using-mainline-kernel/
* **carroarmato0/allwinner-cedar-tools** (2026-06): https://github.com/carroarmato0/allwinner-cedar-tools
  — H618 (TrimUI) tools driving the vendor libs via dlopen; `docs/cedar-encoder.md`
  (saved `dl/allwinner-cedar-tools-cedar-encoder.md`) documents the vendor library
  stack on sun50iw9 Linux: `libvencoder.so` → `libvenc_h264.so`, `libvenc_jpeg.so`;
  `libVE.so` (opens `/dev/cedar_dev`), `libMemAdapter.so` (ION); notes that on that
  H618 build bitrate control returned -1 (content-driven VBR, ~8 Mbit/s ceiling,
  30 fps at 720p). Useful as a **vendor reference harness** (section 4.6).
* **codebutler/rgsp-cast** (2026-08, GPL-3.0): Anbernic RG SP (H700, sun50iw9),
  vendor Cedar via Rust; confirms **ISP RGB→YUV conversion and scaling in hardware**
  on this generation, H.264 Main L4.1; its `scripts/extract-vendor-libs.sh` pulls the
  CedarC libs out of a pinned TrimUI firmware image.
* Radxa A733 issue (newer VE2 generation, separate `cedar_dev_ve2` IRQ): shows the
  vendor stack moving to dma-heap + IOMMU; not our generation.
* Older: libv/cedarx_h264_encoder, ebutera/cedar-h264enc, rosimildo/videoenc,
  Unturned3/h264enc_demo (V3s + libcedarc on mainline 5.19), uboborov/sunxi-cedar-mainline
  (`/dev/cedar_dev` char driver for mainline, CMA), aodzip/cedar (CedarX-compatible
  mainline driver, H6 BSP based). Armbian topic 50617 (2025-03, Zero 2W): decode works
  on H618 with Cedrus + v4l2-request, no encoder.

---

## 2. Blob acquisition and first-pass static look

### 2.1 What exists and what we fetched (all from public GitHub; nothing executed)

| File | Origin | sha256 | Notes |
| --- | --- | --- | --- |
| `dl/libcedarc-aodzip/library/toolchain-sunxi-aarch64-glibc/libvencoder.so` | aodzip/libcedarc e4246be | `68b7908be9bbf4849f9e9f205aa745a973b7bf4c55bf284372a88fdf0dd9aa74` | aarch64 glibc, stripped, 1.0 MB, monolithic (H264+H265+JPEG+VP8 encoders in one). NEEDS libVE, libMemAdapter, libcdc_base. "CedarC-v1.1.9". **The blob BliKVM traced**; knows H3/V3s/H5/H6 (0x12010) but *not* 0x12011. |
| `…/toolchain-sunxi-aarch64-glibc/libVE.so` | same | `83159cd2b980015eeca4021f6b2739ca5542be4705e3f38cc39fcdac2e530199` | opens `/dev/cedar_dev`, reads 0xf0 then 0xe0/0xe4 |
| `dl/libcedarc-aodzip/library/alp50_64/{libVE,libvencoder,libawh264}.so` | same | `1067671b…6d94f`, `3d775d95…097eb`, `449edf72…e14a4` | Android (bionic) aarch64; `libawh264.so` is the **decoder** plugin, not the encoder |
| `dl/libcedarc-CalvinXu17-a133/library/toolchain-sunxi-aarch64-glibc/libvenc_codec.so` | CalvinXu17/libcedarc e68d4a7 | `eb7aa183530370ac068dd98067cb13254c3a8afff3fff3754d6c8f36fe6537f8` | newer split build (A133/sun50iw10): 255 exported funcs incl. `h264_config_registers`, `SetH264RegVer1/Ver2`, `EncIspFunction`, `SetIspRegister`, `EncAdapterPrintEncReg/IspReg/TopVEReg`, `h264RoiQpMap`, `init_dynamicMe`, `init_temporalfilter`, `H264EncMotionDetect`, `switch_T_SVC_bitrateRatio`, `init_rc_param`, `h264InitSpsPps`, `initVUI` — a free function-level map of the encoder's software stages. Separate `libvenc_base.so` dependency. |
| `…/aarch64-linux-gnu/libVE.so` (same repo) | same | `3879355d…7b789` | Android build **with DWARF debug_info, not stripped** (`frameworks/av/media/libcedarc/ve/veAw`) — only the VE keeper, equivalent to the LGPL H6-CedarC source; do not need to read it. |
| radxa/allwinner-debian `packages/arm64/libcedarc/libcedarc-dev_{1,2,3}.0.0_arm64.deb` | https://github.com/radxa/allwinner-debian | not fetched | Tina 5.0 / A733 (VE2) generation — wrong engine, skip. |

**Not freely obtainable from Orange Pi's GitHub:** no `libcedarc` package exists in
`orangepi-xunlong/orangepi-build` for sun50iw9 (code search finds only `libcedrus`
and RK packages), and the `orangepi-xunlong/libcedarc` repo does not exist. The only
public **sun50iw9-specific** Linux/glibc encoder blobs (`libVE.so`, `libvencoder.so`,
`libvenc_h264.so`, `libvenc_jpeg.so`, `libMemAdapter.so`) are inside the **TrimUI
Brick/Smart Pro (H618) stock firmware**, which rgsp-cast and allwinner-cedar-tools
extract from the vendor's public download. That is the vendor's own firmware, publicly
distributed, used only locally as a black-box reference — a defensible position, but
it is a user decision; we did not download it. Android H616/H618 SDK blobs
(Cathgao/H618-Android12-patches shows the HAL chain is 32-bit bionic) are unsuitable.

### 2.2 First-pass static look (host, binutils only)

* All blobs: `readelf -h` → ELF64 AArch64; stripped except the Android libVE.so.
* `libVE.so` strings: `/dev/cedar_dev`, `/dev/googlevp9_dev`, `/dev/sunxi_soc_info`,
  "can not get the ve version, both 0xf0 and 0xe0 is 0" — confirms it mmaps the VE
  window via `/dev/cedar_dev` (vendor driver maps 0x01c0e000) and the 0xf0/0xe0/0xe4
  version scheme.
* `objdump -d | grep` for `str w, [x, #imm]` with imm in 0xa00..0xbff on
  `alp50_64/libvencoder.so`: direct stores to 0xaf8, 0xb60, 0xb80, 0xb84, 0xb8c,
  0xb90, 0xb94, 0xb98, 0xb9c, 0xba0, 0xba4, 0xba8, 0xbb8 (x6), 0xbd0-0xbec; on
  `libvenc_codec.so`: 0xa3c, 0xb38, 0xb88, 0xba8, 0xbe0 (x6: the SRAM port). Most
  register writes go through a base-plus-variable path, so immediate-offset grepping
  under-counts, but it already confirms **direct MMIO programming of the 0xa00 ISP and
  0xb00 AVC blocks** and the existence of registers beyond the V3s map (0xb94/0xb98,
  0xbd0-0xbec, 0xaf8, 0xa3c).
* VE base on H616: `0x01c0e000` (mainline `sun50i-h616.dtsi` `video-codec@1c0e000`,
  reg length 0x2000; vendor DT the same base). Encoder block at VE+0xb00, ISP at
  VE+0xa00 — unchanged since A10.
* RE tooling on the host: **not installed**: Ghidra (`ghidra`, `ghidraRun`,
  `analyzeHeadless`), radare2/rizin/Cutter, retdec, pdftotext/poppler. Installed:
  `objdump`, `aarch64-linux-gnu-objdump`, `readelf`, `binwalk`, `gh`, `git`, python3.
  To install (no sudo for the agent): `ghidra` (or `rizin` + `cutter`), `poppler-utils`
  (pdftotext), `qemu-user-static` (if we ever want to run the aarch64 tracer on the host
  — BliKVM chose not to), `ffmpeg` with libvmaf, `x264`, `libva-utils`, `v4l-utils`.
  Note the plan's primary RE technique (2.3) does not need a disassembler at all.

### 2.3 Chosen RE technique for the remaining unknowns

Black-box MMIO trace (BliKVM "V2R" method, re-implemented by us in C): load the vendor
library as an unprivileged process on the board, supply our own `VeOps`/`MemAdapter`
tables through its published interface (`veInterface.h`, `memoryAdapter.h`), map a
PROT_NONE page where it expects the registers, and in the SIGSEGV handler open the page,
single-step/breakpoint one instruction, record the access (offset, value, R/W, order),
then close it again. Return a fake "finish" status and length for the IRQ wait. Vary
one input per run (resolution, QP, profile, CABAC, RC mode, ROI, intra-refresh, GOP,
input format, rotation, scaling, forced IDR) and diff the traces. The result is a
register-level description written in our own words. Only for register *meanings* the
trace cannot reveal (e.g., what bit 27 of 0xb08 does) do we fall back to on-engine
A/B experiments with our own lab module.

---

## 3. Hardware facts for the H616 (mainline tree 7.3.1 + vendor sources)

### 3.1 Device tree and resources (`arch/arm64/boot/dts/allwinner/sun50i-h616.dtsi`:264)

```
video-codec@1c0e000 { compatible = "allwinner,sun50i-h616-video-engine";
  reg = <0x01c0e000 0x2000>;
  clocks = <&ccu CLK_BUS_VE>(41), <&ccu CLK_VE>(40), <&ccu CLK_MBUS_VE>(51); clock-names "ahb","mod","ram";
  resets = <&ccu RST_BUS_VE>(5); interrupts = <GIC_SPI 93 IRQ_TYPE_LEVEL_HIGH>;
  allwinner,sram = <&ve_sram 1>; }
```
Our tree carries Jernej Skrabec's 2021 Armbian patches (`arm64-dts-sun50i-h616-add-vpu-node.patch`,
`drv-staging-media-sunxi-cedrus-add-H616-variant.patch`). Upstream, Chen-Yu Tsai's July
2026 series (v3, `20260712030011.3778169-1-wens@kernel.org`; patches 1-4 via media,
5-7 landed in `sunxi/dt-for-7.4`) adds the same compatible (reusing the H6 variant)
**plus `iommus = <&iommu 3>, <&iommu 2>` and `allwinner,sram = <&ve_sram 1>, <&sram_c 1>`**.
The vendor DT confirms two IOMMU masters (`<&mmu_aw 3 1>` for ve, `<&mmu_aw 2 1>` for
"ve1") and maps syscon 0x03000000 and CCU 0x03001000 for the SRAM hand-over/clock pokes
that mainline does through `sunxi_sram_claim()` and the clock framework. H616 IOMMU
(`allwinner,sun50i-h616-iommu`, mainline since 6.11) is present in our dtsi at
`iommu@30f0000` but **not yet attached to the VE node in 7.3.1** — our encoder work
should rebase on the 7.4 DT (or carry the two-line iommus/sram patch) so VE DMA is
confined and 4 GB+ is a non-issue.

### 3.2 Clocks, SRAM, power

* `CLK_VE` parent `pll-ve` (`ccu-sun50i-h616.c`), Cedrus H6 variant `.mod_rate =
  648000000` (vendor H6 default 552 MHz; vendor cedar_ve allows 100-900 MHz;
  Armbian carries `media-cedrus-Increase-H6-clock-rate.patch`). T527 vendor-validated
  encode ceiling was 792 MHz; for H616 we start at 648 MHz and treat the rate as a
  tunable in the parity work.
* SRAM: `ve_sram` section at `sram@1a00000` (`allwinner,sun50i-h616-ve-sram`), with
  SRAM C 0x28000 partially aliasing it; Cedrus claims it via `sunxi_sram_claim()`
  unless `quirk_no_sram`. The encoder uses the same SRAM (the V3s map's internal
  deblock/intra-pred buffers; T527 needs an external line buffer at 0xbc4 only above
  2048 px wide).
* Power: mainline Cedrus does reset+3 clocks with runtime PM; vendor also toggles PRCM
  power switch (0x264) / gating (0x258) on some SoCs (`VE_POWER_MANAGE_VALID`) — not
  needed on H616 under mainline (Cedrus decode already works).

### 3.3 What mainline Cedrus does and does not do

* `cedrus_regs.h` defines only VE_MODE (0x00), VE_BUF_CTRL (0x50), output format,
  VE_VERSION (0xf0) and the MPEG/H264/H265/VP8 decoder blocks. **Nothing at 0xa00 or
  0xb00 is ever touched**; `VE_MODE_DISABLED = 7` is written on stop. The H616 uses
  `sun50i_h6_cedrus_variant` (UNTILED, MPEG2/H264/H265/H265_10/VP8 decode, 648 MHz).
* `cedrus_irq()` (`cedrus_hw.c`:147): cancels the watchdog, fetches the current M2M
  ctx; if none → `IRQ_NONE`. An encoder completion raised on the shared line while
  Cedrus owns the IRQ and has no job would be unhandled → "nobody cared" → line
  disabled. **Any coexistence design must own the IRQ in one place.**
* Cedrus `TODO` (Bootlin branch) explicitly plans the platform/proc/context/engine split
  "to register two different procs (decoder and encoder) … exposing distinct video
  devices" — i.e. the maintainers' intended way to add an encoder is *inside Cedrus*.

### 3.4 VE identification on H616

`0xf0 = 0`; `0xe0 = 0x00033010` (decoder IP), `0xe4 = 0x00012011` (encoder IP);
vendor composite `0x3301000012011` (BliKVM on H616; rgsp-cast on H700). H6 is
`0x3101000012010`. Cedrus does not read these; our driver should log them at probe.

### 3.5 Coexistence options

| Option | How | Mergeable? | Use |
| --- | --- | --- | --- |
| A. Extend Cedrus (Bootlin architecture) | one platform device, one IRQ handler dispatching on mode-reg bit 7 vs decoder engine, shared M2M dev/job queue (half-duplex VE), separate `/dev/videoN` for the encoder, `CEDRUS_CAPABILITY_H264_ENC` on the H616 variant | **Yes** (what maintainers planned) | Phase B/D |
| B. Separate `sunxi-venc` module sharing via exported symbols/semaphore (T527 approach) | second driver `devm_ioremap`s the same window, Cedrus exports a semaphore + IRQ forwarding | No (two drivers on one device, hacks) | Reference only |
| C. Unbind Cedrus, bind a lab/PoC module or UIO | `echo 1c0e000.video-codec > /sys/bus/platform/drivers/cedrus/unbind`, then bind our module (or `uio_pdrv_genirq`) to the same node; CMA/dma-heap buffers | No (lab only) | Phase A |

---

## 4. Engineering plan

### 4.0 Guiding acceptance gate: parity with the vendor blob

Every phase from B onwards is measured against the vendor encoder **on the same board**
(section 4.6). The driver is "done" only when, for each row below, it is as good or
better; where it is not, we must identify the cause (register setting, RC algorithm,
missing feature, clock) and fix it, or document a hardware reason.

| Dimension | Metric | Method | Pass |
| --- | --- | --- | --- |
| Quality | PSNR-Y, SSIM, VMAF vs source at matched bitrate (±3 %), per sequence | 4+ sequences (synthetic: `smptebars`/`testsrc2` scroll; real: xiph derf 1080p `crowd_run`, `park_joy`, `in_to_tree`; 720p `four_people`/`johnny`; a desktop-scroll capture), 300 frames, at 1.5/2.5/5/8 Mbit/s and CQP 22/28/34, GOP structures the blob supports (IPPP… with IDR period 30/60/∞; "smart P"/long-term-ref if the blob exposes them; B frames only if the blob does) | ≥ blob VMAF and ≥ blob PSNR − 0.1 dB on every sequence/rate; investigate any miss |
| Performance | encode fps (sustained), per-frame latency trigger→IRQ and queue→dequeue (p50/p99), CPU % during encode | 1080p30 live loop for 10 min; 720p; and the blob's maximum (4K@25 per brief, if the blob accepts it) | fps ≥ blob; p99 latency ≤ blob; CPU ≤ blob |
| Features | profiles BP/MP/HP (CABAC), levels, RC modes CQP/CBR/VBR(AVBR), intra-refresh (0xb28), ROI (0xbcc-0xbdc, 8 regions per `vencoder.h`), ISP input (NV12/NV21/YUV420P/YUV422/YUYV/ARGB, scale, rotate, crop), JPEG encode (STARTTRIG mode 1) | feature matrix enumerated with the blob via `VideoEncSetParameter` and `v4l2-ctl --list-ctrls` for ours | every blob feature that the hardware implements is present (software-only blob features may be matched in userspace) |
| Stability | 12 h soak at 1080p30 with periodic IDR, resolution changes, start/stop 1000x, decode+encode interleaving with Cedrus, timeout/reset recovery | `v4l2-ctl`/GStreamer loop + dmesg watch | zero errors, no leaks (`/sys/kernel/debug/dma_buf`, CMA free), no IRQ storms |

Blob-side steps known to be **software** (so we must match/beat them algorithmically,
not by register copying): SPS/PPS/slice-header syntax (library composes, hardware bit
writer emits), per-frame QP / rate control (library; hardware only provides MAD
statistics and thresholds), GOP decisions and IDR insertion, reference management
(one or two refs), ROI → QP-map preparation, scene-change/"motion detect" heuristics
(`H264EncMotionDetect`), temporal-filter/dynamic-ME parameter selection
(`init_temporalfilter`, `init_dynamicMe`), VUI/SEI generation. Hardware does: intra/
inter prediction and search within its window, transform/quant, CAVLC/CABAC entropy
coding of slice data, deblocking, reconstruction, sub-pixel planes, ISP CSC/scale/
rotate, statistics.

### 4.1 Phase A — userspace/lab PoC on H616 (2-4 weeks)

Goal: prove the full register sequence encodes decodable I and P frames on *our*
board, and capture vendor traces for everything the V3s map does not explain.

1. Kernel side for the lab: a minimal GPL-2.0 lab module bound to the VE node after
   unbinding Cedrus (clocks/reset/SRAM/IRQ as `cedrus_hw.c`; ioctls: alloc dma-buf from
   CMA/dma-heap, read/write register, wait IRQ; log `0xe0/0xe4`). Alternatively
   `uio_pdrv_genirq` + `/dev/dma_heap/linux,cma` — simplest, but UIO cannot ack the
   level IRQ in the encoder's 0xb1c/0xb14 registers, so a tiny module is preferred.
   Keep the BliKVM/T527 lesson: **never** let Cedrus and the lab module both hold the
   IRQ.
2. Host-side encoder tool in C (`ve-h264-poc`): implements the H616 hypothesis from
   BliKVM's "register description" (select via bits 7/6 + reset bit 24; ISP 0xa00/
   0xa04/0xa14/0xa2c/0xa08/0xa78-80; stream 0xb88/0xb80/0xb84/0xb8c with `>>8`;
   buffers 0xba0-0xbc4 `>>8`; headers via bit writer with status bit 9 polling;
   PARA0 0 / 0x410; PARA1 QP | bit 8 | stride/48 | bit 27; ME 0x00011000; trigger 8;
   read 0xb90/0xb1c/0xb50-58). Our own SPS/PPS/slice-header writer (constrained
   baseline → main/high), NV12 input, 2 ping-pong recon sets, sub-pixel buffers of the
   V3s sizes, MB-info buffer.
3. MMIO tracer (`ve-trace`) per 2.3, run against the aodzip glibc `libvencoder.so`
   with H6 identity (0x12010) and, if the user approves the TrimUI firmware, the
   sun50iw9 build with the true 0x12011. Trace matrix: CQP vs CBR vs VBR, ROI on, intra
   refresh on, each `VENC_PIXEL_FMT` the H616 accepts (which reveals ISP format codes
   and the RGB CSC path), scaler ratios, rotation, 4K input, GOP/long-term-ref modes,
   JPEG. Output: `docs/h616-ve-encoder-registers.md` (our words, with per-run diffs).
4. Validation: decode PoC output with host ffmpeg and the JM reference decoder
   (`ldecod`), check `ffprobe -show_frames`, PSNR against source; then decode with the
   board's own Cedrus (GStreamer `v4l2slh264dec`/ffmpeg v4l2-request) to prove
   hardware-decodability.
   Exit criterion: 1080p I+P at CQP decodes everywhere, timing ≈ 7 ms/frame, no
   IRQ/watchdog errors, trace-derived register table covers all blob features.

### 4.2 Phase B — kernel V4L2 M2M stateful encoder (6-10 weeks)

* Placement: `drivers/staging/media/sunxi/cedrus/` on top of a rebased Bootlin rework
  (`cedrus_proc.c`/`cedrus_engine.c` split) — files `cedrus_enc.c`, `cedrus_enc_h264.c`
  (new H616 engine variant alongside V3s), later `cedrus_enc_jpeg.c`. Capability
  `CEDRUS_CAPABILITY_H264_ENC` (+ `_JPEG_ENC`) on the H616 variant; variant data for
  address shift (`>>8`), size units (8 px vs MB), ME default, MAD-threshold count. Keep
  the V3s path working (we can't test it; Bootlin/piernov can).
* Device model: second video node (`/dev/videoN`, "cedrus-enc"), OUTPUT queue
  `V4L2_PIX_FMT_NV12`/`NV21`/`YUV420`/`YVU420` (+ `YUYV`/`UYVY`/`RGB32` once the ISP
  codes are traced), CAPTURE `V4L2_PIX_FMT_H264`; `S_SELECTION` crop; stepwise
  framesizes 256x64 … 1920x1088 initially, 4K after the 0xbc4 line-buffer experiment;
  `V4L2_CID_MIN_BUFFERS_FOR_OUTPUT`.
* Controls (stateful encoder class): `V4L2_CID_MPEG_VIDEO_H264_PROFILE` (BP/CBP/MP/HP),
  `_H264_LEVEL`, `_H264_ENTROPY_MODE`, `_BITRATE`, `_BITRATE_MODE` (CQ/CBR/VBR),
  `_BITRATE_PEAK`, `_GOP_SIZE`, `_H264_I_PERIOD`, `_FORCE_KEY_FRAME`,
  `_H264_MIN_QP`/`_MAX_QP`, `_H264_I_FRAME_QP`/`_P_FRAME_QP`, `_CONSTANT_QUALITY`,
  `_H264_LOOP_FILTER_MODE`/`_ALPHA`/`_BETA`, `_H264_CHROMA_QP_INDEX_OFFSET`,
  `_CYCLIC_INTRA_REFRESH_MB` (0xb28), `_PREPEND_SPSPPS_TO_IDR`, `_HEADER_MODE`,
  `_FRAME_RC_ENABLE`, `_MB_RC_ENABLE` (if the MAD thresholds prove usable), VUI
  SAR/timing controls, `V4L2_CID_ROTATE`/`HFLIP` (ISP), ROI via the standard
  `V4L2_CID_MPEG_VIDEO_…` lacks ROI — propose a compound control or defer to the
  stateless-hybrid API.
* In-kernel rate control: start with a proper frame-level RC (e.g. a simplified x264
  ABR/VBV model: complexity from 0xb50 MAD + previous frame bits, QP clamp, VBV
  buffer), optionally **two-pass per frame** (re-encode against the same reference
  when the first pass misses the budget by > X %, cheap at 7 ms/pass) which is how
  BliKVM beats the blob's RC. Expose the hardware MAD thresholds (0xb2c-0xb38) once
  the trace tells us how the blob uses them.
* IRQ/job model: one handler; mode-reg bit 7 → encoder status 0xb1c; watchdog +
  `reset_control_reset` recovery (T527 saw VE wedges on decode↔encode mode switches;
  budget a per-switch encoder reset pulse via 0x004 bit 24 as the vendor does).
* DMA: with the 7.4 DT (`iommus`) use `vb2_dma_contig` behind the IOMMU; recon/
  sub-pixel/MB-info/RC buffers allocated per context with the V3s sizes (BliKVM
  confirms the H616 stays within them).
* Deliverables: driver, dt-bindings update (none needed beyond the 7.4 series), tests
  (`v4l2-compliance -d /dev/videoN` must pass), documentation in `Documentation/`.

### 4.3 Phase C — userspace integration (2-3 weeks)

* GStreamer `v4l2h264enc` (needs `V4L2_PIX_FMT_H264` + stateful controls; verify
  `extra-controls`, `capture-io-mode=dmabuf`, zero-copy from `v4l2src`), FFmpeg
  `h264_v4l2m2m` (check its buffer-count and `-b:v`/`-qp` mapping), libcamera/
  pipewire consumers; a `ve-enc-bench` tool for the parity matrix (4.6).
* Carry fixes upstream to GStreamer/FFmpeg if their stateful encoder clients
  mis-handle our control set (common: `H264_LEVEL` enumeration, `MIN_BUFFERS`).

### 4.4 Phase D — upstreaming (3-6 months of review cycles, part time)

1. Post the Cedrus rework (rebased Bootlin series, co-developed/acked by Paul
   Kocialkowski) first — low-controversy.
2. Post the encoder infrastructure + H616 H.264 engine with the parity numbers from
   4.6 and the register documentation (`Documentation/userspace-api/media/drivers/`
   or in-tree comments as Cedrus does). Cc linux-media, linux-sunxi, Hans Verkuil,
   Nicolas Dufresne, Paul Kocialkowski, Chen-Yu Tsai, Jernej Skrabec, Andre Przywara.
3. Expect the "why stateful?" discussion; answer with 1.4 and offer to port the engine
   layer to the hybrid stateless API when it lands (the in-kernel RC is reusable).
4. Documentation to produce: register map (ours, from traces + experiments), buffer
   layout table, encode sequence, IRQ/status semantics, variant differences (V3s vs
   H616 vs T527), limits (P-frame min width, size units, stream-end behaviour), and the
   RE-provenance statement for each fact (source: open code / trace / experiment).

### 4.5 Test method on our board (future phase; not now)

1. Second SD card A (mainline + our driver) and card B (vendor reference, 4.6). Same
   board, same power, same clock settings where controllable.
2. Inputs: raw YUV sequences in NV12 on tmpfs/eMMC (ffmpeg `-pix_fmt nv12 -f rawvideo`,
   width/height multiples of 16 plus cropped odd sizes like 1366x768 and 1280x719 to
   test cropping), plus a live `videotestsrc`/`v4l2src` loop for latency.
3. Encode with `v4l2-ctl --stream-mmap`/`gst-launch-1.0 … v4l2h264enc` (ours) and
   `vencoderDemo`/`cedar-probe`-style tool (blob). Record per-frame bytes, type, QP (parse
   slice headers), trigger→IRQ time (driver tracepoint/`debugfs`), `perf stat`/`top`
   CPU, `/proc/interrupts`.
4. Decode outputs on the host with ffmpeg (`-c:v h264` software) and the JM reference
   decoder; compute PSNR/SSIM/VMAF (`ffmpeg -lavfi "[0:v][1:v]libvmaf=…;psnr;ssim"`),
   bitrate accuracy, VBV compliance (`ffprobe -show_packets`), syntax conformance
   (`h264_analyze`/JM trace). Also decode with the board's Cedrus to prove hardware
   interop.
5. Soak per 4.0 with `dmesg -w` and CMA/dma-buf accounting.

### 4.6 Running the vendor blob as the A/B reference on the same board

Option 1 (preferred, no proprietary kernel): mainline kernel with our **lab module
exposing a `/dev/cedar_dev`-compatible ioctl/mmap ABI** (the vendor ABI is GPL and
small: ENGINE_REQ/REL, WAIT_VE_EN/DE, RESET_VE, SET_VE_FREQ, MAP_DMA_BUF, FLUSH_CACHE
+ register mmap) plus a `libMemAdapter`-compatible dma-heap shim; run the vendor
`libvencoder.so` stack and Allwinner's `demo/vencoderDemo/EncoderTest.c` (source in the
libcedarc mirrors) against it. Same kernel, same clocks → cleanest A/B. uboborov/
sunxi-cedar-mainline and aodzip/cedar are prior art for such a shim.
Option 2: vendor card — orangepi-build `BOARD=orangepizero2 BRANCH=current` (kernel
`orange-pi-5.4-sun50iw9`, includes `drivers/media/cedar-ve` and ION/dma-heap), with
the sun50iw9 CedarC libs (TrimUI firmware extraction, user decision) and `EncoderTest`.
Record VE clock (`IOCTL_SET_VE_FREQ`), library version string, and the exact
`VencH264Param` used, so the comparison is reproducible.
Either way the blob is used locally as a measurement reference only; nothing of it is
redistributed or read.

### 4.7 Effort summary

| Phase | Calendar | Notes |
| --- | --- | --- |
| A PoC + traces + register doc | 2-4 weeks | de-risked by BliKVM/T527: expect first decodable frame in the first week |
| B kernel driver (H.264, CQP+RC, ISP formats) | 6-10 weeks | includes Cedrus rework rebase, compliance, IOMMU DT |
| Parity work (RC quality, features: ROI/intra-refresh/scaler/4K, JPEG) | 4-8 weeks | iterative against the gate in 4.0 |
| C userspace | 2-3 weeks | parallel with parity work |
| D upstreaming | 3-6 months elapsed | review latency dominated |
| Total | ≈ 5-7 person-months | |

---

## 5. Risks

1. **Register semantics still unknown** on H616: bit 27 of 0xb08, bit 10 of 0xb04
   (0x410 P-frame image), the RC assist registers 0xb2c-0xb38 and the 0xb9c RC buffer,
   0xb94/0xb98 and 0xbd0-0xbec seen in blob stores, the 2nd reference slot
   (0xba8/0xbac), B-slice type, ISP scaler/CSC codes for RGB/YUV422, 4K line buffer
   (0xbc4). Mitigation: the trace matrix in 4.1; the hardware tolerates experiments
   (stays in its buffers, honours stream end).
2. **Blob availability for sun50iw9**: the only public glibc build that knows encoder
   IP 0x12011 is inside TrimUI firmware; the aodzip build (0x12010/H6 path) is what
   BliKVM used and it works on the H616 engine, so the trace can proceed without it,
   but feature probing of what the *vendor* supports on H616 (RC modes, ROI, 4K) may
   need the real build. User decision on firmware download.
3. **ISP dependency**: format conversion/scaling/rotation happens in the 0xa00 ISP stage
   that is only partially documented (V3s map has format/scaler/rotation fields; H616
   adds 0xa14 and uses 8-px units). RGB inputs and the thumbnail path are untraced.
   Mitigation: trace with each `VENC_PIXEL_FMT`; initially expose NV12/NV21/YUV420 only.
4. **Rate control is software** in the vendor stack; parity on quality depends on our
   RC algorithm, not registers. Mitigation: multi-pass per frame (deterministic 7 ms
   passes), MAD statistics feedback, x264-derived model; compare per sequence.
5. **Motion-search window** is narrow (≈16 px horizontal); fast motion/scrolling text
   costs quality regardless of software. Document as a hardware limit; test whether
   0xb48/0xb4c thresholds and 0xb10 bits widen it (BliKVM found bit 4 helps downward
   motion only).
6. **Coexistence with Cedrus**: single half-duplex engine, one IRQ, VE state-machine
   wedges on decode↔encode switches (T527). Mitigation: one driver, serialised job
   queue, encoder reset pulse per job, watchdog + full reset.
7. **SRAM/clock gating differences**: H616 SRAM C aliasing and the second SRAM/IOMMU
   entries only in the 7.4 DT series; clock ceiling for encode unknown (648 vs 792
   MHz). Mitigation: test on 7.4 DT, sweep `CLK_VE`.
8. **uAPI politics**: stateful encoder may be questioned in favour of the pending
   stateless hybrid; mitigation in 1.4/4.4. Worst case the driver lives out of tree in
   Armbian until the uAPI lands, with the engine layer ready to port.
9. **Licensing**: never copy GPL-3.0 (BliKVM) or unlicensed (T527) code into the kernel;
   use them as documentation/behavioural reference only, and record provenance per fact.
   Allwinner LGPL-2.1 headers can inform register names but the kernel code is written
   fresh. The TrimUI/vendor blobs stay out of any repository.
10. **JPEG**: the same AVC block encodes JPEG (STARTTRIG mode 1, `libvenc_jpeg.so`); no
    H616-specific open RE yet (sasa's stateful `v4l2jpegenc` covers T113/A40; recedro/
    jepoc 2014). Treat as a stretch goal after H.264 parity.

---

## 6. Local artefacts

```
dl/jemk-cedrus/                      git clone (h264enc PoC, ve.c/ve.h)
dl/bootlin-cedrus-h264enc/           cedrus_regs.h, cedrus_enc*.c, cedrus_engine.*, cedrus_proc.c, TODO
dl/sunxi-venc-t527/                  git clone (T527 M2M encoder, register trace-derived)
dl/vendor-cedar_ve-5.4-sun50iw9/     cedar_ve.c/.h, flush_cache.S, ve_mem_list.h, sun50iw9.dtsi
dl/allwinner-zh-media-codec/         git clone (LGPL 2015 CedarX: video_enc_reg.h, vencoder framework)
dl/Allwinner-Homlet-H6-CedarC/       git clone (LGPL H6 libVE: veAw.c, veAwTopRegDef.h)
dl/libcedarc-aodzip/                 git clone (headers + blobs; toolchain-sunxi-aarch64-glibc/libvencoder.so is the trace subject)
dl/libcedarc-CalvinXu17-a133/        git clone (A133 split build; libvenc_codec.so symbol list)
dl/blikvm-docs/                      h616-ve-h264-encoder.md (134 KB), feasibility, driver design
dl/allwinner-cedar-tools-cedar-encoder.md   vendor library API/quirks on H618
dl/sunxi-A10_VE.txt, *.archive.html  linux-sunxi register tables (Wayback copies)
dl/slides/                           Kocialkowski FOSDEM 2024, Media Summit 2025/2026 PDFs (text not extractable here)
dl/armbian-sasa-cedrus-enc/          login-wall placeholders; patches need a forum login
tools/html2txt.py, tools/pdftext.py  helpers used above
```
