# GStreamer hardware JPEG decode on cedrus (v4l2sljpegdec): state 2026-11-05 (odd-size/mjmix/dmesg analysed, fixes in code, 06 queued)

## Rounds so far
- 02-gst-jpeg (done, build/gst-jpeg/results/, summary harness/runner-queue/done/02-gst-jpeg.summary.md): hardware path
  works and is byte-identical to the driver's own output; the three "wrong output" items it left are closed below.
- 05-gst-jpeg-gaps (queued): caps refusals (separate chroma tables, multi-scan, 4096x4096) -> jpegdec. Unchanged.
- 06-gst-jpeg-oddsize (queued, this round): odd/sub-MCU sizes in all chroma layouts, resolution changes down and up,
  odd-size clip, per-case kernel-log counts. Package harness/gst-jpeg/oddsize/, bundle build/gst-jpeg/bundle-oddsize.

## The three 02 "wrong output" items, resolved on the host from the 02 results (2026-11-05 evening)
1. **z17x33 / z17x33-411 `hw==drv DIFF`, differing db/pb/db3 md5s: a test bug, not a decoder bug.** compare.py modelled
   the GStreamer I420 dump with the chroma planes at `stride * height`; GstVideoInfo puts them at
   `stride * ROUND_UP_2(height)` (17x33: 680, not 660), so every odd-height comparison read the chroma 20 bytes early
   (the symptom: U/V PSNR 11 dB, Y fine). Read correctly, the 02 dumps give: hw == driver output **exactly** for
   z17x33 and z17x33-411 (also through decodebin, playbin, decodebin3); hw vs `ffmpeg -idct int` max|d| 1/1/1
   (PSNR 64.8/70.0/65.2 dB); the driver's 4:1:1 -> 4:2:0 resampling equals the same formula applied to ffmpeg's
   4:1:1 planes bit for bit (max|d| 0). The md5 differences between db/pb/db3 are the padding bytes of the I420 dump
   (stride 20/12 for width 17, the extra Y row for odd heights), which are not written by every path: never compare
   md5s of padded dumps at odd sizes, compare visible pixels. Neither v4l2sljpegdec (crop/stride from the driver's
   format: bytesperline 32, height 48 for 17x33, plane offsets from gst_v4l2_format_to_dma_drm_info()) nor
   cedrus_jpeg.c needed a change. Fixed: harness/gst-jpeg/compare.py and gaps/compare.py (layout), 02's compare.txt
   regenerated (z17x33 now `hw==drv EXACT`, PSNR 48.4/50.7/51.3 dB vs jpegdec).
2. **mjmix "hw 8640000 B vs sw 6912000 B": the hardware output was right, jpegdec's was short.** mjmix is 15 frames
   640x480 then 15 frames 320x240 (ffprobe): 15*460800 + 15*115200 = 8640000 = the hw size. The sw path lost the 15
   small frames: jpegparse set `width=320, height=480` on the 320x240 images (its interlaced-MJPEG heuristic takes the
   container height whenever it is larger than the image, also on a plain resolution change; the 02 decodebin log
   shows it), and jpegdec takes an image of half the caps height for a field and produced nothing for them.
   v4l2sljpegdec parses the image itself and was unaffected. **Fix: patches/gstreamer/0106** (jpegparse: use the
   container height only when the stream was found interlaced; take a smaller first image for a field only at the
   frame width). Source commit 53e6abb on branch opiz2 of build/gst-jpeg/src.
3. **dmesg "failed to parse JPEG header: -22" pairs: from the stateful `v4l2jpegdec`, not from our pipelines.** The
   direct `hw` runs of mj422/mj444 never sent a frame (`not-negotiated`, see out/mj422.hw.log). The kernel time of the
   30 pairs (222.8-223.3 s after the boot at 18:52:58 in harness/serial.log = 18:56:41) falls in the `norank` run
   (18:56:03-18:57:03): gst-plugins-good's stateful v4l2jpegdec queues OUTPUT buffers to cedrus without requests
   (JPEG does not require them, cedrus_video.c) whose contents fail v4l2_jpeg_parse_header(), 30+ times at 17 ms,
   then hangs (the known MARGINAL-override reason). The image is user data and the buffer comes back with
   V4L2_BUF_FLAG_ERROR, so the log lines are wrong in any case. **Kernel fix: fix/sunxi-cedrus-jpeg-quiet-refusals**
   (below): the JPEG refusals become dev_dbg(), the generic "Failed to setup decoding job" is rate-limited.
