# Orange Pi Zero2 (H616): hardware video decoding to the chip spec

Date: 2026-11-02. Kernel: Armbian sunxi-7.3 edge (Linux 7.3.1).
Worktree: `/home/aruni/orangepizero2/wt-vdec`, branch `feat/sunxi-h616-vdec-spec`, rebased onto `stonking-orangepizero2` `39853f9` (clean, no conflicts: the upstream 7.4 cedrus H616 commits carry the same content the old patches had). Commits `cb3826a` (series), `4ce548b`, `d92a201` (board-found fixes). Nothing has been pushed. **Board results: §9.**
Scope: decode only. The encoder (`harness/research/ve-encoder/`) and the GPU rows of `docs/spec-checklist.md` belong to other efforts.

## 0. The spec

The official Orange Pi Zero2 page (http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/details/Orange-Pi-Zero-2.html, fetched over HTTP on 2026-11-02) and the H616 User Manual v1.0 §2.2.4 / §4.4.1 agree. UM §4.4.1 adds the maximum sizes and bitrates:

| Item | Spec | UM §4.4.1 maximum |
|---|---|---|
| H.265 | Main10@L5.1, 4K@60 or 6K@30 | 6144x4320, 150 Mbit/s |
| VP9 | Profile 2, 4K@60 | 8192x8192, 60 Mbit/s |
| AVS2 | JiZhun 10-bit, 4K@60 | 8192x8192, 60 Mbit/s |
| H.264 | BP/MP/HP@L4.2, 4K@30 | 4096x2048, 60 Mbit/s |

UM §4.4.1 also lists the following, with no spec row but covered by the project rule that every hardware capability must work: H.263 BP, VP8, MPEG-4 SP/ASP@L5, MPEG-1/2, VC-1 SP/MP/AP, Xvid, Sorenson Spark (all 1080p@60), AVS/AVS+ JiZhun (1080p@60), and JPEG (16384x16384, 45 MPPS).

## 1. Hardware inventory

**There is no Hantro G2 on the H616.** VP9, AVS2 and 10-bit HEVC all run inside the single cedar video engine at 0x01C0E000.

| Question | Answer | Source |
|---|---|---|
| Decode blocks in the memory map | Only `VE 0x01C0 E000–0x01C0 FFFF (8K)` and `VE SRAM 0x01A0 0000–0x01BF FFFF`; no 0x01C00000 block | UM §3.1 Memory Mapping |
| CCU clocks/resets | Only `VE_CLK_REG 0x0690` (PLL_VE, M divider) and `VE_BGR_REG 0x069C` (gate bit 0, reset bit 16), plus MBUS gate bit 1 at 0x804. The H6's VP9 clock and gate (0x6C0/0x6CC) are absent | UM §3.3.5.62/63; mainline `ccu-sun50i-h616.c` has no vp9 clock, `sun50i-h616-ccu.h` has no `RST_BUS_VP9` |
| IOMMU masters | 0 DE, 1 DI, **2 VE_R, 3 VE**, 4 and 5 reserved, 6 G2D. The H6's G2 sat on a master that is reserved here | UM §3.12, Table 3-8; mainline node `iommus = <&iommu 3>, <&iommu 2>` (Chen-Yu Tsai v3 "Corrected second IOMMU port") |
| VE IRQ | GIC SPI 93 | mainline `sun50i-h616.dtsi` (eabc3c090e81), vendor `sun50iw9p1.dtsi` |
| VE version | `0x0F0` reads 0. The decoder IP at `0x0E0` is 0x00033010 and the encoder at `0x0E4` is 0x00012011, giving a 64-bit id of 0x3301000012011. The H6 is 0x3101000012010 | board read in `harness/research/ve-encoder/dl/blikvm-docs/h616-ve-h264-encoder.md` (l. 436); the vendor libVE `policy_list` has an entry `{0x3301000012011, 0, 0, 624 MHz}`, so this is the H616 entry |
| Vendor `vp9@01c00000 "allwinner,sunxi-google-vp9"` node, IRQ 90, `iommus = <&mmu_aw 2 1>` | A dead copy of the H6 node. It has no module clock (the driver warns `get google_vp9_moduleclk failed`), and `CONFIG_VIDEO_GOOGLE_VP9_DECODER_SUNXI` is unset in every sun50iw9 defconfig (h616/h700/t507, android and dragonboard) | `orangepi-xunlong/linux-orangepi` branch `orange-pi-4.9-sun50iw9`: `arch/arm64/boot/dts/sunxi/sun50iw9p1.dtsi`, `drivers/media/cedar-vp9/google_vp9.c`, `arch/arm64/configs/sun50iw9p1smp_*_defconfig` (copies in `kernel-check/dl-vdec/bsp/`) |
| Where VP9 is decoded | In the VE's **H.265 engine slot** (VE+0x500, `VE_MODE` = 4). VP9 also needs `VE_MODE` bits 31 (rampd) and 30 set, and DDR mode 256-bit | vendor libVE `enableDecoder()` jump table: VIDEO_CODEC_FORMAT_VP9 (0x113) → mode 4. The vendor library for this is `libawvp9HwAL.so` ("AL" = Allwinner's own core; `vecore_*`/`vp9_*_regNN` registers). `libawvp9Hw.so` is the Hantro (`DWL*`) driver for the H6 G2. Jernej Škrabec's driver: "runs VP9 in the H.265 engine slot and register bank" |
| Where AVS2 is decoded | Also the H.265 engine slot (mode 4) | libVE jump table: AVS2 (0x118) → mode 4; `libawavs2.so` register structs `AVS2_*_REG04…REG8C` follow the HEVC/VP9 layout (bitstream 0x40–0x4C, scale-down 0x50–0x58, neighbour 0x60, col-MV 0x78/0x7C, 10-bit 0x84/0x8C) |
| Where AVS/AVS+ and RealVideo are decoded | AVS (0x117) → mode 1 (H.264 engine); RX (0x114) → mode 3 | same jump table |
| Where 10-bit HEVC is decoded | The H.265 engine writes an 8-bit NV12 reconstruction plus a plane holding the 2 low bits of each sample (`VE_DEC_H265_10BIT_CONFIGURE` 0x58C). The secondary (scale-down/rotate) output engine converts it to P010 | vendor H6 CedarC `h265_register.c`; Jernej's "Add P010 output for 10-bit VP9 and H.265" |
| VE clock | Vendor default 624 MHz for the H616 (libVE `policy_list`). Jernej's H616 variant uses 600 MHz. The Armbian H6 variant uses 648 MHz | libVE, `cedrus.c` |
| Vendor userspace with debug info | `libawvp9HwAL.so`, `libawavs2.so`, `libawh265.so` (androidq_64), `libVE.so` in `harness/research/ve-encoder/dl/libcedarc-CalvinXu17-a133/library/` are **not stripped and carry DWARF**, so register bitfield layouts and source line numbers can be recovered | `file`, `pahole`; dumps in `harness/research/vdec/*.pahole.txt` |

