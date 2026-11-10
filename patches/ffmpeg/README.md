# FFmpeg v4l2-request patches

Base: Ubuntu `ffmpeg 7:8.1.2-2ubuntu2` (= FFmpeg tag n8.1.2). Applied in file-name order, appended to
debian/patches/series (scripts/build-media-debs.sh). All 52 apply with fuzz 0 on the Ubuntu source.

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
| 0314 | MPEG-4 field quarter-sample MC mirrors the 16x8 block at its edges, not in the middle (ISO/IEC 14496-2 7.6.2.2; software decoder; matches the ISO/IEC 14496-5 reference decoder on the interlaced qpel vectors). Shared with the Orange Pi 5 build |
| 0315-0317 | Shared with the Orange Pi 5 build: 64-bit CAPTURE buffer index mask (cedrus allows 64 CAPTURE buffers); change the frame size of a running session (VIDIOC_REMOVE_BUFS); VP9 keeps the hwaccel across frame size changes of non-key frames (smaller frames decoded in place, larger ones grow the CAPTURE buffers) |
| 0320 | crop the decoder's compose offset (cedrus H.265 AFBC is stored 4 lines down; kernel compose rectangle) |
| 0321 | frames decoded in place (smaller VP9 inter frames) get the line stride the driver reports with VIDIOC_TRY_FMT for their size (cedrus: the stride of a frame of that width); downloads copy the frame's own size |
| 0322 | frames smaller than the device's minimum frame size (VP9 8x8 ... 66x10) are decoded into buffers of the minimum size instead of failing hwaccel init |
| 0323 | frames returned after their decoder session closed (a frame thread re-creating the hwaccel for a VP9 key frame of a new size) no longer dereference the freed session: random crashes on the resize-fp-tiles vectors |
| 0324 | decode scaled down when the CAPTURE pool at the coded size would take more than half of the available memory and the driver lists smaller CAPTURE frame sizes (cedrus H.265 10-bit from 5K up: half size; 6144x3456 Main10 on a 1 GB board) |
| 0325 | MPEG-4 Part 2 / H.263: the slice parameter arrays grow on demand up to one video packet or GOB per macroblock of a 4096x2304 picture (was 2048 per picture; cedrus accepts 36720 = 4080x2304) |
| 0326 | pictures the decoder wrote scaled down (CAPTURE format smaller than the coded size, 0324) get the CAPTURE size instead of the coded size: hwdownload no longer reads past the buffer and DRM PRIME consumers get the right framebuffer size |
| 0327 | H.265 Main/Main 10 pictures larger than any level-5 picture: coded-data (OUTPUT) buffers sized by the stream's level/tier CPB limit (at least level 6, 8,315,536 bytes) instead of an uncompressed 8-bit picture; 94 MB less at 6K, so half-size 6K fits in 1 GB. 4K and smaller unchanged |
| 0329 | MPEG-4 Part 2 software decoder: interlaced B-VOP field direct mode with frame threads read the co-located P-VOP field vectors from the wrong thread (stale or zero); they are now kept with the picture, so output matches `-threads 1` (upstream PR code.ffmpeg.org #25898) |
| 0330 | H.265 High tier streams: coded-data buffers sized by the Main tier CPB like 0327 (High tier at level 6 kept the 31.8 MB default and ran out of memory at 6K) |
| 0331 | MPEG-4 Part 2 / H.263 software decoder: a video packet start no longer overwrites the left macroblock's stored block-3 vector, which B-VOP direct mode reads |
| 0332 | MPEG-4 Part 2 software decoder: 8x8 and 4MV chroma references are clipped to the padded edge (1088 for 1080p), not the picture height |
| debian/0001 | packaging: --enable-v4l2-request --enable-libudev |

uAPIs expected by the add-on hwaccels (local copies in libavcodec/v4l2-stateless-*.h, used only when the kernel
headers lack them): VC-1 600-604 + profile/level 658-659, MPEG-4 700-704, H.263 800-801, AVS2 900-903, AVS 1000-1002,
MPEG-1 flags in the MPEG-2 controls. For MPEG-1, 0304 probes `V4L2_PIX_FMT_MPEG1_SLICE` ('MG1S', 0x5331474d), so
kernels whose decoders only offer `V4L2_PIX_FMT_MPEG2_SLICE` fall back to software.

Trailers: third-party patches unchanged; our own patches carry `Assisted-by: LLM` and a `Signed-off-by`.
