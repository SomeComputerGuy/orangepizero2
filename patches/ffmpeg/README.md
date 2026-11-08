# FFmpeg v4l2-request patches

Base: Ubuntu `ffmpeg 7:8.1.2-2ubuntu2` (= FFmpeg tag n8.1.2). Applied in file-name order, appended to
debian/patches/series (scripts/build-media-debs.sh). All 36 apply with fuzz 0 on the Ubuntu source.

| range | source |
|---|---|
| 0001-0011 | Jonas Karlman (Kwiboo) et al., V4L2 Request API hwaccels, FFmpeg PR 20847, head 3ac4e07593 (2026-03-12, newest revision; PR still open) via github.com/Kwiboo/FFmpeg v4l2-request-n8.1 (b57fbbe50c~2). Code identical to the PR head |
| 0012 | HEVC SPS short/long-term RPS controls (probes the controls, no-op on cedrus) |
| 0013 | Alexander Kanavin: ffbuild race fix (upstream backport) |
| 0101-0102 | Kwiboo v4l2-request-n8.1: AFBC_16X16_SPLIT (Jernej Skrabec) and BROADCOM_SAND128 (Jonas Karlman) capture formats |
| 0201-0208 | Jernej Skrabec, github.com/jernejsk/FFmpeg v4l2request-mpeg4 a56a208b07: VC-1 fixes + VC-1/WMV3 hwaccel, MPEG-4 Part 2/H.263/Sorenson Spark hwaccels (patch-id identical to his commits) |
| 0301-0308 | MPEG-4 field-direct fix, interlaced-B software fallback, GMC1 rshift, MPEG-1 hwaccel, AVS1/AVS+ (cavs) hwaccel, native hwaccel-only AVS2 decoder + AVS2 hwaccel |
| 0309 | D-pictures only reach hwaccels that declare HWACCEL_CAP_MPEG1_D_PICTURES and whose device accepts coding type D in VIDIOC_TRY_EXT_CTRLS (fixes 0304; Hantro: D-pictures rejected like in software) |
| 0310 | FATE vc1test_smm0005 reference for Jernej's 0201/0202 B-picture fixes |
| 0311 | FATE source list gains the four local uAPI headers |
| 0312 | AFBC fourcc fallbacks for distro headers |
| 0313 | AVS2 decoder output hold-back for asynchronous hwaccels (two decode requests in flight on v4l2request; `-flags low_delay` turns it off) |
| 0320 | crop the decoder's compose offset (cedrus H.265 AFBC is stored 4 lines down; kernel compose rectangle) |
| debian/0001 | packaging: --enable-v4l2-request --enable-libudev |

uAPIs expected by the add-on hwaccels (local copies in libavcodec/v4l2-stateless-*.h, used only when the kernel
headers lack them): VC-1 600-604 + profile/level 658-659, MPEG-4 700-704, H.263 800-801, AVS2 900-903, AVS 1000-1002,
MPEG-1 flags in the MPEG-2 controls. For MPEG-1, 0304 probes `V4L2_PIX_FMT_MPEG1_SLICE` ('MG1S', 0x5331474d), so
kernels whose decoders only offer `V4L2_PIX_FMT_MPEG2_SLICE` fall back to software.

Trailers: third-party patches unchanged; our own patches carry `Assisted-by: LLM` and a `Signed-off-by`.