**Cross-check from the coordinator's orangepi-build mining** (`harness/research/orangepi-build-mining.md`, vdec rows) agrees with the above. The 5.4 vendor BSP (the production H616 kernel) has no `cedar-vp9`. It declares a second `allwinner,sunxi-cedar-ve` instance at 0x1c0e000 on `mmu_aw 2` (= VE_R, matching mainline `iommus = <3>, <2>`) and gives SPI 90 to G2D. The T527 glibc CedarC `libawvp9HwAL.so` (DWARF, `-O0`) references `AW_SOC_H616`/`AW_SOC_H313`. The vendor 6.1 kernel maps H616 to the H6 Cedrus variant (10-bit capable) at 600 MHz. Conclusion: **the Hantro `sun50i-h6-vpu-g2` path is dropped for H616**. The T527 `libawavs2.so` is stripped (no DWARF), so it cannot cross-check the AVS2 struct layouts; the A133 Android-29 build stays the reference. **Board read (2026-11-02, read-only):** `busybox devmem` 0x01c00000/04/08 = 0x00000000 (a Hantro G2 returns its 0x6732xxxx ID there), while the VE at 0x01c0e0e0/e4 reads 0x00033010/0x00012011 and 0x01c0e0f0 reads 0. With no VP9 clock gate in the CCU there is nothing that could be gating a G2 off: **settled, no G2**; VP9 is the VE's H.265 slot.

How Chen-Yu and Jernej settled VP9 upstream: Chen-Yu's v1 commit message said VP9 "is supposed to" be there. Jernej answered that "manual and all my experiments show VP9 is supported" (https://lkml.iu.edu/2606.1/13282.html, https://lkml.iu.edu/2606.1/12596.html). The merged version (1f24d4307515, 7.4) says "it also includes a VP9 decoder. Support for VP9 will be added separately".

## 2. Per spec item: what is needed and its status

| Item | What is needed | Upstream state | Our state |
|---|---|---|---|
| **H.265 Main10 4K@60** | Cedrus 10-bit already exists (`CEDRUS_CAPABILITY_H265_10_DEC`), but its only uncompressed output was NV12, which holds just the top 8 bits, so it is not bit-exact. AFBC 10-bit (Armbian patch) can only be checked by scanning it out. Needed: P010 through the secondary output. 4K fits the old 4096x2304 limit | Not posted. Jernej's `jernejsk/linux-1` `h616-cedrus` branch (2026-07/10): "Add P010 output for 10-bit VP9 and H.265" | **Pulled in** (rebased). Needs a board run: Main10 conformance + 4K60 fps |
| **H.265 6K@30** | Allow up to 6144x4320 on H616 (UM). The VE width-class bits must be set for every width ≥ 4096 (vendor libVE `VeReset`: width ≥ 0x1000 → bits 21 and 22; ≥ 0x801 → bit 21). The neighbour-info buffer stays 794 KiB (the vendor `libawh265` allocates 0xC6800 at every size). The size fields are 14 bits wide | Nothing anywhere | **Our patch** `media-cedrus-h616-decode-H-265-pictures-up-to-6144x4320.patch`. Needs a board experiment (6K stream; a VE hang would show up as a watchdog timeout) |
| **VP9 Profile 2 4K@60** | New Cedrus VP9 backend (VE H.265 slot): probability buffer layout, hardware symbol counts plus `v4l2-vp9` backward adaptation, segment map, 10-bit P010 | Not posted. Jernej's "media: cedrus: Add VP9 decoding support" (reverse engineered from `libawvp9HwAL.so`). Tested on H616 with FFmpeg: "all profile 2 vectors and 241 of the 305 profile 0 vectors pass" (the failures are resolution changes inside inter frames, an FFmpeg reallocation issue) | **Pulled in**, plus our `select V4L2_VP9` fix. Board run needed. 12-bit (`vp92-2-20-12bit`) is expected to be rejected, since the hardware is 10-bit |
| **AVS2 JiZhun 10-bit 4K@60** | (a) V4L2 stateless AVS2 uAPI: pixel format plus controls for sequence header, picture header, RPS/ref lists, weighted-quant matrices, ALF parameters; (b) a `cedrus_avs2.c` backend in the H.265 slot; (c) a userspace parser and hwaccel (FFmpeg has no native AVS2 decoder, only `libdavs2` and an AVS2 parser) | **Nothing anywhere**: no uAPI, no driver, no userspace | **Not started in code.** Register map extracted from `libawavs2.so` DWARF (`harness/research/vdec/avs2-regs-libawavs2.txt`, 21 registers at VE+0x500+{04…8C}). Plan in §5 |
| **H.264 HP@L4.2 4K@30** | Driver already supports up to 4096x2304. H616 fix: with the 128-bit DDR mode, H.264/VP8 P-frame chroma is corrupt (~22 dB) and luma is bit-exact | Not posted. Jernej "h616: use the 256-bit DDR mode for all codecs" | **Pulled in.** Note: `docs/status.md` says H.264 was bit-exact at 1080p with 128-bit mode, so recheck chroma md5 on P-frame-heavy vectors (CABA2_Sony_E, BA_MW_D) before and after |
| Others in UM (no spec row) | VC-1 SP/MP/AP, MPEG-4 Part 2/H.263/Sorenson Spark | Not posted. Jernej `h616-cedrus` (VC-1) and `h616-mpeg4` | **Pulled in**, with new **non-upstream uAPI**. Userspace only from Jernej's FFmpeg fork |
| AVS/AVS+ JiZhun 1080p, RealVideo, JPEG, Xvid/DivX3 (MS-MPEG4) | AVS+ = H.264 slot (mode 1), RV = mode 3, JPEG = `0xE00` block (`VE_MODE` bit 5) | Nothing upstream or on lists for AVS/AVS+, RealVideo or VE JPEG decode on any sunxi | Not started; listed as follow-ups (§6) |
| DI300 deinterlacer (separate block, IOMMU master 1) | Jernej `h616-deinterlace-v1` / `h616-integration-v1` | Not posted | Not in this decode scope; follow-up |

