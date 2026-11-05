# FFmpeg v4l2-request hwaccel for AVS1 (JiZhun) and AVS+ (Guangdian) on the H616

Branch `opiz2/avs` in `kernel-check/ffmpeg-deb/src` (worktree `kernel-check/ffmpeg-deb/wt-avs`), two commits on top of
`opiz2/series` (FFmpeg n8.1.2 + Kwiboo's v4l2-request series + MPEG-4/VC-1/MPEG-1), author Arun Iyengar, trailer
`Generated-by: LLM`. Board results 2026-11-05, image kernel 7.3.1-edge-sunxi64 (cedrus with the h616-avs patches).

| commit | subject | files |
|---|---|---|
| `7918aeb` | avcodec/cavsdec: add the plumbing for hwaccels | `libavcodec/cavs.h`, `cavs.c`, `cavsdec.c` |
| `efdf453` | avcodec: add V4L2 Request API AVS1 and AVS+ hwaccel | `libavcodec/v4l2_request_cavs.c`, `v4l2-stateless-avs.h` (new), `configure`, `libavcodec/Makefile`, `hwaccels.h`, `cavsdec.c` (pix fmt + hw_configs) |

Nothing is sent upstream. The uAPI header is a private copy of `patches.media/h616-avs/` patch 1, skipped when the
kernel headers already define `V4L2_CID_STATELESS_AVS_SEQUENCE` (the build uses `kernel-check/ffmpeg-deb/kuapi`).

## 1. Design

- **Model: one request per picture.** cedrus decodes a whole picture per request (the engine parses the slice headers
  and removes the annex A pseudo start codes itself, CTRL bit 26), both fields of a field coded picture. The hwaccel
  therefore gets the picture in one `start_frame()` call, from the picture start code to the end of its last slice,
  and `decode_slice()` is called once with the first slice start code onwards, which gives `data_offset` (the uAPI
  rule; 4 for pre-final streams without slice start codes, as `avs1dec` does). `end_frame()` sets SEQUENCE + PICTURE
  (+ WEIGHT_QUANT when `weighting_quant_flag`) and queues the request. The bitstream goes in as found (no
  de-emulation).
- **Picture end** (`decode_pic_hwaccel()` in cavsdec.c): annex A keeps start code prefixes out of slice data, so the
  next start code of a non-slice unit ends the picture; extension (B5) and user data (B2) units before the first slice
  belong to the picture (same rule as `avs1dec`). With the cavs parser a packet is one picture anyway.
- **References** (copied from `harness/avs1dec/avs1dec.c`, bit-exact on the board): DPB[0] = newest I/P, DPB[1] the one
  before. I/P: FORWARD = DPB[0], SECOND_FORWARD = DPB[1] (used by the second field of a field coded I); B: FORWARD =
  DPB[1], BACKWARD = DPB[0], SECOND_FORWARD = the reference before DPB[1], kept in `AVSContext.ref2` (distance and
  flags only; the frame itself is gone). Each descriptor: capture timestamp (`ff_v4l2_request_get_capture_timestamp`),
  `picture_distance = poc/2`, flags VALID / INTRA (`f->pict_type == I`) / PICTURE_STRUCTURE / TOP_FIELD_FIRST, the last two
  stored per `AVSFrame` and swapped with the frames.
- **Header parsing added to cavsdec.c** (software decoding unchanged): sequence `progressive_sequence`,
  `chroma_format`, `sample_precision`, `frame_rate_code`; picture `top_field_first`, `repeat_first_field`,
  `advanced_pred_mode_disable`, `skip_mode_flag` of a field coded I picture, `picture_reference_flag` (1 for a frame
  coded B, where it is not coded); Guangdian additions: `bbv_delay_extension`, always-present marker bit,
  `no_forward_reference_flag`, `pb_field_enhanced_flag`, the weighting quantization parameters (`AVSWeightQuant`, the
  deltas as `int`, the uAPI takes s16) and `aec_enable`. Profile 0x48 is accepted in the sequence header and refused at
  the first header when no hwaccel is active ("Guangdian profile without a hwaccel"); `decode_pic()` also refuses it
  without a hwaccel, so a mid-stream profile change cannot reach the JiZhun macroblock layer.
- **Format negotiation:** `ff_get_format()` at the first sequence header with `{DRM_PRIME, YUV420P}`; `hw_configs`
  `HWACCEL_V4L2REQUEST(cavs)`. The coded size is whole macroblocks (an even number of rows when interlaced, 1920x1088 for
  the test card), `avctx->width/height` the displayed size, as FFmpeg master does; software output is cropped as before.
- **Per-picture hwaccel data:** `AVSFrame.hwaccel_picture_private` via `ff_hwaccel_frame_priv_alloc()`, released with
  the frame (`cavs_frame_unref()`), on the keyframe DPB reset and in `ff_cavs_end()`. The hwaccel skips the software
  `ff_cavs_init_pic()` and edge buffer. `cavs_decode_frame()` no longer re-parses slice headers in hwaccel mode (they are
  the engine's; it printed "unexpected start code 0x1b6" per slice before the fix).
- `v4l2_request_cavs_init()` sets the SEQUENCE control as init control so the driver can refuse profile or size before
  streaming; `frame_params` uses `V4L2_PIX_FMT_AVS_FRAME`, 8 bit.

## 2. Host checks (software path unchanged)

Minimal native build `kernel-check/ffmpeg-deb/build-avs-host` (`--disable-everything --enable-decoder=cavs ...`),
outputs in `kernel-check/avs1-host-avs/`:

| stream | result |
|---|---|
| bunny.mp4 (`-f cavsvideo`) | 60 frames, framecrc and framemd5 identical to FATE cavs-bunny / FFmpeg 8.1 (`kernel-check/avs1-refs`) |
| cavs.mpg | 170 frames, framecrc identical to FATE cavs |
| avsplus-1080i-testcard.ts | 0 frames, "Guangdian profile without a hwaccel is not implemented" (8.1: "only support JiZhun profile") |
| AVSFileFormat.es | 0 frames, same cavs error lines as 8.1 (7x illegal intra chroma pred mode, 98x unexpected start code) |

Both commits compile on their own (`cavsdec.o` of the first commit built separately). No new warnings in cavs/v4l2_request
files in the cross build.

## 3. Board results

Binary `kernel-check/ffmpeg-deb/build-avs/ffmpeg` (static aarch64, `harness/ffmpeg/dev-build.sh`), copied to
`/root/ffavs/` with the streams; test driver `harness/ffmpeg/avs-board-test.sh` (copy + decode + compare + time),
outputs in `kernel-check/board-ffavs/` (`summary.tsv`, `*.hw.framecrc`, `*.hw.framemd5`, `fps.txt`). Decode:
`ffmpeg -hwaccel v4l2request -hwaccel_output_format drm_prime [-f cavsvideo] -i S -an -fps_mode passthrough -noautoscale
-vf hwdownload,format=nv12,format=yuv420p -f framecrc|framemd5 -` (hwdownload fails on a software fallback, so a match
proves hardware decode; the VE IRQ delta is one per picture). Reference: `kernel-check/avs1-refs-master` (FFmpeg master,
proven right by the board in impl-di-jpeg-avs §4.3).

| stream | frames | framecrc vs master ref | framemd5 vs master ref | vs avs1dec board output | VE IRQs | decode only (`-f null`, looped) |
|---|---|---|---|---|---|---|
| bunny.mp4 720p (`-f cavsvideo`) | 60/60 | **60/60 equal** | **60/60 equal** | equal (same reference) | 60 | x20 = 1200 frames in 5.66 s: **212 fps** (utime 0.68 s) |
| avsplus-1080i-testcard.ts (AVS+, field coded, AEC, enhanced field B, pseudo start codes) | 5/5 | **5/5 equal** (= FATE) | **5/5 equal** | equal | 5 | ES x40 = 200 frames in 2.30 s: **87 fps = 174 fields/s** (tiled `V4L2REQUEST_PIXFMT=ST12`: 2.31 s) |
| cavs.mpg (pre-final revision, no slice start codes) | 171 (SW 170) | 0 equal (expected: the engine writes nothing, impl-di-jpeg-avs A7) | 0 equal | equal (avs1dec: all-zero frames) | 171 | 171 frames in 0.14 s; the 171st is the truncated last picture the software decoder drops |
| AVSFileFormat.es (`-f cavsvideo`) | 105 | no reference (no FFmpeg decodes it in software) | - | 105 frames as avs1dec | 105 | x20 = 2100 frames in 1.40 s |

More:
- **Automatic download** (`-hwaccel v4l2request` without `-hwaccel_output_format`, the mpv-like path, `-pix_fmt
  yuv420p`): bunny 60/60 and test card 5/5 framecrc equal to the references. Without `-pix_fmt yuv420p` the output is
  NV12 (the frames context sw format), whose framecrc differs by layout only.
- **hwdownload cost:** 1080i 200 frames 5.87 s (34 fps), 720p 1200 frames 15.2 s (79 fps): CPU-bound mmap reads of the
  capture buffers (utime = rtime), not the VE. The decode-only numbers include process start-up.
- **Robustness:** bunny truncated to 20000 B and bunny with 20000 random bytes spliced in: no hang, rc 0, one
  rate-limited "AVS decode error: status 0x60010003/0x50010003, error case 0x58/0x42" per bad picture in dmesg,
  bunny afterwards bit-identical (framemd5 md5 `44af435b…` both runs). dmesg otherwise clean.
- Speed target 1080p60: met for 1080i (174 fields/s) and 720p (212 fps); avs1dec measured the pure hardware time at
  10.3 ms (1080i) and 4.2 ms (720p) per frame, so the pipeline is close to the engine.

## 4. Open items

- mpv is not installed on the board (gst-launch-1.0 is); the mpv path is covered only by FFmpeg's automatic download
  check above. The desktop-image agent should run mpv `--hwdec=v4l2request` (or drm/drm_prime output) once it is there.
- Weighting quantization (`V4L2_CID_STATELESS_AVS_WEIGHT_QUANT`) is filled but untested: no stream uses it (B10 in
  impl-di-jpeg-avs). Slice weighting is parsed by the engine; also untested (no stream).
- cavs.mpg (pre-final revision) decodes to black in hardware (engine limitation, known); the hwaccel does not refuse
  such streams. If wanted, `decode_pic_hwaccel()` could return ENOSYS when no slice start code is found, which makes
  FFmpeg fall back to software for them.
- Streams whose sequence header changes size are refused by cavsdec as before (`ff_get_format()` is called once).
- Both this branch and `opiz2/avs2` touch `configure`, `libavcodec/Makefile` and `hwaccels.h` next to the av1 lines;
  the hunks are two lines each, so a textual conflict on merge is possible but trivial.
- Cross-codec switching (AVS -> H.264 -> AVS2 -> AVS) was shown clean with avs1dec (A9); not repeated with FFmpeg.
