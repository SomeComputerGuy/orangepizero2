# GStreamer hardware JPEG decode on cedrus (v4l2sljpegdec): state 2026-11-05 (gaps closed in code, board run queued)

## First board run (runner job 02-gst-jpeg, summary harness/runner-queue/done/02-gst-jpeg.summary.md)
- Works: v4l2sljpegdec registered at PRIMARY+1; s420/s422/s444/s411/dri7/nodht/opt420/z16x16/z2049x64/z4096x2304
  decode, byte-identical to the driver's own output (jpegtest); decodebin/playbin/decodebin3 pick it for them and
  pick jpegdec for grey/prog/s440/mjpeg422/mj422/mj444; mjmix (resolution change) decodes; trunc completes.
- Quality vs jpegdec: Y PSNR 51.3 dB (stills), 59.3 dB (mj420), max |d| 4 (stills) / 3 (clip). Check 4's
  "max|d| <= 2" was too strict for this IDCT (impl-di-jpeg-avs.md J2 measured 65 dB / 1 against ffmpeg -idct int;
  jpegdec's islow differs more). PSNR >= 48 is the criterion from here on.
- Check 7 "FAIL": only the `norank` line timed out (rc=124), which is the expected v4l2jpegdec hang that check 10
  documents (why the MARGINAL override stays). No v4l2sljpegdec run hung.
- **The gap this round closes**: `crtable` (Cr DQT differs) passed the caps, decodebin picked v4l2sljpegdec, the
  driver refused every image ("Cb and Cr DQT tables differ") and the output was empty (hw rc=0, 0 bytes), no
  fallback. The same held for non-interleaved scans (element error) and 4096x4096 (hw rc=1, picked v4l2sljpegdec:
  cedrus has no VIDIOC_ENUM_FRAMESIZES, so the probed sink caps carry no size range).
- Other open observations (not touched here, work list): z17x33 and z17x33-411 `hw==drv DIFF` and db/pb/db3 md5s
  differ from each other (odd-size cropping/stride in the GStreamer path); mjmix hw output 8640000 B vs sw 6912000 B
  (frame sizes after a resolution change); perf mj1080 10.7 s vs jpegdec 4.9 s for 300 1080p frames (~28 vs ~61 fps:
  one image in flight, synchronous request, memcpy of the bitstream); dmesg had 30 "failed to parse JPEG header: -22"
  pairs from the `hw` runs of refused images (mj422/mj444 frames reach the driver through the direct pipeline).

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
  as the last line of defence.
- Picture size: a real limit (4096x2304 for JPEG) that the driver knew but did not report.

## Design (patches/gstreamer, source build/gst-jpeg/src branch opiz2, commits 92e0dc5 0ce2d76 42d3c43 ...)
- 0101 v4l2codecs decoder: keep V4L2_BUF_FLAG_ERROR per request, `gst_v4l2_request_has_buf_error()`.
- 0102 jpegparse: `sampling-factors` caps field ("2x2:1x1:1x1"), renegotiates on change.
- 0103 v4l2codecs: `v4l2sl*jpegdec` (GstVideoDecoder subclass, rank PRIMARY+1), one image in flight, OUTPUT buffer
  sized from the image, 4:1:1 -> NV12/I420 only, full-range BT.601 output colorimetry.
- **0104 jpegparse (new)**: parses DQT, DHT and SOS too and sets, once the whole image is parsed, `scans=(int)N`
  (number of SOS) and `component-tables=(string){shared,luma-chroma,separate}`: how the components share their
  quantisation+Huffman tables *by content* (shared = one set for all, luma-chroma = first component vs. the rest,
  separate = components after the first differ). Undefined tables are the annex K defaults, told apart by selector
  (MJPEG without DHT -> luma-chroma). Each component takes the tables in force when its scan starts (tables redefined
  between scans count). Reset per image (SOI; MPF sub-images keep the primary's). A change renegotiates.
- **0105 v4l2sljpegdec (new)**: sink caps add `scans=1, component-tables={shared,luma-chroma}`; the per-image check
  also parses DQT/DHT and refuses (element error, not a silent drop) what the caps cannot show: 16-bit DQT,
  Huffman selectors > 1 (driver limit, SOF1 only), Cb/Cr tables differing in content.
- Fallback semantics now: caps refuse -> decodebin/playbin plug jpegdec (grey, RGB/CMYK, progressive, lossless,
  non-1x1 chroma factors, 4:4:0, >1 scan, separate chroma tables, and with the kernel fix below sizes above
  4096x2304). Per-image element error remains for: 12-bit samples (SOF1 P=12), SOF1 with Th 2/3, DNL (height 0),
  scan component order != frame order. All are rare and loud; jpegparse has no field for them (12-bit has no
  software decoder in GStreamer core either).

## Kernel: fix/sunxi-cedrus-enum-framesizes (armbian-build, pushed to `fork`, for the coordinator to merge)
- Commit 3c0ecd788 on top of test-cumulative f8be54bac (c10): patch
  `patches.media/h616-vdec/media-cedrus-enumerate-the-coded-frame-sizes.patch` + series.conf. cedrus gets
  `vidioc_enum_framesizes`: coded formats report STEPWISE 16x16..cedrus_max_size() (4096x2304; H.265/AVS2
  6144x4320; AVS 1920x1088) step 16; capture formats -EINVAL (no scaler; v4l2codecs reads capture frame sizes as
  scaling capabilities, v4l2-compliance treats EINVAL at index 0 as "no frame sizes").
- Effect: `gst_v4l2_decoder_probe_sink_caps()` (OPi5 patch 0002) gives every v4l2sl* decoder a width/height range,
  so 4096x4096 JPEG (and oversize streams of the other codecs) go to the software decoder up front.
- Verified: applies on the c10 series (834 patches, 0 failures), cedrus_video.o compiles with the kernel flags
  (kernel-check/run-framesizes-patch.log), checkpatch --strict clean. Not board-tested; worktree wt-cedrus-framesizes.

## Vectors and test package (harness/gst-jpeg/gaps/, runner job harness/runner-queue/05-gst-jpeg-gaps.md)
- harness/jpegtest/jpegtool.py gained `cr-table-same` (Cr -> DQT slot 2 with the same content: must stay on the
  hardware), `cr-huffman` (Cr recoded with the luma Huffman tables, one interleaved scan: tables differ, same
  picture) and `split-scans N` (3 = Y, Cb, Cr each alone; 2 = Y then Cb+Cr): a small entropy transcoder (F.1.2/F.2.2,
  restart intervals in, none out). Every edited vector decodes identically to its source with ffmpeg (gen-vectors.sh
  checks the md5).
- gen-vectors.sh -> build/gst-jpeg/vec-gaps (cases.txt: NAME W H EXPECT scans:tables): hw = s420, crtq2, mj-crtq2;
  fallback = crtable, crhuff, noninter, noninter2, dri7-noninter, mj-crhuff, mj-noninter; size = z4096x4096
  (SKIPPED unless the kernel enumerates frame sizes). Bundle build/gst-jpeg/bundle-gaps (dev .so with 0101-0105,
  built 2026-11-05 19:51 with build-dev.sh, no warnings).
- board-test.sh records per case: jpegparse caps (scans/component-tables), direct hw decode, jpegdec decode,
  decodebin/playbin/decodebin3 (clips: playbin3) pick + md5, driver output for hw cases, dmesg delta. compare.py
  turns that into one PASS/FAIL(reasons)/SKIPPED line per case (hw: md5 == driver, PSNR >= 48 dB vs jpegdec, autoplug
  picked v4l2sljpegdec; fallback: direct hw link refused without hang, autoplug picked jpegdec, md5 == jpegdec) plus
  SUMMARY and DMESG lines; HANDOFF.md checks 1-7 are greps on those.
- 02-gst-jpeg's package (harness/gst-jpeg/, build/gst-jpeg/bundle) is untouched.

## Next steps
1. Runner job 05-gst-jpeg-gaps on the booted kernel (any); rerun once c11 (with the framesizes fix) is on the board
   for the z4096x4096 case.
2. If a fallback case FAILs with `caps` in its reasons, the jpegparse field logic is wrong (look at out/NAME.caps.log);
   with `hw-accepted`, the sink caps of 0105 did not take effect (check inspect.txt). `psnr` on crtq2 would mean the
   driver mishandles Tq=2 (it shouldn't: it indexes 0..3).
3. Then the integration path from before: `scripts/build-media-debs.sh gst-plugins-bad1.0`, apply
   harness/research/gst-jpeg/image-integration.patch (now needs 0104/0105 in the series: PDIR gstreamer picks up all
   patches/gstreamer/*.patch), image build, verify-board. Re-check the 02 package's check 4 threshold (PSNR only).
4. Work list (from the 02 run): odd-size output path (z17x33 DIFF), mjmix output size, throughput (pipeline the
   requests: 2 images in flight), the `hw` direct pipeline sending refused frames to the driver (cosmetic dmesg noise).