## 3. Patches added (worktree `wt-vdec`, branch `feat/sunxi-h616-vdec-spec`)

All 29 patches (26 + 3 board-found, rows 27–29) are in `patch/kernel/archive/sunxi-7.3/patches.media/h616-vdec/`, in a new block at the **end** of `series.conf`. It has to be last because it is rebased onto the patched tree, which already contains Armbian's H.265 AFBC, depth filtering, H616 and A523 variant patches. The 24 Jernej commits come from `jernejsk/linux-1` (`h616-mpeg4` head `1ae40d912ab0`, which contains `h616-cedrus`) and keep their authorship. Downloads are in `kernel-check/dl-vdec/jernej/` (untrusted, not executed).

| # | Patch | Origin | Rebase notes |
|---|---|---|---|
| 1 | iommu-sun50i-Allow-page-sizes-multiple-of-4096 | Jernej e2ce16cd1539 | clean |
| 2 | iommu-sun50i-reset-the-sibling-masters-of-a-faulting-master-in-the-IRQ | Jernej 9c48b5cceb7a | clean |
| 3 | media-cedrus-free-MV-col-buffers-in-buf-cleanup | 6eef0dcfa239 | clean |
| 4 | media-cedrus-reject-H-264-HEVC-SPS-larger-than-the-hardware-or-buffers | 735ee0133869 | fuzz only |
| 5–9 | h264 long-term refs / mpeg2 field pictures / VP8 size check / VP8 > 2048 / stride from capture format | e9bd8535bc45 fbce4a9e943b 54ac1265e388 ce2087881d1d 2c3bafca8fc7 | clean |
| 10 | media-cedrus-Add-VP9-decoding-support | a47cb67f9a91 | fuzz only (sits next to the A523 variant) |
| 11 | media-cedrus-Add-P010-output-for-10-bit-VP9-and-H-265 | bfad2e9a00d2 | one hunk hand-merged: kept Armbian's AFBC chroma-address check (noted in the patch) |
| 12 | media-cedrus-Implement-AFBC-YUV420-output-for-VP9 | 6b76b9716d4d | reduced to the VP9 parts, because Armbian's H.265 AFBC patch already adds the mode bits, engine-enable setup, format-set case and sizing (noted in the patch) |
| 13 | media-cedrus-h616-use-the-256-bit-DDR-mode-for-all-codecs | 8cbb2d18143d | fuzz only |
| 14–19 | VC-1: biblio, profile/level ctrls, uAPI, driver, H616 enable, H3/H5/R40/A64/H6 enable | 804dee243be6 … 86e549b6386d | fuzz only |
| 20–24 | MPEG-4 Part 2/H.263/Sorenson: biblio, uAPI, several HW runs per job, driver, H616 enable | 29ee69639b29 … 1ae40d912ab0 | fuzz only |
| 25 | media-cedrus-select-V4L2-VP9 | **ours** | Kconfig `select V4L2_VP9` (otherwise it only links because Hantro=y selects it) |
| 26 | media-cedrus-h616-decode-H-265-pictures-up-to-6144x4320 | **ours** | per-variant `h265_max_width/height` (H616: 6144x4320), `cedrus_max_size()` used by try_fmt/SPS check, width class `>= 4096` |
| 27 | media-cedrus-keep-8-bit-H-265-AFBC-behind-the-linear-capture-formats | **ours, board-found** | with H265_10 on H616 the 8-bit AFBC format became the G_FMT default and GStreamer failed every 8-bit H.265 stream ("Unsupported V4L2 pixelformat AS12"); 8-bit AFBC is now opt-in, 10-bit AFBC stays ahead of P010 |
| 28 | media-cedrus-report-only-the-picture-as-capture-payload | **ours, board-found** | `bytesused` excluded the private 10-bit reconstruction planes (was 40435200 for a 24883200-byte 4K P010 picture). Correct uAPI, but GStreamer writes the whole buffer anyway (raw fdsink dumps still need `CHUNK=40435200`); videometa-aware sinks are unaffected |
| 29 | media-cedrus-reset-the-VE-when-switching-to-or-from-VP9 | **ours, board-found** | with an H.265 and a VP9 stream decoded at the same time, 600/600 H.265 jobs failed "Failed to setup decoding job: -22" (zero slice-padding byte from the bitstream engine); VE reset on every VP9↔other switch, as libVE does |

Skipped because Armbian already has them with identical content: Jernej 0936f56840c6 "Don't CPU map source buffers", ab21a6fdc724 "format filtering", and 16f6b276fbe0 "YUV 4:2:0 AFBC formats" (same fourccs; only his documentation hunk differs).

