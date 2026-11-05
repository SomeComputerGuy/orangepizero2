# Shared FFmpeg v4l2-request series (orangepi5 RK3588 + orangepizero2 H616)

Base: Ubuntu `ffmpeg 7:8.1.2-2ubuntu2` (= FFmpeg tag n8.1.2). Applied in file-name order, appended to
debian/patches/series (scripts/build-media-debs.sh). All 35 apply with fuzz 0 on the Ubuntu source.

| range | source |
|---|---|
| 0001-0011 | Jonas Karlman (Kwiboo) et al., V4L2 Request API hwaccels, FFmpeg PR 20847, head 3ac4e07593 (2026-03-12, newest revision; PR still open) via github.com/Kwiboo/FFmpeg v4l2-request-n8.1 (b57fbbe50c~2). Code identical to the PR head. `Link:` lines are provenance added by orangepi5 |
| 0012 | orangepi5: HEVC SPS short/long-term RPS controls (probes the controls, no-op on cedrus) |
| 0013 | Alexander Kanavin: ffbuild race fix (upstream backport) |
| 0101-0102 | Kwiboo v4l2-request-n8.1: AFBC_16X16_SPLIT (Jernej Skrabec) and BROADCOM_SAND128 (Jonas Karlman) capture formats |
| 0201-0208 | Jernej Skrabec, github.com/jernejsk/FFmpeg v4l2request-mpeg4 a56a208b07: VC-1 fixes + VC-1/WMV3 hwaccel, MPEG-4 Part 2/H.263/Sorenson Spark hwaccels (patch-id identical to his commits) |
| 0301-0308 | orangepizero2: MPEG-4 field-direct fix, interlaced-B software fallback, GMC1 rshift, MPEG-1 hwaccel, AVS1/AVS+ (cavs) hwaccel, native hwaccel-only AVS2 decoder + AVS2 hwaccel |
| 0309 | shared glue: D-pictures only reach hwaccels that declare HWACCEL_CAP_MPEG1_D_PICTURES and whose device accepts coding type D in VIDIOC_TRY_EXT_CTRLS (fixes 0304; Hantro: D-pictures rejected like in software) |
| 0310 | shared glue: FATE vc1test_smm0005 reference for Jernej's 0201/0202 B-picture fixes |
| 0311 | shared glue: FATE source list gains the four local uAPI headers |
| 0312 | shared glue: AFBC fourcc fallbacks for distro headers |
| debian/0001 | packaging: --enable-v4l2-request --enable-libudev |

uAPIs expected by the add-on hwaccels (local copies in libavcodec/v4l2-stateless-*.h, used only when the kernel
headers lack them): VC-1 600-604 + profile/level 658-659, MPEG-4 700-704, H.263 800-801, AVS2 900-903 (avs2-v5,
d0aa5a388 = orangepi5 k15-avs2), AVS 1000-1002 (d5f4c3d35 = orangepi5 k15-avsp), MPEG-1 flags in the MPEG-2
controls (7828d5a1f = orangepi5 k15-mpeg1).
MPEG-1 coded format: 0304 probes `V4L2_PIX_FMT_MPEG1_SLICE` ('MG1S', 0x5331474d; orangepi5 k15-mpeg1 f22ca213f036,
proposal in work/_out/mpeg1-rk3588/UAPI-MPEG1-FOURCC.md) for MPEG-1, so kernels whose decoders only offer
`V4L2_PIX_FMT_MPEG2_SLICE` fall back to software instead of decoding MPEG-1 as MPEG-2 (the former debian/0002
`--disable-hwaccel=mpeg1_v4l2request` stopgap of the board test is gone).

Trailers: third-party patches unchanged. Arun Iyengar's own patches carry `Assisted-by: LLM` then his
`Signed-off-by` last (FFmpeg has no AI-attribution rule; its checklist asks for a sign-off).
Git source: work/_out/ffmpeg-shared/src, branch `final` on n8.1.2. Re-export per range with
`git format-patch --zero-commit --no-signature --start-number 1 / 101 / 201 / 301`.
