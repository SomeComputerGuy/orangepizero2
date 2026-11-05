# GStreamer hardware JPEG decode on cedrus (v4l2sljpegdec): state 2026-11-05

## Findings
- OPi5 has **no** stateless/V4L2 JPEG GStreamer element (patches/gstreamer 0001-0014: v4l2codecs caps, kmssink, h264/h265
  release, VP9 resize, stateless H.264/H.265 encoders; work/_out/jpeg-dec/DESIGN.md plans a stateful-style kernel JPEG
  for v4l2jpegdec). Their set is adopted unchanged as patches/gstreamer/0001-0014, ours on top as 0101-0103.
- cedrus JPEG takes one JFIF per OUTPUT buffer and parses it in the driver; requests are allowed (not required), no
  controls. Driver refusals (kernel `cedrus_jpeg_setup`): components != 3 (greyscale), chroma factors != 1x1, luma
  factors other than 2x2/2x1/1x1/4x1 (4:4:0 refused by v4l2_jpeg_parse_header), precision != 8, non-interleaved scan,
  Cb/Cr tables differing, > 4096x2304. 4:1:1 needs a linear capture format.
- jpegparse caps `sampling` cannot express the factor layout: FFmpeg writes 4:2:2 as Y2x2/C1x2 and 4:4:4 as 1x2 for all
  components (both refused by the hardware but named YCbCr-4:2:2 / 4:4:4). Refusing on the first frame cannot make
  decodebin fall back, so jpegparse now also exports `sampling-factors` ("2x2:1x1:1x1"), and the decoder's sink
  template keys on it.
- The hardware is not bit-exact with libjpeg (max |d| 1, Y ~65 dB, impl-di-jpeg-avs.md J2), so "md5 equal to jpegdec"
  cannot hold. The test instead checks md5(v4l2sljpegdec) == md5(jpegtest, same driver) and PSNR/max|d| vs jpegdec.
- v4l2jpegdec (gst-plugins-good, PRIMARY+1) stays MARGINAL in the image: it cannot drive cedrus (7.6) and at equal rank
  it sorts before v4l2sljpegdec. The override comment in userpatches gets updated with the integration patch.

## Design (patches/gstreamer)
- 0101 v4l2codecs decoder: keep V4L2_BUF_FLAG_ERROR per request, `gst_v4l2_request_has_buf_error()` (other decoders
  unchanged).
- 0102 jpegparse: `sampling-factors` caps field, renegotiates on change.
- 0103 v4l2codecs: `v4l2sl*jpegdec` (GstVideoDecoder subclass, rank PRIMARY+1). Sink: `image/jpeg, parsed=true,
  sof-marker={0,1}, colorspace=sYUV, sampling-factors={2x2:1x1:1x1, 2x1:1x1:1x1, 1x1:1x1:1x1, 4x1:1x1:1x1},
  interlace-mode=progressive` + device frame sizes. One image in flight (synchronous request), OUTPUT buffer sized from
  the image (renegotiates if a later one is bigger, or on size / 4:1:1 change). Per image: unsupported (12-bit,
  non-interleaved) = element error; corrupt or driver error flag = dropped frame (GST_VIDEO_DECODER_ERROR). 4:1:1 ->
  NV12/I420 only. Output colorimetry full-range BT.601 like jpegdec.

## Code state
- Source git: build/gst-jpeg/src (clone of ~/orangepi5/work/gst-reopen), branch `opiz2`: Ubuntu 1.28.6-1ubuntu1 +
  OPi5 0001-0014 + ours (0101-0103 = the last three commits; local tree, nothing pushed). The bundled dev .so predates
  only a cosmetic `#define GST_USE_UNSTABLE_API` in 0103.
- Exported: patches/gstreamer/0101-0103 (project repo). scripts/build-media-debs.sh knows gst-plugins-bad1.0
  (+opiz2.1, PDIR gstreamer) but does not build it by default.
- Dev build (arm64 .so only, ~5 min): harness/gst-jpeg/build-dev.sh -> build/gst-jpeg/out/{libgstv4l2codecs,libgstjpegformat}.so.
  It compiles with no warnings in our files. **Never run on the board.**
- Image integration (not applied): harness/research/gst-jpeg/image-integration.patch = build.sh builds
  gst-plugins-bad1.0 for every variant + config hook `post_repo_customize_image__opiz2_gst_media` (minimal/server get
  the gst-plugins-bad packages from /opt/opiz2-media, pinned) + updated v4l2jpegdec comment. These hunks had been swept
  into 1c65b98 by another commit while untested; they are reverted in this commit.

## Next steps
1. Runner job harness/runner-queue/01-gst-jpeg.md (package harness/gst-jpeg/HANDOFF.md) on the booted kernel. If the
   coordinator wants the newest cN, install it first (harness/research/vdec-perf/install-kernel.sh cN) - not in the job.
2. Fix what fails (likely spots: the bitstream sizing in negotiate, the 4:1:1 linear-format filter, decodebin3
   picking), rebuild with build-dev.sh, rerun.
3. When checks 2-9 pass: run
   `scripts/build-media-debs.sh gst-plugins-bad1.0` (cold ccache, ~1-2 h qemu), `git apply
   harness/research/gst-jpeg/image-integration.patch`, add gst-plugins-bad1.0 to the default SOURCES, image build,
   verify-board on the image (gst-inspect v4l2sljpegdec, playbin on a 4:2:0 JPEG picks it).
4. Open: images whose Cb/Cr tables differ (crtable) or with non-interleaved baseline scans pass the caps and fail per
   frame (dropped, no fallback); jpegparse does not parse DQT, so no caps-level refusal for those.