No DT change was needed. Armbian already carries upstream `eabc3c090e81`: `video-codec@1c0e000` with both IOMMU ports and both SRAM claims. No `config/kernel/linux-sunxi64-edge.config` change either: `VIDEO_SUNXI_CEDRUS=y`, `V4L2_VP9=y`, `SUN50I_IOMMU=y` are already set.

Effect on the H616 variant: it is now its own `sun50i_h616_cedrus_variant`, with MPEG2, H264, H265, H265_10, VP8, VP9, VC1, MPEG4 at 600 MHz, `ve_mode_ddr = BW_256` and `h265_max` 6144x4320. Before, it reused the H6 variant (648 MHz, no VP9). The H6 variant keeps 648 MHz and gains VC-1.

### Compile check
See §7 (filled in from `kernel-check/run-vdec-all.log`).

## 4. Board test plan (as designed; what was actually run and its results are in §9)

### 4.0 Userspace on Ubuntu 26.10 arm64
- `gstreamer1.0-plugins-bad` 1.28.6 has `v4l2codecs`: `v4l2slh264dec`, `v4l2slh265dec`, `v4l2slvp8dec`, `v4l2slvp9dec`, `v4l2slmpeg2dec`, `v4l2slav1dec`. It has no VC-1, MPEG-4 or AVS2 element.
- `ffmpeg` 8.1.2 has **no** v4l2-request hwaccel (FFmpeg PR 20847 is still pending). Its HEVC/VP9 hardware devices are cuda/vaapi/vdpau/vulkan only. It is still useful as the software reference decoder.
- For FFmpeg v4l2-request, including VC-1/MPEG-4 and AFBC/P010 mapping: build Jernej's fork `https://github.com/jernejsk/FFmpeg` branch `v4l2request-mpeg4` (FFmpeg 8.1 + Kwiboo's v4l2request + VP9/AV1 + VC-1 + MPEG-4) natively on the board, see 4.1.
- fluster: `git clone https://github.com/fluendo/fluster` (pure Python 3, no packaging needed). Decoders: `GStreamer-H.265-V4L2SL-Gst1.0`, `GStreamer-VP9-V4L2SL-Gst1.0`, `GStreamer-H.264-V4L2SL-Gst1.0`, `GStreamer-VP8-V4L2SL-Gst1.0`, `GStreamer-MPEG2-V4L2SL-Gst1.0`.

**Proposed package list for `userpatches/customize-image.sh`** (proposal only; this agent did not edit it):
```
apt-get install -y --no-install-recommends v4l-utils gstreamer1.0-tools gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good gstreamer1.0-plugins-bad ffmpeg python3 git
# to build the v4l2-request FFmpeg on the board (or ship it prebuilt later):
apt-get install -y --no-install-recommends build-essential pkg-config libdrm-dev libudev-dev
```
`gstreamer1.0-plugins-good` provides matroskademux/qtdemux, `-bad` provides v4l2codecs and h264parse/h265parse/vp9parse, and `-base` provides videoconvert.

### 4.1 Steps
Pass criteria are inline. Everything runs on the board as a normal user in group `video`, unless marked `sudo`.