- Observation for the work list (not ours): jpegdec + videoconvert give wrong chroma for 4:1:1 images (s411 1080p:
  U/V 4.4 dB, z17x33-411: 7.5 dB against the driver and against ffmpeg's 4:1:1 resampled the same way). The 4:1:1
  software reference is therefore ffmpeg, not jpegdec (compare.py of the oddsize package does that).
- **Deferred (performance, not wrong output): throughput.** mj1080: v4l2sljpegdec 10.7 s vs jpegdec 4.9 s for 300
  1080p frames (~28 vs ~61 fps): one image in flight, synchronous request wait, memcpy of the bitstream into the
  OUTPUT buffer. Plan when picked up: two images in flight (second OUTPUT buffer already allocated), poll instead of
  wait, measure with `perf mj1080` of the 02 package (its line 11 has no threshold).

## What the hardware can do (checked against the driver and the vendor notes, 2026-11-05)
- cedrus_jpeg.c (kernel-check/work-cumul/linux-7.3.1 drivers/staging/media/sunxi/cedrus): the JPEG decoder is the
  MPEG engine. Quantisation goes through the two MPEG matrices (VE_DEC_MPEG_IQMINPUT INTRA = Y, NON_INTRA = chroma);
  the Huffman SRAM holds exactly four descriptors (Y-DC, Y-AC, C-DC, C-AC) and four HUFFVAL arrays, with no
  per-component selector register. The vendor libawmjpeg writes the same four tables (impl-di-jpeg-avs.md §7.1).
  So "Cb and Cr with different tables" is a true hardware limit, not a driver choice; the driver compares table
  *content*, so different selectors naming identical tables are fine (and must stay on the hardware path).
- Non-interleaved scans: the engine consumes one scan as interleaved MCUs of the trigger's chroma format (the
  greyscale probe in impl-di-jpeg-avs.md §7 showed it parsing a 1-component scan as a 3-component one). Merging
  per-component scans into one would need a full entropy decode on the CPU. True hardware limit.
- Both therefore go to jpegdec, decided at caps negotiation. No driver change for them; the driver's refusals stay
  as the last line of defence (now quiet, see the kernel fix).
- Picture size: a real limit (4096x2304 for JPEG) that the driver knew but did not report (framesizes fix).
- Odd sizes: the engine writes whole MCUs into a capture buffer of bytesperline ALIGN(width, 16) and height
  ALIGN(height, 16) (17x33 -> 32x48); the driver reports that format and GStreamer takes stride/offsets from it; the
  picture is cropped to WxH by the caps. Verified pixel-exact at 17x33 (4:2:0, 4:1:1); 06 covers the other layouts,
  1x1, 8x8, 1921x1081, 4095x2303.

## Design (patches/gstreamer, source build/gst-jpeg/src branch opiz2, commits 92e0dc5 c2c828c 289b52c 0ce2d76 42d3c43 53e6abb)
- 0101 v4l2codecs decoder: keep V4L2_BUF_FLAG_ERROR per request, `gst_v4l2_request_has_buf_error()`.
- 0102 jpegparse: `sampling-factors` caps field ("2x2:1x1:1x1"), renegotiates on change.
- 0103 v4l2codecs: `v4l2sl*jpegdec` (GstVideoDecoder subclass, rank PRIMARY+1), one image in flight, OUTPUT buffer
  sized from the image, 4:1:1 -> NV12/I420 only, full-range BT.601 output colorimetry.
