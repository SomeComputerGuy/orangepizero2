# H616 Cedrus: legacy decode formats, bit-exactness and speed on the Orange Pi Zero2

Date: 2026-11-03. Work item **W2** of `docs/datasheet-checklist.md` (datasheet §2.4.1, `docs/vendor/H616_Datasheet_V1.0.txt`).
Tags: **[M]** measured here, **[I]** inference, **[U]** unverified.

Board kernels (userspace only, no kernel installed by this work):
- MPEG-2 suite, first 37 vectors: vdec-series test kernel `7.3.1 #12` (2026-11-03 00:29).
- Everything else: image kernel `7.3.1-edge-sunxi64 #11` from image 16cdd50a9.

Both kernels expose `MG2S S264 S265 VP8F VP9F AVS2 SVC1 MG4S S263 SPKS`. VE at 600 MHz (`clk/ve/clk_rate`).

## 0. Answer

| Format (datasheet) | Streams | Bit-exact (x/y) | Within IDCT envelope¹ | fps 1080p (VE-bound / pipeline)² | Verdict vs datasheet |
|---|---|---|---|---|---|
| **MPEG-2 MP/HL** 1080p@60 | ISO 13818-4 main profile: 37 MPEG-2 vectors, incl. 9 field-picture and 1 dual-prime. Generated MP@HL 1080p60, 1080i, 1088p60 | 3/37 conformance streams fully, all frames of 4. FFmpeg's IDCT is not the VE's (§2.1) | **37/37** conformance, 1088p OK. **1080p/1080i FAIL** (bottom-edge MC, root-caused, fix patch §4) | 147 / 126 (1080p60), 138 / 113 (1080i, 60 fields), tiled 172 / 143 | Speed **meets**. Correctness **meets for MB-aligned heights**; 1080-line streams need the fix patch (untested on HW) |
| **MPEG-1 MP/HL** 1080p@60 | ISO 13818-4 suite's 6 MPEG-1 vectors (ccm1, MEI.stream16 ×2, tcela-16/18/19), generated 1080p30 | — | — | — | **GAP: no path.** No userspace can submit MPEG-1, and the uAPI cannot express it (§2.2) |
| **MPEG-4 SP** | ISO 14496-4 SP: ti_sdtv, ti_vga. Generated SP 1080p60 | 0 | generated 1/1 OK (max 3). Conformance 0/2: **both use data partitioning, which the driver rejects** (SW fallback) | — / 146 | Speed meets. **PARTIAL**: data partitioning and RVLC are not supported ("the engine has no data partitioning (nor RVLC) mode") |
| **MPEG-4 ASP@L5** | Generated (FFmpeg encoder): B + qpel + 4MV 1080p60, interlaced 1080i30 | 0 | progressive B+qpel OK (max 3). **Interlaced FAIL** (B-VOPs only, §3.2) | — / 94 (B+qpel), — / 110 (1080i)³ | Speed meets. **Interlaced B-VOPs wrong** |
| **Xvid** | Generated (libxvid 1.3): B; B+qpel; B+GMC; B+qpel+GMC; GMC pan; GMC rotation+zoom with qpel | 0 | 5/6 OK. **B+GMC (half-pel) FAIL** (§3.3) | 133 / 126 (B), 120 / 112 (qpel), 122 / 115 (GMC), **47 / 46 (qpel+GMC)**; tiled qpel 146 / 137, qpel+GMC 51 / 50 | **PARTIAL**: one half-pel GMC stream wrong, and the qpel+GMC stream decodes at **47–51 fps (< 60)** |
| **H.263 BP** | Generated baseline, 16CIF 1408x1152 (the largest baseline source format; 1080p is not expressible in H.263 BP) and 4CIF | 0 | 2/2 OK (max 3) | 16CIF 219 / 171, 4CIF 792 / 486 | **Meets** (at the largest BP size) |
| **Sorenson Spark** | Generated FLV1 1080p60 (no free conformance set) | 0 | 1/1 OK (max 3) | 163 / 127 | **Meets** |
| **VP8** 1080p@60 | libvpx test vectors (fluster VP8-TEST-VECTORS, 61); generated 1080p60 with alt-ref | **60/61** conformance (= suite md5⁴), 300/300 generated | n/a (normative) | 152 / 141 | **Meets**, except mid-stream upscaling (segmentation-1425, §3.5) |
| **VC-1 AP** | SMPTE (FATE mirror): SA00040, SA00050, SA10091, SA10143 (480i interlaced), SA20021, ilaced_twomv (1080i, frame-interlaced 2MV) | **6/6** | n/a | 1080i: 116 / 50⁵ | **Meets** (interlaced AP bit-exact) |
| **WMV9 / VC-1 MP** | SMPTE SMM0005 (B-frames), SMM0015 | **1/2**: SMM0005 17/24 frames (B-frames wrong) | n/a | 720x576: 773 / 206. 1080p scaled by MB count ≈ 150 [I] | **PARTIAL**: Main-profile B-frames wrong at the right edge (§3.1) |
| **VC-1 SP** | none (no free SP stream, no VC-1 encoder on the host) | — | — | — | **untested** |
| **H.264 BP/MP/HP@L4.2** 4K@30 | JVT-AVC_V1 (135), JVT-FR-EXT 8-bit 4:2:0 (46), generated High 1080p60 CABAC, CAVLC, 1080i MBAFF, 4K30 | AVC_V1 **130/130** BP/MP/HP (5 Extended-profile vectors excluded), FR-EXT **44/46**, generated **4/4** (4K30 300/300) | n/a | 124 / 103 (1080p High), 120 / 97 (1080i MBAFF). **4K30: 29.6 / 28.3 linear NV12, 41.6 / 38.9 tiled** | **Meets** with tiled output; linear NV12 is just under 30. 4:0:0 monochrome (High profile) is rejected (2 FR-EXT vectors) |