```sh
# A. Driver/caps
dmesg | grep -iE 'cedrus|1c0e000|sun50i-iommu'           # "Device registered as /dev/videoN", no SRAM/IOMMU errors
for d in /dev/video*; do v4l2-ctl -d $d --info | grep -q cedrus && V=$d; done; echo $V
v4l2-ctl -d $V --list-formats-out                          # MG2S S264 S265 VP8F VP9F + VC1L, MP4S, H263, SPK (new fourccs)
v4l2-ctl -d $V --list-ctrls-menus                          # vp9_frame_decode_parameters, vp9_probability_tables, hevc_*, h264_*, vc1/mpeg4 ctrls
# capture formats depend on the OUTPUT format; check 10-bit P010 exposure:
v4l2-ctl -d $V --set-fmt-video-out=pixelformat=S265,width=3840,height=2160 --list-formats   # 8-bit: NV12 (+ AFBC)
gst-inspect-1.0 v4l2codecs | grep -E 'v4l2sl'               # v4l2slh264dec v4l2slh265dec v4l2slvp8dec v4l2slvp9dec v4l2slmpeg2dec
cat /proc/interrupts | grep -i 1c0e000                      # note the count (IRQ check baseline)

# B. Bit-exactness (fluster, GStreamer). Vectors are fetched by fluster itself:
git clone --depth 1 https://github.com/fluendo/fluster && cd fluster
./fluster.py download JCT-VC-HEVC_V1 VP9-TEST-VECTORS VP9-TEST-VECTORS-HIGH JVT-AVC_V1 JVT-FR-EXT
./fluster.py run -d GStreamer-H.265-V4L2SL-Gst1.0 -ts JCT-VC-HEVC_V1 -j1 -t 120     # incl. the 11 Main10 vectors (P010)
./fluster.py run -d GStreamer-H.265-V4L2SL-Gst1.0 -ts JCT-VC-HEVC_V1 -j1 -tv WP_A_MAIN10_Toshiba_3 WP_MAIN10_B_Toshiba_3 DBLK_A_MAIN10_VIXS_4 INITQP_B_Main10_Sony_1 WPP_A_ericsson_MAIN10_2 WPP_B_ericsson_MAIN10_2 WPP_C_ericsson_MAIN10_2 WPP_D_ericsson_MAIN10_2 WPP_E_ericsson_MAIN10_2 WPP_F_ericsson_MAIN10_2 TSUNEQBD_A_MAIN10_Technicolor_2
./fluster.py run -d GStreamer-VP9-V4L2SL-Gst1.0 -ts VP9-TEST-VECTORS-HIGH -j1      # expect vp92-2-20-10bit-yuv420 PASS; 12-bit and 4:2:2 (vp93) not supported
./fluster.py run -d GStreamer-VP9-V4L2SL-Gst1.0 -ts VP9-TEST-VECTORS -j1           # Jernej: 241/305 with FFmpeg; record GStreamer count
./fluster.py run -d GStreamer-H.264-V4L2SL-Gst1.0 -ts JVT-AVC_V1 -j1               # compare with the pre-change run (256-bit DDR fix)
./fluster.py run -d GStreamer-VP8-V4L2SL-Gst1.0 -ts VP8-TEST-VECTORS -j1
./fluster.py run -d GStreamer-MPEG2-V4L2SL-Gst1.0 -ts MPEG2_MAIN -j1 2>/dev/null || ./fluster.py list | grep -i mpeg2
# Pass: Main10 vectors 11/11 (except TSUNEQBD: unequal luma/chroma depth, rejected by try_ctrl = expected),
#       VP9 profile-2 10-bit 4:2:0 PASS, no regressions vs the pre-change run for H.264/HEVC 8-bit/VP8/MPEG-2.
# Watch dmesg during runs: no "sun50i-iommu ... fault", no cedrus watchdog timeouts.

# C. Throughput vs spec (streams produced on the build host by harness/research/vdec/make-4k-streams.sh;
#    copy the directory incl. *.md5 to the board, e.g. ~/vdec-streams)
cd ~/vdec-streams
run() { # $1 file $2 parser-chain $3 caps-format
  i0=$(awk '/1c0e000/{s=0;for(i=2;i<=5;i++)s+=$i;print s}' /proc/interrupts)
  /usr/bin/time -f "%e s" gst-launch-1.0 -q filesrc location=$1 ! $2 ! fakesink sync=false 2>&1 | tail -1
  i1=$(awk '/1c0e000/{s=0;for(i=2;i<=5;i++)s+=$i;print s}' /proc/interrupts); echo "irqs: $((i1-i0))"
}
run hevc-main-2160p60.mkv   "matroskademux ! h265parse ! v4l2slh265dec"       # frames = 600 (10 s @ 60)
run hevc-main10-2160p60.mkv "matroskademux ! h265parse ! v4l2slh265dec"
run hevc-main10-6k30.mkv    "matroskademux ! h265parse ! v4l2slh265dec"       # 300 frames; needs patch 26
run vp9-p2-2160p60.webm     "matroskademux ! vp9parse ! v4l2slvp9dec"
run vp9-p0-2160p60.webm     "matroskademux ! vp9parse ! v4l2slvp9dec"
run h264-high-2160p30.mkv   "matroskademux ! h264parse ! v4l2slh264dec"       # 300 frames
# fps = frames / elapsed. Pass: >= 60 (HEVC/VP9 4K), >= 30 (HEVC 6K, H.264 4K), irqs >= frames (HW really decoded).
# Exact frame counts: gst-launch-1.0 -q filesrc location=F ! DEMUX ! PARSE ! DEC ! fakesink silent=false -v | grep -c chain

# D. 4K bit-exactness of the same streams (P010 / NV12 out, compare to SW md5 made on the host)
gst-launch-1.0 -q filesrc location=hevc-main10-2160p60.mkv ! matroskademux ! h265parse ! v4l2slh265dec ! \
  videoconvert dither=none ! video/x-raw,format=I420_10LE ! filesink location=/tmp/o.yuv && md5sum /tmp/o.yuv
#   reference on the host: ffmpeg -i F -pix_fmt yuv420p10le -f rawvideo - | md5sum   (8-bit: yuv420p / I420)
#   (4K raw output is ~1.5 GB per 60 frames 10-bit: use -t 1 s streams or pipe into md5sum via fdsink fd=1)

# E. VE clock check (throughput depends on it): sudo cat /sys/kernel/debug/clk/ve/clk_rate   # expect 600000000
```

