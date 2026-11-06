# GStreamer hardware JPEG decode on cedrus (v4l2sljpegdec + stateful v4l2jpegdec): state 2026-11-06 (job 22 PASS on c24; stateful v4l2jpegdec hang root-caused = cedrus refused V4L2_DEC_CMD_STOP, kernel fix in c41, runner job 56 queued)

## Rounds so far
- 02-gst-jpeg (done, build/gst-jpeg/results/, summary harness/runner-queue/done/02-gst-jpeg.summary.md): hardware path
  works and is byte-identical to the driver's own output; the three "wrong output" items it left are closed below.
- 05-gst-jpeg-gaps (done, build/gst-jpeg/results-gaps/, summary done/05-gst-jpeg-gaps.summary.md): 10 of 11 PASS on the
  stock kernel (#17, no ENUM_FRAMESIZES). All caps refusals (separate tables, multi-scan, also in MJPEG) -> jpegdec,
  hw cases bit-identical to the driver, DMESG clean. z4096x4096 FAIL = test bug, see below.
- 06-gst-jpeg-oddsize (done, build/gst-jpeg/results-oddsize/, summary done/06-gst-jpeg-oddsize.summary.md): 9 of 12
  PASS; every still hw == driver exactly, every case `dmesg +0`, mjmix/mjmix-up (0106) PASS. The 3 FAILs = test bugs,
  see below; compare.txt regenerated with the fixed reference: 12 of 12 PASS (original kept as compare.run1.txt).
- 11-gst-jpeg-recheck (queued, harness/runner-queue/11-gst-jpeg-recheck.md): the failing cases of both on the newest
  cumulative kernel with patches 0101-0107. Package harness/gst-jpeg/recheck/, bundle build/gst-jpeg/bundle-recheck.

## Stateful v4l2jpegdec hang (work-list item) root-caused 2026-11-06: cedrus refused V4L2_DEC_CMD_STOP; kernel fix c41
Evidence: job 22 out/norank16.gstdebug.txt (build/gst-jpeg/results-recheck/out/) and out/dmesg.txt.
- Is cedrus JPEG a stateful-looking node? Yes, by design: the 2024 JPEG series (Gil Peyrot / Skrabec,
  "Don't require requests for all codecs") decodes JPEG without requests (the driver parses the whole image), on the
  same /dev/video0 decoder node, source format V4L2_PIX_FMT_JPEG, capture NV12/NV21/YU12/YV12. That is exactly the
  stateful JPEG decoder shape gst-plugins-good (and FFmpeg v4l2m2m) autoplug, and it decodes correctly that way: in the
  log frame 0 (1920x1088) is decoded and output (`Got buffer for frame number 0`). So the autoplug is not wrong and no
  caps/rank change is warranted; the driver lacked one piece of the stateful interface.
- The hang: at EOS gst_v4l2_video_dec_finish() sends V4L2_DEC_CMD_STOP; cedrus only had
  v4l2_m2m_ioctl_stateless_decoder_cmd (FLUSH only) -> `Failed to send decoder command 1 ... (Invalid argument)`.
  GStreamer then falls back to queueing empty OUTPUT buffers until the capture side reports EOS. vb2 makes each a
  full-length buffer ("use of bytesused == 0 is deprecated"), the JPEG parser refuses it ("Failed to setup decoding job:
  -22", ~50/s, ratelimited -> dmesg +133), the capture buffer returns with ERROR and a stale timestamp ("Driver bug
  detected", "frame number 4293", "Decoder is producing too many buffers"), and the loop repeats until timeout 60
  (rc=124). Not a gst-plugins-good bug: it handles a LAST-flagged buffer / -EPIPE properly.
- Fix (kernel, armbian-build fix/sunxi-cedrus-jpeg-stop-drain 950c46035, worktree wt-jpeg-stop, pushed to fork;
  merged into test-cumulative 39b1dce3f = **c41**; patch
  patches.media/h616-jpeg/media-cedrus-jpeg-drain-on-V4L2_DEC_CMD_STOP.patch at the end of series.conf): for the JPEG
  source format, (try_)decoder_cmd use the stateful m2m helpers (STOP/START); cedrus_job_finish() (irq, watchdog,
  setup-error paths) flags the capture buffer of the last source buffer queued before STOP with V4L2_BUF_FLAG_LAST and
  marks the context stopped; buf_queue completes a capture buffer queued after the drain as an empty LAST buffer;
  start/stop_streaming update the m2m drain state; START clears last_buffer_dequeued and reschedules. The other
  codecs keep the stateless FLUSH (they never enter the draining state). Build-check: 877 patches, 0 failed, build exit
  0, 0 C warnings, dtbs exit 0; checkpatch --strict clean. No GStreamer change and no rank change.
- MARGINAL override (image-integration.patch, GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL): keep it. With the fix
  v4l2jpegdec works, but it is a wrong autoplug at equal rank: it sorts before v4l2sljpegdec and its caps cannot refuse
  what the engine cannot decode (greyscale, multi-scan, separate chroma tables, 16-bit DQT), so those would become
  decode errors instead of falling back to jpegdec, while v4l2sljpegdec's caps (0102/0104/0105) route them. Update the
  comment in image-integration.patch from "cannot drive cedrus / hangs" to that reason when the integration is done.
- Board check: runner job 56 (harness/runner-queue/56-gst-jpeg-stateful.md, package harness/gst-jpeg/stateful/:
  make-bundle.sh -> build/gst-jpeg/bundle-stateful, board-test.sh, check.sh, run-job.sh (resumable, PAUSE file, stall
  watchdog, restore-kernel.sh), HANDOFF.md checks C0-C7). Results build/gst-jpeg/results-stateful/compare.txt.
  If C1-C4 fail with `cmdfail>0`: the board did not run c41+ (kernel.txt). If `cmdfail=0` but rc=124: read
  out/sf-*.gstdebug.txt for "Waiting for decoder stop" without a following "Done draining" (LAST never delivered: check
  out/dmesg.txt and the drain path in cedrus_job_finish). md5 != v4l2sljpegdec at equal size: compare the NV12
  format/stride both negotiated (out/*.log caps lines).

## Job 11 analysed (2026-11-06): 8 of 8 cases PASS on c17, checks 1 and 8 had wrong expectations, no hardware fault
Summary harness/runner-queue/done/11-gst-jpeg-recheck.summary.md, results kept in build/gst-jpeg/results-recheck-job11/.
Every case PASS: z4096x4096 refused by the caps and decoded by jpegdec, 1x1/8x8/15x15 on the hardware (0107 effective),
odd-size 4:2:2/4:4:4/4:1:1 stills and the 33x17 clip within max|d| 1 of the engine reference, hw == driver, `dmesg +0`
everywhere, DMESG clean.
1. **Check 1 `INSPECT: FAIL(name)`: wrong expectation.** compare.py wanted a line `Name v4l2sljpegdec`; gst-inspect-1.0
   prints `Name` only under "Plugin Details" and that is the plugin's name (`v4l2codecs`), never the element's. The
   element is now proven by `gst-inspect-1.0 --exists v4l2sljpegdec` (`EXISTS=0` in inspect.txt) plus the Long-name;
   the Rank and sink-range checks are unchanged.
2. **Check 8 `NORANK` picked v4l2sljpegdec, rc=0, dmesg +0: wrong expectation, and the explanation of the "hang".**
   out/norank.gstdebug.txt (442 bytes) shows what happened without the rank override: decodebin tried the stateful
   `v4l2jpegdec0` first (`Opening`), it answered `Returning sink caps EMPTY` and was closed, then v4l2sljpegdec decoded
   the picture. Cause: the cumulative kernel enumerates frame sizes (c11+, media-cedrus-enumerate-the-coded-frame-sizes:
   stepwise 16..4096 x 16..2304, **step 16**); gst-plugins-good's probe (gstv4l2object.c gst_v4l2_object_probe_caps_for_format,
   `gst_value_set_int_range_step`) turns that into `width=[16,4096,16], height=[16,2304,16]` in the stateful decoder's
   sink caps, so 1921x1081 does not intersect and the stateful decoder declines. On the stock kernel (no ENUM_FRAMESIZES)
   it took the picture and hung (05/06). Consequence for the work-list item "stateful v4l2jpegdec hang": with c11+ it
   only happens for pictures whose width and height are multiples of 16; the MARGINAL override stays. The norank check
   now expects exactly this (rc=0, picked v4l2sljpegdec, dmesg +0, `stateful-empty-caps` >= 1 from the GST_DEBUG log),
   and a second run `norank16` (new vector z1920x1088.jpg, 16-aligned) goes to the stateful decoder and is recorded
   (rc, picked, dmesg +N, GST_DEBUG log) for the work-list analysis, not judged.
Rerun: harness/runner-queue/22-gst-jpeg-recheck2.md (bundle-recheck rebuilt with the new vector and board-test.sh).

## Jobs 05 and 06 analysed on the host (2026-11-05 night): four test bugs, one real gap (patch 0107), no hardware fault
1. **05 z4096x4096 "not refused" (KSIZES=1): test bug.** gaps/board-test.sh derived KSIZES from `grep '^ *width: \['`
   over the whole gst-inspect output, which matched the SRC template (`width: [ 1, 2147483647 ]`, always there). The
   SINK template of the run had no width/height at all (inspect.txt), i.e. the kernel (#17 of Oct 30, the stock image
   kernel) has no ENUM_FRAMESIZES and the case should have been SKIPPED. Neither the element (probe_sink_caps puts the
   STEPWISE range into the sink template when the ioctl works), nor jpegparse (caps had width=4096, height=4096), nor
   the kernel range was at fault; cedrus S_FMT clamps to cedrus_max_size(), gst_v4l2_decoder_set_sink_fmt() sees the
   smaller size and fails with EINVAL, the loud element error of 05's log. Fixed: KSIZES now looks at the SINK
   template section only (gaps/board-test.sh; recheck/board-test.sh; compare.py prints the sink range).
2. **Found while fixing 1, a real gap: the sink range would have put sub-macroblock pictures on jpegdec.** With
   ENUM_FRAMESIZES the sink caps became `width: [16, 4096], height: [16, 2304]` (cedrus_enum_framesizes reports
   CEDRUS_MIN_WIDTH/HEIGHT = 16), so on a c11+ kernel 1x1, 8x8 and 15x15 JPEGs would be refused by the caps and
   decoded by jpegdec, although the hardware decodes them (06: z1x1, z8x8, z15x15-444 hw == driver). The minimum is a
   coded-size constraint (the driver rounds the format up), only the maximum excludes a decoder. **Patch 0107**
   (v4l2codecs decoder, gst_v4l2_decoder_probe_sink_caps(): lower bound 1 for STEPWISE), source commit 4a9abbf on
   branch opiz2. No kernel change: ENUM_FRAMESIZES reporting the coded minimum is what V4L2 drivers do (Hantro: 48).
3. **06 z33x17-422 / z15x15-444 FAIL(c-ref): test bug (reference model), hardware right.** hw == driver exactly for
   both. The engine's 4:2:0 output is: 4:2:2 -> rows averaged in pairs with rounding, 4:4:4 -> columns averaged in
   pairs then rows, both including the MCU padding column/row the encoder wrote (modelled by decoding the image with
   ffmpeg at the SOF size rounded up to whole MCUs). Against that model the dumps are within max|d| 1 on every plane
   (33x17 4:2:2, 15x15 4:4:4, and the 02 1080p s422/s444 dumps). compare.py had used ffmpeg's swscale yuvj420p
   output, which is a different filter: 27 dB (and 43-47 dB even at 1080p), fine for the 30 dB threshold only on
   large smooth pictures. Fixed: recheck/compare.py `engine_ref()` (also the 4:1:1 driver formula and 4:2:0, all at
   max|d| <= 3); oddsize/compare.py now runs it.
4. **06 mj-z33x17 FAIL(psnr): test bug (threshold).** hw vs jpegdec min PSNR 47.48 dB over 30 frames against a 48 dB
   threshold; hw vs ffmpeg (-idct int) per frame max|d| 1/1/1 (63.9/63.0/62.2 dB). The 48 dB is just the IDCT
   difference between the engine and libjpeg-turbo on a 33x17 frame (the stills show the same 47-48.6 dB at that
   size, 51 dB at 1080p). Fixed: clips are checked per frame against the ffmpeg reference (max|d| <= 3); the jpegdec
   PSNR is reported only.
5. **06 check 1 "no v4l2sljpegdec in inspect.txt": test bug.** The gst-inspect grep filter dropped the `Name` line.
   Fixed in oddsize/, gaps/ and recheck/board-test.sh (`Name` added to the filter).
6. **06 norank `dmesg +1055`, rc=124: not our pipeline, known work-list item, recorded as designed.** The
   `GST_PLUGIN_FEATURE_RANK=` run lets gst-plugins-good's stateful `v4l2jpegdec` (same rank 257) win; it queues
   buffers cedrus refuses (`failed to parse JPEG header: -22` / `Failed to setup decoding job: -22`, 527 pairs at
   46 ms) and never finishes. The kernel lines are the ones fix/sunxi-cedrus-jpeg-quiet-refusals demotes (merged as
   c14 = 0324a5d4b; job 06 ran on the stock kernel). Why the stateful element's buffers fail the header parse is
   still unknown (not truncation: z1921x1081.jpg is 595 KB, gst-plugins-good's encoded buffer is w*h*12/8/2 =
   1.56 MB); the recheck job records a `GST_DEBUG=v4l2videodec:6,v4l2bufferpool:6` log of that run
   (out/norank.gstdebug.txt) for the work-list item. The MARGINAL override stays until it is understood.

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
- **0106 jpegparse**: caps height from the container only for interlaced streams (fields); a smaller first
  image counts as a field only at the frame width. Fixes the resolution change in MJPEG containers for every
  downstream decoder that trusts the caps (jpegdec). Verified by 06 (mjmix, mjmix-up PASS, caps 640x480 320x240).
- **0107 v4l2codecs decoder (new, commit 4a9abbf)**: gst_v4l2_decoder_probe_sink_caps() uses 1 as the lower bound of
  the STEPWISE width/height range (the minimum is the coded size, only the maximum excludes a decoder), so 1x1..15x15
  pictures stay on the hardware path on kernels with ENUM_FRAMESIZES. Affects every v4l2sl* decoder (0002 series).
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
  wt-cedrus-jpeg-quiet; merged as c14 = 0324a5d4b per kernel-check/cumulative-kernels.txt): patch
  `patches.media/h616-jpeg/media-cedrus-jpeg-quiet-the-refusal-of-undecodable-images.patch` (end of series.conf).
  cedrus_jpeg.c: `cedrus_jpeg_fail()`, the header-parse failure and the "does not fit the capture format" message
  become dev_dbg(); cedrus_dec.c: "Failed to setup decoding job" -> dev_err_ratelimited(). Dry-run applies on the
  c13 tree, cedrus_jpeg.o/cedrus_dec.o compile with the kernel's flags (from the .cmd files, scratch copies),
  checkpatch --strict clean. Board check: 06's `NORANK:` dmesg count (+N recorded, drops to a few lines with the fix)
  and check 6 (every case `dmesg +0`).

## Test packages
- 02 (harness/gst-jpeg/, bundle build/gst-jpeg/bundle): unchanged but compare.py's layout fix; rerun not needed
  (its compare.txt was regenerated from the kept dumps: all stills `hw==drv EXACT`).
- 05 gaps (harness/gst-jpeg/gaps/, bundle-gaps, dev .so with 0101-0105): done; board-test.sh KSIZES/Name fixed for
  any rerun (the bundle's copy is the old one: re-copy board-test.sh into the bundle before a rerun).
- **11 recheck (harness/gst-jpeg/recheck/: make-bundle.sh -> build/gst-jpeg/bundle-recheck, run-job.sh, board-test.sh,
  compare.py, HANDOFF.md; dev .so with 0101-0107 from build/gst-jpeg/out, build log build-dev-recheck.log)**: installs
  the newest cumulative kernel (vp9-vectors/run-job.sh pattern), cases s420, z17x33-411, z33x17-422, z15x15-444, z1x1,
  z8x8 (still), z4096x4096 (size: must fall back), mj-z33x17 (clip), norank with GST_DEBUG log; restores the stock
  kernel. compare.py (shared with oddsize/) checks INSPECT (Name, rank, `sink-range ok` = lower bound 1), stills and
  clip frames vs the engine-exact ffmpeg reference (max|d| <= 3), hw == driver, autoplug, caps sizes, `dmesg +0`.
- 06 oddsize (harness/gst-jpeg/oddsize/, bundle-oddsize, dev .so with 0101-0106, runner job
  harness/runner-queue/06-gst-jpeg-oddsize.md): done. gen-vectors.sh -> build/gst-jpeg/vec-oddsize (cases.txt:
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
0. Job 22 ran on c24 (2026-11-06): PASS (8/8, INSPECT, NORANK; NORANK16 recorded as expected). Next: job 56 (stateful
   v4l2jpegdec on c41), then the integration in step 3.
1. (done) Runner: job 22 (recheck rerun). Expected: INSPECT PASS `KSIZES=1; sink-range ok width=[1,4096] height=[1,2304]`,
   8 of 8 PASS, every `dmesg +0`, NORANK PASS (stateful declines 1921x1081), NORANK16 recorded (rc=124 and some dmesg
   lines expected; out/norank16.gstdebug.txt is the log for the work-list item).
2. If 11 fails: `sink-range BAD` = the bundle is not the 0107 build (BUILD.txt in the bundle names the commit);
   z4096x4096 `db/pb/db3` = the caps range did not exclude it (inspect.txt SINK template); z1x1/z8x8/z15x15 `db`
   with picked jpegdec = 0107 not effective; `hw!=drv` or `y-ref`/`c-ref` on a still = a real crop/stride problem
   at that size (out/NAME.hw.yuv vs out/NAME.drv.yuv with compare.py's planes_gst/planes_tight); `ref` on the clip =
   look at the per-frame max|d|; `dmesg` on a case = our pipeline sent something the driver refused (out/dmesg.txt).
3. Then integration: `scripts/build-media-debs.sh gst-plugins-bad1.0` with patches/gstreamer 0101-0107, apply
   harness/research/gst-jpeg/image-integration.patch, image build, verify-board. Re-check the 02 package's check 4
   threshold (PSNR only; use recheck/compare.py's reference instead).
4. Deferred: throughput (above). Work list: jpegdec/videoconvert 4:1:1 chroma (upstream GStreamer, affects only the
   software path). The stateful v4l2jpegdec hang is root-caused and fixed in c41 (section above); runner job 56.