1. MPEG-1/2/4 Part 2, H.263 and Spark specify the IDCT only to IEEE 1180 accuracy, so ±1 differences are allowed, and they
   accumulate in P-chains (the ISO "att" mismatch stream drifts by 23 between two of FFmpeg's own IDCTs). Pass criterion: across
   FFmpeg's simple/int/faani IDCTs, the HW's max |diff| against the closest one is ≤ max(2, the simple-vs-int spread on the
   same stream). The frame counts must match. A real decoding bug shows up as tens to hundreds of grey levels, localized (§3).
2. ftrace `cedrus_device_run`→`cedrus_irq` (`ve-busy-cmd.sh`) = VE-bound. Wall time of `ffmpeg -hwaccel v4l2request
   -hwaccel_output_format drm_prime -i http://… -f null -` = pipeline. Streams come over HTTP from the host. Linear NV12 capture
   unless "tiled" (`V4L2REQUEST_PIXFMT=ST12`).
3. FFmpeg-encoded MPEG-4 has ~7 hardware runs per frame (video packets: 2048–2064 IRQs for 300 frames). ve-busy only times the
   first run, so only the pipeline number is valid for these streams. Xvid streams have 1 run/frame.
4. The host software decoder reproduces all 61 fluster md5s with `-noautoscale`. HW framemd5 == SW framemd5 therefore implies
   HW == the suite md5.
5. ilaced_twomv is only 13 frames: the pipeline number is dominated by start-up.

**Datasheet speed (1080p@60) is met by every format that has a HW path, except Xvid with quarter-pel + GMC (47–51 fps)**
[M]. 4K@30 H.264 needs the tiled capture format (41.6 fps; linear NV12 29.6).

## 1. Method

### 1.1 Decoder and checks
- Client: Jernej's FFmpeg fork `v4l2request-mpeg4` a56a208b, static cross build `kernel-check/ffmpeg-afbc/build/ffmpeg`
  (sha256 `9542639f…`, impl-vdec-main10-perf §1), copied to `/root/vp/ffmpeg` after each reflash.
- The fork has v4l2request hwaccels for h264, hevc, vp8, vp9, av1, mpeg2, **mpeg4, h263, flv (Spark), vc1, wmv3**
  (`libavcodec/hwaccels.h`, `config_components.h`). **No mpeg1 hwaccel** (§2.2). Nothing was missing for MPEG-4/H.263/Spark/VC-1,
  so no hwaccel code was written.
- Proof of HW decode: the board decodes with `-hwaccel_output_format drm_prime -vf hwdownload,format=nv12`. If FFmpeg falls back
  to software, hwdownload refuses the frames (rc 218), so a matching output can only come from the hardware. The VE IRQ delta
  (`/proc/interrupts` 1c0e000.video-codec) is recorded too.
- Normative-transform codecs (H.264, VP8, VC-1): per-frame `framemd5` (NV12, `-fps_mode passthrough -noautoscale`) on the board
  vs the host's FFmpeg 8.1.2 software decoder, same demuxer options (`harness/research/legacy-dec/run-md5.sh`, `cmp-framemd5.py`).
- Other codecs: raw NV12 from the board to the host, compared per frame against host SW decodes with `-idct simple|int|faani`
  (`run-raw.sh`, `cmp-raw.py`, verdict `sum-raw.py`); faulty frames are located with `locate.sh` (MB row/col of |diff| > 4).
- Conformance md5s: VP8 61/61, JVT-AVC_V1 130/135 and FR-EXT 46/46 of the fluster `result` md5s are reproduced by the host SW
  decoder. The 5 AVC_V1 misses are Extended profile (FMO/ASO, SP slices: FM1_BT_B, FM1_FT_E, FM2_SVA_C, SP1_BT_A, sp2_bt_b),
  which FFmpeg does not decode either and which lie outside BP/MP/HP. The fluster MPEG-2/MPEG-4 suites (0.7.1 JSON) carry no md5.

### 1.2 Test media (data only; nothing downloaded was executed)
Each set sits in its own directory with a `SHA256SUMS` covering the archives and the extracted bitstreams. Fluster JSONs were read
from the fluster 0.7.1 package (opi5 project); fluster itself was not run. `harness/research/legacy-dec/fetch-suite.py` checks
every archive against the JSON `source_checksum` (all matched).

| Directory (`kernel-check/dl-legacy/`) | Source | Vectors |
|---|---|---|
| `iso-mpeg2-main/` | standards.iso.org ISO/IEC 13818-4 main profile (fluster MPEG2_VIDEO-MAIN) | 43 (37 MPEG-2 + 6 MPEG-1) |
| `iso-mpeg4-sp/` | ISO/IEC 14496-4 Amd 10 A6-GE19/20 .tgz (fluster MPEG4_VIDEO-SimpleProfile) | 2 (nok_720p is behind the licence gate) |
| `vp8-test-vectors/` | github.com/webmproject/vp8-test-vectors (fluster VP8-TEST-VECTORS) | 61 |
| `jvt-avc-v1/`, `jvt-fr-ext/` | itu.int jvt-site draft_conformance (fluster JVT-AVC_V1, JVT-FR-EXT) | 135, 69 (46 are 8-bit 4:2:0) |
| `smpte-vc1-fate/` | SMPTE RP 228 VC-1 conformance streams as mirrored on fate-suite.ffmpeg.org/vc1/ (SMPTE does not distribute them free) | 8 |

**Not downloaded**: the ISO 14496-4 ASP and SP .zip bundles (c041935, C051232, c046298). standards.iso.org serves them only after
a click-through **copyright licence** form, and I did not accept a licence on your behalf. These hold the 30 ASP conformance streams
(B-VOPs, qpel, GMC, interlaced). **Your decision is needed**.

Generated (`kernel-check/legacy-streams/`, `make-legacy-streams.sh`, testsrc2 + temporal noise, 300 frames, `SHA256SUMS`): MPEG-2
MP@HL 1080p60/1080i30/1088p60, MPEG-1 1080p30, MPEG-4 SP/ASP (FFmpeg encoder), 6 Xvid variants (libxvid), H.263 BP 16CIF/4CIF,
FLV1 1080p60, VP8 1080p60, H.264 High 1080p60 CABAC/CAVLC and 1080i MBAFF. Plus the existing `vdec-streams/h264-high-2160p30.mkv`.
S-VOP counts (ffprobe): xvid-gmc 6, xvid-qpel-gmc 6, gmc-rot 6, **gmc-pan 0** (Xvid chose P-VOPs), all with 3 warping points and 1/16 pel.

### 1.3 Logs
Summaries copied to `harness/research/legacy-dec/results/` (md5/raw TSVs, fps, all SHA256SUMS). Full logs: `kernel-check/legacy-results/<suite>/` (`summary.tsv`, `raw.tsv`, per-frame `*.perframe`, `*.err`), `fps.tsv`,
`kernel-check/legacy-chain.log`. Lists: `harness/research/legacy-dec/lists/`.

### 1.4 H.264 JVT-AVC_V1
**130/130** of the BP/MP/HP vectors bit-exact [M] (135 total).
- The 5 Extended-profile vectors fail as expected: FM1_BT_B, FM2_SVA_C (rc 69), FM1_FT_E, SP1_BT_A, sp2_bt_b. FFmpeg's software
  decoder fails them too.
- CVFC1_Sony_C (frame cropping) is bit-exact 50/50 once the HW frames are cropped on the host (`crop=300:168:26:60`). The fork's
  drm_prime/hwdownload path applies only the right/bottom crop (output 326x228 instead of 300x168): an FFmpeg-fork display issue,
  not a decode issue.

## 2. Per-format notes

### 2.1 MPEG-2 (incl. field pictures)
- All 37 MPEG-2 conformance vectors pass the envelope test [M]. Typical max |diff| is 2–3 vs FFmpeg `faani` (the VE's IDCT is
  closer to an exact IDCT than FFmpeg's default `simple`). att (the IDCT mismatch stream, 131 P-pictures) reaches 6, with an
  envelope of 23. teracom_vlc4 (VLC/saturation stress) reaches 160, with an envelope of 255.
- Fully bit-exact streams: mcp10ccett 4/4, tcela-15 61/61, tcela-17 2/2.
- **Field pictures** (hhi_burst_long/short, sony-ct1..4, tcela-8/9/10: 19–61 field pairs each) and dual-prime (toshiba_DPall-0)
  are correct. The job count equals frames + field pictures (e.g. hhi_burst_long 65 jobs = 27 frames + 19 pairs), so
  `mpeg2-fix-field-pictures` works on the current series.
- **Bug: 1080-line streams.** The generated 1080p60 and 1080i streams show errors of up to 21–22 confined to the bottom MB rows
  (66–67, y 1054–1079), growing through each GOP. The same encode at 1920x**1088** is clean (max 3). Root cause and fix in §4.

### 2.2 MPEG-1 through MG2S: not possible today
- The hardware has an MPEG-1 mode (`VE_DEC_MPEG_TRIGGER_MPEG1`, bit 24) and full-pel vector bits (`MP12HDR_FULL_PEL_FORWARD/
  BACKWARD_VECTOR`). The driver always triggers MPEG-2 and writes the full-pel bits as 0 (`cedrus_mpeg2.c`).
- The V4L2 MPEG-2 uAPI has no MPEG-1 flag and no full_pel fields. Userspace: GStreamer 1.28 `v4l2slmpeg2dec` sink caps are
  `mpegversion=2` only, and the FFmpeg fork has no `mpeg1_v4l2request` hwaccel (`mpeg1_hwaccel_pixfmt_list_420` has no
  DRM_PRIME).
- Submitting MPEG-1 as MPEG-2 would be wrong anyway: MPEG-1 uses oddification mismatch control (not MPEG-2's sum parity),
  full-pel vectors and D-pictures (tcela-18 is D-only).
- **Fix needs**: a uAPI extension (`V4L2_MPEG2_SEQ_FLAG_MPEG1` + picture flags for full_pel_forward/backward), cedrus setting
  TRIGGER_MPEG1 and the full-pel bits, and an FFmpeg `mpeg1_v4l2request` hwaccel (≈20 lines on top of v4l2_request_mpeg2.c).
  Not written: it adds uAPI.

### 2.3 MPEG-4 Part 2 / Xvid: which ASP tools the hardware handles
| Tool | HW / driver | Evidence |
|---|---|---|
| B-VOPs (direct, interpolated) | yes | Xvid B and FFmpeg B+qpel OK |
| Quarter-pel | yes (with FFmpeg's qpel chroma quirks) | Xvid qpel, FFmpeg qpel OK |
| GMC (S(GMC) VOPs, 1–3 warping points) | yes, affine, in hardware | qpel+GMC and rotation+zoom GMC OK; **half-pel GMC stream wrong** (§3.3) |
| Static sprites | **no** (`-EINVAL` unless `sprite_enable == GMC`) | driver |
| Interlaced (field DCT, field MC) | yes for I/P; **B-VOPs wrong** | §3.2 |
| Data partitioning, RVLC | **no** (`try_ctrl` rejects DATA_PARTITIONED) | ISO SP ti_sdtv/ti_vga fall back to SW |
| Resync markers / video packets | yes (per-packet runs) | FFmpeg-encoded streams: ~7 runs/frame |
| MPEG / H.263 quantisation | yes | generated streams |

### 2.4 H.264 High-profile features
FR-EXT 44/46 bit-exact. The two failures are the 4:0:0 monochrome vectors HPCAMOLQ_BRCM_B and HPCVMOLQ_BRCM_B: `cedrus_try_ctrl`
rejects `chroma_format_idc != 1`. High profile includes 4:0:0, so this is a feature gap (whether the VE can decode it, e.g. by
writing a grey chroma plane, is [U]). Bit-exact coverage:
- 8x8 transform with CABAC and CAVLC: FRExt1–4_Panasonic, HCAFR*, HPCV*;
- scaling matrices: HPCA(Q2)LQ, freh*;
- PAFF: HCAFF1, HVLCPFF0, CAPAMA3 in AVC_V1;
- MBAFF: HCAMFF1, HVLCMFF0, HPCAMAPALQ;
- field pictures: HVLCFI0;
- generated x264 1080i MBAFF 300/300.


### 2.2b MPEG-1 implementation (2026-11-03, build-tested, **not HW-tested**)
- Kernel, on build-fork `fix/sunxi-h616-legacy-dec` at 7828d5a1f, after the MPEG-2 clamp patch:
  - `media-uapi-mpeg2-add-MPEG-1-sequence-and-full-pel-flags.patch`: adds `V4L2_MPEG2_SEQ_FLAG_MPEG1` (0x02) and
    `V4L2_MPEG2_PIC_FLAG_FULL_PEL_FORWARD/BACKWARD` (0x100/0x200), makes v4l2-ctrls-core accept `PIC_CODING_TYPE_D`, and
    documents the fields.
  - `media-cedrus-mpeg2-decode-MPEG-1.patch`: with the MPEG-1 flag the driver triggers with `VE_DEC_MPEG_TRIGGER_MPEG1` and writes the
    MP12HDR full-pel bits. It rejects D-pictures and full-pel in MPEG-2, and field pictures in MPEG-1. Mismatch control is
    expected from the VE's MPEG-1 mode (as in Kuske's mpeg-test); the board test will tell.
  - 752 patches apply, 0 failed, 0 C warnings; cedrus and v4l2-core W=1 report 0 warnings; checkpatch --strict is clean.
- FFmpeg (fork a56a208 + `legacy-dec/ffmpeg-mpeg1-v4l2request.patch`, built into `kernel-check/ffmpeg-afbc/install-mpeg1`, ffmpeg
  sha256 f158cac1...a322):
  - `mpeg1_v4l2request` hwaccel that shares the MPEG-2 callbacks, plus the MPEG-1 seq flag and the full-pel flags;
  - DRM_PRIME in the mpeg1 pixfmt list;
  - configure, hwaccels.h and Makefile entries;
  - `#ifndef` fallbacks for the new uAPI defines.
  - FFmpeg cannot feed D-pictures (its parser rejects them), so the D path stays untested unless we write a small tool.
- Board test plan: install the work-legacy kernel (needs approval), then run the 6 ISO MPEG-1 vectors with run-md5/run-raw
  (IDCT envelope), and rerun MPEG-2 to check the clamp fix.

## 3. Failures

### 3.1 WMV9 (VC-1 Main) B-frames, right edge [M], root cause [U]
- SMM0005 (720x480, MP, Max B-frames 1, Overlap 1, VSTransform 1): I/P frames bit-exact. B-frames 9, 11, 13, … differ, max 12–31,
  only in MB columns 39–44 of 45 (x 624–719), with no propagation.
- SMM0015 (MP, no B) and every AP stream with B-frames (incl. 480i/1080i) are bit-exact, so the fault is specific to Simple/Main
  B-pictures at the right edge. Candidates: MV pull-back of B vectors (MP pulls back to the picture, AP differently), or direct-mode
  derivation from the co-located MV at the edge. Either the driver or the WMV3 fields filled by `v4l2_request_vc1.c` could be at
  fault.
- FATE's references for these files are FFmpeg's own output, not SMPTE's reconstructed YUV, so which side is wrong is not proven.
  Next: get the SMPTE reconstruction for SMM0005, or read the vendor libVE WMV3 B path.

### 3.2 MPEG-4 ASP interlaced B-VOPs [M], root cause [U]
- FFmpeg-encoded 1080i (`+ildct+ilme`, 2 B-frames): I/P-VOPs match (max 2). Every B-VOP differs: frame 1 6 MBs max 47, frames
  4–5 ~200 MBs, PSNR down to 31 dB.
- Progressive B-VOPs (Xvid, FFmpeg) are fine, so the suspects are interlaced direct mode (14496-2 7.6.9.5.2: co-located field MVs,
  TRB/TRD per field, the driver's `trd_field`/`trb_field`) or field-predicted B macroblocks.
- The 30 ISO ASP streams (licence-gated, §1.2) include interlaced B and would show which.

### 3.3 Xvid half-pel GMC, top-left [M], root cause narrowed [U]
- xvid-gmc (3 warping points, 1/16 pel, half-pel MVs): HW is wrong from display frame 23 (the B-VOP) through 29, up to 241,
  starting at the S-VOP at display frame 24 in MB row 0, cols 0-7, then propagating until the I-VOP at 30.
- **Reference decoder (2026-11-03):** xvidcore 1.3.7 (user-built, `--disable-assembly`, libxvidcore.a sha256
  987ceee1...ecad), driven by our `legacy-dec/xviddec.c` with `XVID_CPU_FORCE` (plain C). On the first 40 frames, xvid matches FFmpeg SW
  within 4 everywhere for xvid-gmc. For xvid-qpel-gmc it matches within 4 except one MB of B frame 17 (15 px, max 6; HW agrees with
  FFmpeg there: IDCT drift). So FFmpeg SW is a valid reference and **the HW is wrong** on frames 23-29.
- **MB types (`ffmpeg -debug mb_type`, plus the sprite trajectories from our `legacy-dec/m4v-sprite.py`):** every S-VOP of both
  streams starts with seven inter MBs with MVs (`>`, where the frame counter overlay sits), except the failing S-VOP 24 (trajectory du/dv (0,4) (1,0)
  (4,1), about 2 pel down). There MBs 0-6 are **coded GMC MBs** (mcsel=1 with residual), and MB 7 is skipped GMC. Coded GMC
  MBs elsewhere in the picture are fine. The quarter-pel stream never has coded GMC MBs at the start of a VOP, so its pass does not
  clear the quarter-pel path. The earlier GMC_MV_LUMA rounding hypothesis is weakened: the per-MB average warp vector of MBs 0-7
  is (0, 32/16) and rounds to the same half-pel vector the driver writes.
- Hypothesis: the HW mishandles a run of coded GMC MBs that starts at the first MB of the VOP (MB-to-MB state such as the
  predictor or "previous MB" state, reset at the VOP start). If MB 7, which is skipped GMC, really is wrong, this rules out
  residual-only errors.
- **Board test to separate the cases** (needs a slot): dump the HW frame 24, then compare MBs 0-7 against (a) the SW output and
  (b) the SW warp prediction without residual. The second shows whether the residual or the prediction is wrong.

### 3.4 Xvid quarter-pel + GMC speed [M]
- xvid-qpel-gmc: 21 ms/frame VE (47 fps linear, 51 tiled) against 7–8 ms for the qpel-only and GMC-only streams.
- The rotation+zoom stream with qpel+GMC runs at 114 fps, so the slowdown depends on content (P-VOPs of this stream: [U]).

### 3.5 VP8 mid-stream upscaling (vp80-03-segmentation-1425) [M]
- The frame size grows 176x144 → 212x173 → 282x231. After 4 frames the driver returns `-EINVAL` on the frame control: the size
  check in `cedrus_check_pic_size` refuses a frame larger than the allocated capture buffers while the CAPTURE queue is busy.
- The FFmpeg fork does not reallocate on this change (it prints "Upscaling is not implemented"), so this is a userspace limitation
  with correct driver behaviour.
- segmentation-1436 (282x231 → 352x288) passes [M]; that it reallocates there is [I].

## 4. Fix: MPEG-2 motion-compensation boundary (patch, not HW-tested)
- **Root cause [M]:** `cedrus_mpeg2_setup()` writes `VE_DEC_MPEG_PICBOUNDSIZE`, where the engine clamps MC reads, from the OUTPUT
  format (`ctx->src_fmt`). FFmpeg sets the OUTPUT format to `coded_width/height` = 1920x1080. ISO 13818-2 references are the whole
  decoded frame (6.3.3: `mb_height` rounded to 16 lines, or to 32 for interlaced sequences), so vectors may reach the decoded lines
  1080–1087, which the VE replaced with line 1079.
- Evidence: errors only in MB rows 66–67; 1088p encode clean; conformance (480/576) clean.
- **Fix:** take the boundary from the sequence header, `ALIGN(horizontal_size, 16)` × `mb_height*16`, and `mb_height*8` for field
  pictures. The patch is `media-cedrus-mpeg2-clamp-motion-compensation-to-the-decoded-frame.patch`, placed at the end of the
  h616-vdec block of `series.conf`.
- Branch `fix/sunxi-h616-legacy-dec` from `stonking-orangepizero2` cf62ac65a, worktree `/home/aruni/orangepizero2/wt-legacy-dec`,
  pushed to `fork`, not merged.
- Commit `30d7a833d`. Build (`kernel-check/build-kernel.sh`, ccache, `WORK=kernel-check/work-legacy`): series applies (750 patches, 0 failed), Image + modules + Zero2 DTB build with **0 C warnings**, `make W=1 drivers/staging/media/sunxi/cedrus/` **0 warnings**.
- **Not verified on the board** (no kernel installs allowed). To verify: install a kernel with the patch, re-run
  `FRAMES=120 run-raw.sh lists/gen-raw.list` for the two mpeg2 1080 streams and `run-raw.sh lists/mpeg2.list` (no regression).
  Expected: max |diff| ≤ 3.

## 5. Open / needs a decision
1. ISO 14496-4 ASP/SP zips: accept ISO's click-through copyright licence? This is needed for MPEG-4 ASP conformance (B, qpel, GMC,
   interlaced).
2. A test kernel with the §4 patch (ask before installing).
3. MPEG-1: add a uAPI flag + cedrus MPEG-1 trigger + FFmpeg hwaccel (§2.2)?
4. WMV9 B, MPEG-4 interlaced B, Xvid half-pel GMC: root causes [U] (§3). SMPTE reference YUVs or the xvidcore decoder (a new
   external program: ask) would settle which side is wrong.
5. VC-1 Simple profile: no stream available.
6. H.264 4:0:0 monochrome rejected by the driver.
7. MPEG-4 data partitioning / RVLC: rejected by the driver ("no such mode"). The vendor library's handling is not mined [U].