FFmpeg path, optional (VC-1/MPEG-4, and a second opinion for VP9):
```sh
git clone --depth 1 -b v4l2request-mpeg4 https://github.com/jernejsk/FFmpeg ffmpeg-v4l2 && cd ffmpeg-v4l2
./configure --prefix=$HOME/ffv4l2 --disable-doc --disable-programs --enable-ffmpeg --enable-v4l2-request --enable-libdrm --enable-libudev
make -j4 && make install        # ~30-40 min on the A53s
~/ffv4l2/bin/ffmpeg -hwaccel v4l2request -i F -pix_fmt yuv420p10le -f md5 -     # compare with host md5
```
(If configure rejects `--enable-v4l2-request`, check `./configure --help | grep -i request` on that branch; Kwiboo's branches use that switch.)

## 5. AVS2: plan (the only spec item with no code anywhere)

1. **Register map.** Done as raw material: `harness/research/vdec/avs2-regs-libawavs2.txt` (21 register bitfield layouts) and `libawavs2.pahole.txt` (all 112 structs, including the decoder context, ALF, weighted-quant, RPS and frame-info). The library has DWARF and line tables for `avs2.c`, `avs2_dec.c`, `avs2_hal.c`, `avs2_parse.c`, `avs2_coeff.c`. `objdump -d -l` lines up each register write with a source line (see `kernel-check/dl-vdec/re/libawavs2.dis`). Next: list the order of writes in `AVS2ConfigureRegister`, `Avs2SetHeaderReg`, `Avs2SetFrameSecReg`, `Avs2SetDramReg`, `Avs2Set10BitReg`, `Avs2SetFunctionReg`, `Avs2SetTopReg`/`TopSecReg`, and the SRAM-port table uploads (ALF coefficients, weighted-quant matrices, reference POC/address list), the way Jernej's VP9 commit message describes his `libawvp9HwAL.so` work.
2. **uAPI** (new, downstream first): `V4L2_PIX_FMT_AVS2_FRAME` ('AVS2'), plus `V4L2_CID_STATELESS_AVS2_SEQUENCE`, `_PICTURE` (picture header + RPS + ref list), `_WEIGHT_QUANT`, `_ALF`, mirroring what `Avs2ParseSequenceInf`/`ParseInterPicHeader` fill. Use the v4l2 control framework type pattern of the VC-1 patches (14–16) as the template.
3. **Driver:** `cedrus_avs2.c` in the H.265 slot, reusing the shared 10-bit/P010 helpers from patch 11 and the col-MV handling from H.265.
4. **Userspace:** FFmpeg has no native AVS2 decoder. Options: (a) a v4l2-request hwaccel that keeps libdavs2's parsing (GPL, `pkuvcl/davs2`), or (b) a small standalone test decoder (parse + submit + write YUV) that is enough for md5 checks; (b) first.
5. **Test vectors:** AVS2 conformance streams come from the AVS workgroup (avs.org.cn) and are not freely mirrored; fluster has no AVS2 suite. Fallback: encode with `xavs2` (pkuvcl/xavs2, GPL) at 1080p/4K 10-bit and use `davs2` as the reference md5.

Estimate: comparable to Jernej's VP9 work (cedrus_vp9.c is ~1.4 kLOC), plus the uAPI and userspace. It needs several board sessions to check register semantics.

## 6. Current state and next steps (handover)

State (2026-11-02, after board runs, §9): 29 patches in `wt-vdec` (26 + 3 found on the board). H.265 8-bit/10-bit, VP9 P0/P2, H.264 decode bit-exact at 4K, 6K 8-bit H.265 bit-exact, **provided VDD-SYS is not undervolted** (§9.2). Throughput: 4K60 met only for 8-bit H.265 and 8-bit VP9 (close) with the native tiled output; 10-bit 4K60 is **not met** with P010 output; H.264 4K30 met.

Next steps, in order:
1. **Coordinator / GPU owner (blocker for correctness): stop the GPU OPP table from undervolting the VE.** On Zero2/Zero3 the GPU and the VE share `vdd-gpu-sys` (DCDCC). `sun50i-h616-gpu-opp.dtsi` (integration commit `14924c9`) lets panfrost devfreq drop it to 810 mV at idle; the VE at 600 MHz then miscomputes small blocks (§9.2). Proposed fix (not made by this agent, it is the kernel/GPU branch): in `sun50i-h616-orangepi-zero.dtsi` set `&reg_dcdcc { regulator-min-microvolt = <900000>; }` (keep max 990000), so the low GPU OPPs simply run at ≥ 900 mV; verify with `board-matrix.sh`-style runs at idle GPU. 890 mV and 950 mV were both 6/6 clean, 810 mV 6/13 + 1/3.
2. Rebuild an image from `feat/sunxi-h616-vdec-spec` + that DT fix and re-run §9 with `harness/research/vdec/board-bench.sh` (fps) and `board-10bit.sh` (md5) on a fresh boot; serve streams with `python3 -m http.server --bind 10.56.0.1 8642` from `kernel-check/vdec-streams`.
3. 10-bit 4K60 (H.265 Main10 and VP9 P2): P010 through the secondary output engine is ~0.75–0.9 GB/s write-bound (24–31 fps). The way to 4K60 is the AFBC 10-bit output (already the driver default for 10-bit H.265, and opt-in for VP9) consumed by the display (DE33 AFBC) — measure it with an AFBC-capable client (Jernej's FFmpeg fork with `-hwaccel v4l2request` and DRM-PRIME output, or Kodi). **Building/running that fork on the board was refused by the permission classifier in this session; it needs the user's go-ahead.** The fork's `V4L2REQUEST_PIXFMT` experiment override is in `harness/research/vdec/ffmpeg-fork-pixfmt-override.diff`.
4. VE clock: keep 600 MHz once VDD-SYS ≥ 0.89 V; consider 624 MHz (vendor policy) for 6K30/4K60 margin only after a soak at the fixed voltage. Note the stock image (upstream 7.4 H616 variant) ran the VE at 648 MHz on the same undervolted rail — upstream should hear about the shared-rail issue.
5. fluster conformance (JCT-VC-HEVC_V1 incl. Main10, VP9-TEST-VECTORS(-HIGH), JVT-AVC_V1) was **not run**: cloning/running fluster from GitHub on the board falls under the same "external code" refusal. Needs approval, then §4 B.
6. AVS2: §5 (no code yet). Other UM codecs (AVS/AVS+, JPEG, RealVideo, MS-MPEG4) and DI300: as before.
7. Upstreaming: Jernej's patches are unposted; our 5 are small. Report the VP9↔H.265 cross-context failure (patch 29) and the payload issue (patch 28) to Jernej, since they are in his VP9/P010 code.
8. Board network (not vdec, for the coordinator): on the test kernels, host→board TCP throughput degrades from ~15 MB/s (fresh boot) to ~0 after about 1 h of decode load, with clean `ethtool -S` counters and 33 % loss on 8000-byte pings; a reboot restores it. Seen on kernels #3 and #6 (both this series on `39853f9`), not investigated further.

## 7. Compile-check results

**After the rebase onto `39853f9` and the three board-found patches (HEAD `d92a201`):** `STAGE=patch` 741 applied, 0 failed (`kernel-check/run-vdec-patch4.log`); cedrus + sun50i-iommu sources byte-identical to the built tree `kernel-check/work-vdec/linux-7.3.1`. `STAGE=all` after the rebase (`run-vdec-all2.log`): exit 0, 8 pre-existing C warnings, DT_CHECK ok. Incremental ccache rebuilds for patches 27–29 (Image, `W=1` on cedrus): no warnings. Final series Image md5 `c6b1ba9b5d471337e4df2fcc5fd2e815` (no debug params).

Earlier (before the rebase):
Commit `1c1912b` on `feat/sunxi-h616-vdec-spec` (26 patch files + series.conf, 10,878 inserted lines).

- `STAGE=patch`: 735 patches applied, 0 failed. The resulting cedrus/IOMMU sources are byte-identical to the scratch git tree (`kernel-check/scratch-vdec/linux`, one commit per patch).
- `STAGE=all` (`kernel-check/run-vdec-all.log`, `WORK=kernel-check/work-vdec`, ccache): Image + modules + Zero2 DTB OK, `make dtbs` OK (55 h616 overlays), overall exit 0. The 8 C warnings are all pre-existing (sunxi_sid, fdt_address, sunxi-addr, axp20x, panel-simple, sunxi-sysinfo); none are in cedrus, IOMMU or v4l2-core. The dtc warnings are the pre-existing A64/H5 ones.
- `make W=1 drivers/staging/media/sunxi/cedrus/`: no warnings.
- DT_CHECK: `video-codec@1c0e000` with `compatible = "allwinner,sun50i-h616-video-engine"`, `interrupts = <0 93 4>`, `iommus = <&iommu 3>, <&iommu 2>`, two SRAM claims.
- Config: `CONFIG_VIDEO_SUNXI_CEDRUS=y`, `CONFIG_V4L2_VP9=y` (now also selected by cedrus), `CONFIG_SUN50I_IOMMU=y`; no change to `linux-sunxi64-edge.config`.

Throughput streams: `harness/research/vdec/make-4k-streams.sh` was run on the build host into `kernel-check/vdec-streams/` (log `kernel-check/vdec-streams.log`). It produces hevc-main/main10 2160p60, hevc-main10 6K30, vp9 p0/p2 2160p60, h264 high 2160p30, each with a `.md5`/`.framemd5` from the software decoder. Copy the directory to the board for §4 C/D.

## 9. Board results (2026-11-02, Orange Pi Zero2 1 GB, test kernels from this branch on `39853f9`)

Kernels: #1–#3 = the series (+ patches 27/28), #6 = + patch 29 + debug-only `sunxi_cedrus.dbg_mod_rate`/`dbg_ddr` params (`kernel-check/scratch-vdec/debug-params.diff`, not in the series), installed with its own modules (module BTF must match vmlinux). Userspace: Ubuntu 26.10 `gstreamer1.0-plugins-bad` 1.28.6 v4l2codecs, `v4l-utils`, `ffmpeg` (host reference only). Streams: `kernel-check/vdec-streams/` (testsrc2 + noise, ~40 Mbit/s 4K, near the worst case for CABAC), references made on the host with `ffmpeg -pix_fmt nv12|p010le -f md5/framemd5`. Scripts: `harness/research/vdec/{board-bench.sh,ve-busy.sh,framemd5.py,mem-probe.sh,board-matrix.sh,board-voltage.sh,board-10bit.sh,vdec-fallback.sh}`; logs `kernel-check/vdec-board-*.log`.

### 9.1 Per spec row

fps = VE-bound rate from ftrace (`cedrus_device_run`→`cedrus_irq`, `ve-busy.sh`; VE busy ≥ 96 % of wall time, CPU ~1 s per run, so these equal the pipeline rate to fakesink). md5 = whole-stream md5 of the decoder output vs the host software decode.

| Spec row | Driver state | fps measured (VE 600 MHz) | Bit-exact md5 (VDD-SYS ≥ 0.89 V) |
|---|---|---|---|
| H.265 Main 4K60 | upstream + patches 27/29 | **81.8** native tiled NV12_32L32 (meets); 34.9 linear NV12 | **PASS** 600/600 frames, 9/9 runs at 432 MHz or ≥ 0.89 V |
| H.265 Main10 4K60 | Jernej P010 (patch 11) | **24.5** with P010 (not met); AFBC10 not measurable with GStreamer | **PASS** 600/600 (`e57bc497…`) |
| H.265 6K30 | our patch 26 | 8-bit 6144x3456: **30.2** tiled (meets, no margin), 12.5 linear. Main10 6K: **OOM** (one P010 buffer is 103.5 MB, 1 GB board) | 8-bit 6K **PASS** 120/120 (`b497a7c5…`); Main10 6K not decodable on 1 GB |
| VP9 Profile 2 4K60 | Jernej VP9 (patch 10) + P010 | **35.6** with P010 (not met) | **PASS** 600/600 (`1e40c2b3…`; min MemAvailable 140 MB during the CPU-readback run, no OOM) |
| VP9 Profile 0 4K (no spec row, same engine) | | **76.3** tiled (meets 60) | **PASS** 600/600 (`9368ae9b…`) |
| AVS2 JiZhun 10-bit 4K60 | **none** (no uAPI/driver/userspace anywhere, §5) | n/a | n/a |
| H.264 High 4K30 | upstream + 256-bit DDR (patch 13) | **42.0** tiled (meets), 28.6 linear NV12 | **PASS** 300/300 (`2f51f88f…`) |

Stock image kernel (upstream 7.4 H616 variant, 648 MHz, no VP9) for comparison: H.265 Main 4K 79.8 fps; H.265 Main10 and H.264 4K **hang the VE** ("frame processing timed out!", gst "Not enough memory to decode"); no VP9 device.

Why 10-bit misses 60: the VE reconstructs into 8-bit tiled + 2-bit planes and the secondary output engine writes P010 on top; that engine is write-bound at ~0.75–0.9 GB/s (8-bit linear NV12 costs +16.4 ms/frame for 12.4 MB, P010 ~33 ms for 24.9 MB). DRAM is DDR3-1440 x32 (`CONFIG_DRAM_CLK=720`), and the 8-bit tiled path already moves ~3 GB/s, so this is not DRAM. 4K60 10-bit needs the AFBC output to the display (next step 3).

### 9.2 The intermittent mismatch: VDD-SYS undervolted by GPU devfreq

Symptom: at 600 MHz about every second 4K H.265 run had a few bad frames, different ones each run (393–419, 221–223, 433–479, 21–23, 13, 183, …), never a kernel message. A bad frame differs in ~60 luma bytes inside two horizontally adjacent 64x64 CTBs, 5 rows, max |d| 37–68, chroma clean; it propagates through B-pyramid/P references to the next I-frame. VP9 P0 showed the same once (frame 35). Not stale CPU cache (partial 64-byte lines, data matches no other frame).

| VE clock | DDR mode | vdd-gpu-sys | clean runs |
|---|---|---|---|
| 600 MHz | 256-bit | 810 mV (GPU idle) | 6/13 |
| 600 MHz | 128-bit | 810 mV | 1/3 |
| 432 MHz | 256-bit | 810 mV | 3/3 |
| 600 MHz | 256-bit | 890 mV (GPU devfreq min 504 MHz) | 3/3 |
| 600 MHz | 256-bit | 950 mV (GPU min 600 MHz) | 3/3 |

Cause: the VE sits on VDD-SYS, which on the Zero2 is AXP305 DCDCC shared with the GPU (`vdd-gpu-sys`, 810–990 mV in the DTS). U-Boot does not set DCDCC (no `CONFIG_AXP_DCDC3_VOLT`), so it used to stay at the PMIC default; the GPU OPP table added in `14924c9` lets panfrost devfreq lower it to 810 mV whenever the GPU idles, and the VE at 600 MHz (648 MHz on the stock kernel!) is not reliable there. Fix proposed in §6 step 1 (DT floor 900 mV on `reg_dcdcc`); runtime workaround: `echo 504000000 > /sys/class/devfreq/1800000.gpu/min_freq`.

### 9.3 Other bugs found and fixed on the board
- 8-bit H.265 no longer negotiated in GStreamer (AFBC default): patch 27.
- P010 payload included private planes: patch 28.
- VP9 + H.265 in parallel contexts: every H.265 job failed: patch 29 (H.265 + H.264 in parallel was fine before and after).

### 9.4 Memory (1 GB board)
- All cedrus buffers come from the IOMMU page path; **none from CMA**. "CMA full" (CmaFree 0) is movable page cache placed in CMA pageblocks: `echo 1 > /proc/sys/vm/drop_caches` brings CmaFree from 0.9 MB to 42.6 MB. The remaining ~20 MB of the 64 MB CMA is held persistently (display framebuffers, not cedrus).
- Buffer counts are GStreamer's (the driver sets no `min_buffers`): 2 OUTPUT buffers everywhere; CAPTURE 8 (H.265 4K), 11 (H.264 4K), 14 (VP9 4K: 8 ref slots + pipeline).
- Capture buffer sizes: 4K NV12 12.4 MB; 4K P010 40.4 MB = P010 24.9 + hidden 8-bit recon 12.4 + 2-bit plane 3.1 (the recon + 2-bit are what the VE references; P010 is the copy for userspace, so none of it is removable while P010 is the output; AFBC10 output would avoid the extra surface). 6K P010 103.5 MB.
- Per-context aux: H.265 neighbour info 794 KiB + per-buffer MV col (CTB-count sized, from the coded size, not the max); VP9 prob tables 544 KiB + neighbour 2 MiB + col-MV sized from the coded size (grown on resolution change). Nothing sized for the maximum resolution; nothing to trim.
- Health at 4K 10-bit (fakesink, decoder-only): H.265 Main10 min MemAvailable 468 MB, VP9 P2 260 MB, gst RSS 33–43 MB, no OOM, ssh/other services fine. With CPU readback (fdsink → md5) gst additionally maps every buffer; that is what produced the 585 MB RSS and, once, an OOM kill of a second concurrent 4K 10-bit decode ("dma alloc of size 40435712 failed"). Two 4K 10-bit P010 decodes at once do not fit in 1 GB.

### 9.5 Not done / blocked
- AFBC throughput and the FFmpeg v4l2request path: building/running Jernej's FFmpeg fork on the board was refused by the permission classifier (external code). Needs the user's approval.
- fluster conformance suites: same reason.
- AVS2: not started (§5).

## 8. Sources
- H616 User Manual v1.0 (`kernel-check/work-audio/vendor/H616_User_Manual_V1.0_cleaned.pdf`; text in `kernel-check/dl-vdec/um.txt`): §2.2.4, §3.1 (memory map), §3.3.5.62/63 (VE CCU), §3.12 Table 3-8 (IOMMU masters), §4.4.1 (decode features).
- Orange Pi Zero2 product page (HTTP), Video decoding section.
- Vendor BSP: github.com/orangepi-xunlong/linux-orangepi `orange-pi-4.9-sun50iw9`: `sun50iw9p1.dtsi`, `drivers/media/cedar-ve/cedar_ve.c`, `drivers/media/cedar-vp9/google_vp9.c`, `drivers/clk/sunxi/clk-sun50iw9.[ch]`, `arch/arm64/configs/sun50iw9p1smp_*defconfig`.
- Vendor userspace: `Allwinner-Homlet/H6-CedarC` (LGPL source: `ve/veAw/veAw.c`, `vdecoder/videoengine/h265/h265_register.[ch]`); libcedarc A133 drop (`library/aarch64-linux-gnu/libVE.so`, `libawvp9HwAL.so`, `libawavs2.so`, `library/androidq_64/libawh265.so`, all with DWARF).
- Upstream: Chen-Yu Tsai "[PATCH v3 0/7] arm64: allwinner: h616: Support Video Engine" (msgid 20260712030011.3778169-1-wens@kernel.org; 1f24d4307515, eabc3c090e81 in 7.4); review thread https://lkml.iu.edu/2606.1/13282.html.
- Jernej Škrabec: github.com/jernejsk/linux-1 branches `h616-cedrus`, `h616-mpeg4`, `vp9-v1`, `h616-bench-cedrus`; github.com/jernejsk/FFmpeg `v4l2request-mpeg4`.
- FFmpeg v4l2-request status: Kwiboo PR 20847 (pending as of 2026-03), github.com/Kwiboo/FFmpeg `v4l2-request-n8.1`.
- fluster: github.com/fluendo/fluster (`test_suites/h.265/JCT-VC-HEVC_V1.json`, `test_suites/vp9/VP9-TEST-VECTORS-HIGH.json`).