- 0104 jpegparse: parses DQT, DHT and SOS too and sets `scans=(int)N` and
  `component-tables=(string){shared,luma-chroma,separate}` (table sharing by content; annex K defaults told apart by
  selector; tables in force when each scan starts; reset per image, MPF sub-images keep the primary's).
- 0105 v4l2sljpegdec: sink caps add `scans=1, component-tables={shared,luma-chroma}`; per-image check also parses
  DQT/DHT and refuses (element error) 16-bit DQT, Huffman selectors > 1, Cb/Cr tables differing in content.
- **0106 jpegparse (new)**: caps height from the container only for interlaced streams (fields); a smaller first
  image counts as a field only at the frame width. Fixes the resolution change in MJPEG containers for every
  downstream decoder that trusts the caps (jpegdec).
- Fallback semantics: caps refuse -> decodebin/playbin plug jpegdec (grey, RGB/CMYK, progressive, lossless, non-1x1
  chroma factors, 4:4:0, >1 scan, separate chroma tables, and with the framesizes kernel fix sizes above 4096x2304).
  Per-image element error remains for: 12-bit samples, SOF1 with Th 2/3, DNL (height 0), scan component order !=
  frame order. All rare and loud; jpegparse has no field for them.

## Kernel branches (armbian-build, pushed to `fork`, for the coordinator to merge into test-cumulative)
- **fix/sunxi-cedrus-enum-framesizes** (3c0ecd788, worktree wt-cedrus-framesizes; merged in c11+): cedrus
  `vidioc_enum_framesizes`, coded formats STEPWISE 16x16..cedrus_max_size() step 16, capture formats -EINVAL. Gives
  every v4l2sl* decoder a width/height range so 4096x4096 JPEG goes to jpegdec up front. Board check: 05 case
  z4096x4096 (SKIPPED on kernels without it).
- **fix/sunxi-cedrus-jpeg-quiet-refusals** (0324a5d4b on test-cumulative 626dff92e = c13, worktree
  wt-cedrus-jpeg-quiet, NOT merged): patch
  `patches.media/h616-jpeg/media-cedrus-jpeg-quiet-the-refusal-of-undecodable-images.patch` (end of series.conf).
  cedrus_jpeg.c: `cedrus_jpeg_fail()`, the header-parse failure and the "does not fit the capture format" message
  become dev_dbg(); cedrus_dec.c: "Failed to setup decoding job" -> dev_err_ratelimited(). Dry-run applies on the
  c13 tree, cedrus_jpeg.o/cedrus_dec.o compile with the kernel's flags (from the .cmd files, scratch copies),
  checkpatch --strict clean. Board check: 06's `NORANK:` dmesg count (+N recorded, drops to a few lines with the fix)
  and check 6 (every case `dmesg +0`).

## Test packages
- 02 (harness/gst-jpeg/, bundle build/gst-jpeg/bundle): unchanged but compare.py's layout fix; rerun not needed
  (its compare.txt was regenerated from the kept dumps: all stills `hw==drv EXACT`).
- 05 gaps (harness/gst-jpeg/gaps/, bundle-gaps, dev .so with 0101-0105): queued as before; compare.py layout fix
  only (its cases are even-sized, no effect).
- **06 oddsize (harness/gst-jpeg/oddsize/, bundle-oddsize, dev .so with 0101-0106, runner job
  harness/runner-queue/06-gst-jpeg-oddsize.md)**: gen-vectors.sh -> build/gst-jpeg/vec-oddsize (cases.txt:
  `NAME W H still SAMP` / `NAME 0 0 clip SEQ`): stills z17x33 (420), z17x33-411, z33x17-422, z15x15-444, z1x1, z8x8,
  z1921x1081, z2049x64, z4095x2303; clips mjmix (640x480*15,320x240*15), mjmix-up (320x240*15,640x480*15),
  mj-z33x17 (33x17*30; odd-size frames encoded with ImageMagick, ffmpeg's mjpeg encoder rounds odd sizes).
  board-test.sh per case: jpegparse caps sizes seen, hw, sw, db/pb/db3 (clips: pb3), drv (jpegtest -f yu12), and the
  number of kernel log lines the case added; then the `norank` run with its own count. compare.py (host, ffmpeg
  reference decoded at compare time): stills hw == drv exactly, vs ffmpeg Y max|d| <= 3, chroma max|d| <= 3 (4:2:0,
  4:1:1 with the driver's resampling formula) or PSNR >= 30 dB (4:2:2/4:4:4, engine-downsampled), autoplug picks
  v4l2sljpegdec with pixels == hw, caps == WxH, `dmesg +0`; clips: hw and sw sizes add up to SEQ, autoplug == hw,
  caps sizes == the SEQ sizes in order, hw vs jpegdec PSNR >= 48 dB, `dmesg +0`. Validated on the 02 dumps: z17x33
  and z17x33-411 PASS, mjmix (pre-0106) FAIL(caps,sw-size) as expected.

## Next steps
1. Runner: 05 (gaps) then 06 (oddsize) on any booted kernel; 06's NORANK dmesg count is informational until the
   quiet-refusals fix is in the cumulative kernel (c14+), then it should be a handful of rate-limited lines.
2. If 06 fails: `hw!=drv` or `y-ref`/`c-ref` on a still means a real crop/stride problem at that size (look at
   out/NAME.hw.yuv vs out/NAME.drv.yuv with compare.py's planes_gst/planes_tight); `caps` or `sw-size` on a clip
   means 0106 did not take (check that the bundle's libgstjpegformat.so is the 0106 build: inspect.txt lists the
   plugin path); `dmesg` on a case means our pipeline sent something the driver refused (out/dmesg.txt has the lines).
3. Then integration: `scripts/build-media-debs.sh gst-plugins-bad1.0` with patches/gstreamer 0101-0106, apply
   harness/research/gst-jpeg/image-integration.patch, image build, verify-board. Re-check the 02 package's check 4
   threshold (PSNR only).
4. Deferred: throughput (above). Work list: jpegdec/videoconvert 4:1:1 chroma (upstream GStreamer, affects only the
   software path); the stateful v4l2jpegdec hang on cedrus (gst-plugins-good; the MARGINAL override covers it).
