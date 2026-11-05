# Upstream queue (held: send only after the user says go)

Order agreed 2026-11-04: get the non-minimal (server) image building first, push git, then send these.

| # | Fix | Target | Draft | State |
|---|-----|--------|-------|-------|
| 1 | MPEG-4 interlaced field-direct vertical MV scaling (software decoder bug; vm_dec 14496-5 arbitration, harness/research/impl-legacy-decode.md §6.3c) | FFmpeg (ffmpeg-devel ML) | harness/research/legacy-dec/ffmpeg-mpeg4-field-direct-DRAFT.patch (git form: patches/ffmpeg/0301) | draft, needs FATE run + format-patch |
| 2 | MPEG-4 frame-threading: p_field_mv_table not synced (co-located field MVs read as zero) | FFmpeg (bug report or patch) | described in the field-direct draft file | report only, no patch yet |
| 3 | v4l2-request MPEG-4: fall back to software at init for interlaced streams that allow B-VOPs (pairs with the cedrus refusal) | Jernej's FFmpeg v4l2-request fork (not upstream FFmpeg: MPEG-4 request API is not upstream) | harness/research/legacy-dec/ffmpeg-v4l2request-mpeg4-ilace-b-fallback.patch (git form: patches/ffmpeg/0302) | draft; board 2026-11-05: interlaced-B stream falls back to SW at init |
| 4 | Other FFmpeg drafts: GMC1 AMV rshift, MPEG-1 via v4l2-request | check each before sending | harness/research/legacy-dec/ffmpeg-gmc1-amv-rshift-fix.patch (patches/ffmpeg/0303), ffmpeg-mpeg1-v4l2request.patch (now row 7) | review |
| 6 | armbian/configng: desktop YAML for Ubuntu 26.10 stonking (copy of resolute) | armbian/configng PR | docs/prs/configng/0001-desktops-add-Ubuntu-26.10-stonking-as-a-copy-of-reso.patch | draft (our image applies the same change at build time, userpatches/desktop/configng-add-release.py) |
| 7 | FFmpeg v4l2-request MPEG-1 (`mpeg1_v4l2request`; needs the downstream MPEG-1 flags in the MPEG-2 uAPI) | the shared v4l2-request series (Kwiboo/Jernej), not FFmpeg until the kernel uAPI is upstream | patches/ffmpeg/0304 + 0309 (D-pictures only to hwaccels with HWACCEL_CAP_MPEG1_D_PICTURES; supersedes legacy-dec/ffmpeg-mpeg1-v4l2request.patch) | board-tested 2026-11-05 (1080p30 within IDCT envelope). Before the RFC: older MPEG-2 drivers ignore `V4L2_MPEG2_SEQ_FLAG_MPEG1` and would silently decode MPEG-1 as MPEG-2, so make MPEG-1 support discoverable (e.g. a menu/capability control or a distinct OUTPUT fourcc) in the kernel uAPI and probe it in FFmpeg (point raised by orangepi5). HELD |
| 8 | FFmpeg cavs hwaccel plumbing + `cavs_v4l2request` (AVS1/AVS+, downstream cedrus AVSF uAPI) | same; the cavsdec plumbing part could go to FFmpeg once a uAPI exists | patches/ffmpeg/0305-0306 | board bit-exact (impl-desktop-ffmpeg-avs.md) |
| 9 | FFmpeg native hwaccel-only AVS2 decoder + `avs2_v4l2request` (downstream cedrus AVS2 uAPI) | same | patches/ffmpeg/0307-0308 | board bit-exact on 17 8-bit streams (impl-desktop-ffmpeg-avs2.md) |
| 10 | AVS2 stateless uAPI v6 (V4L2_PIX_FMT_AVS2_FRAME + SEQUENCE/PICTURE/WEIGHT_QUANT/ALF controls) as a joint RFC with two backends: cedrus (H616, P010 + AFBC 10-bit capture) and rkvdec VDPU381 (orangepi5, NV15), plus the v4l2-compliance stateless-codec hunk | linux-media (RFC, uAPI in staging-style docs first) + v4l-utils | armbian-build fix/sunxi-avs2-uapi-v6 (e0e401310, patch media-uapi-add-AVS2-stateless-decoder-pixel-format-and-controls.patch; v6 = v5 d0aa5a388 + doc clarifications only: ref_poc optional for hardware that tracks reference POCs, ALF coefficients as coded with drivers deriving the centre tap (9.12.2), WQ matrices raster order with drivers converting, 10-bit not tied to P010, field coding rejected). v4l-utils part: the AVS2_FRAME define + STATELESS_DECODER case already in patches/v4l-utils/0001 (one copy, no separate patch) | both backends bit-exact on v5/v6 (layout unchanged): cedrus 8-bit + 10-bit md5 vs davs2, rkvdec 17/17. Open before sending: no weighting-quantization stream tested on either side; split the v4l-utils AVS2 hunk out of 0001 for the joint send. HELD |
| 5 | Cedrus MPEG-4 VE reset + interlaced qpel / interlaced B-VOP refusals | Armbian PR (cedrus MPEG-4 is not in mainline) | branches fix/sunxi-h616-mpeg4-ve-reset, fix/sunxi-h616-mpeg4-ilace-qpel-refuse | merged into stonking-orangepizero2 |

The FFmpeg rows 3 and 7-9 live in the one shared series patches/ffmpeg (README.md there; Kwiboo PR 20847 base, shared with
the orangepi5 project). Nothing is sent.

Rules: FFmpeg patches need the user's go, real author Arun Iyengar, AI disclosure per the target's policy.
Mesa/panfrost items are NOT in this queue (never upstream without asking).

## Row 10 draft cover text (AVS2 uAPI v6, HELD)

    [RFC PATCH v6] media: uapi: add AVS2 stateless decoder pixel format and controls

    AVS2 (GB/T 33475.2, IEEE 1857.4) stateless decoding uAPI with two
    backends: Allwinner cedrus (H616 VE, 8-bit, 10-bit as P010 or AFBC) and
    Rockchip rkvdec (VDPU381, 10-bit as NV15). Both decode the same streams
    bit-exactly against the reference decoder with the same controls.

    v6 changes documentation only (layout, CIDs and types as in v5):
    - ref_pics[].ref_poc is always filled by applications; hardware that
      tracks reference POCs itself (VDPU381 keeps them with the co-located
      MVs) may ignore it;
    - ALF coefficients are passed as coded; drivers derive the centre tap
      (9.12.2);
    - weighting quantization matrices are in raster order and drivers
      convert them (no WQ stream tested yet by either backend);
    - 10-bit output is not tied to a capture format;
    - field coded sequences are rejected by both drivers for now.

    v4l-utils: v4l2-compliance learns V4L2_PIX_FMT_AVS2_FRAME as a stateless
    format (hunk in patches/v4l-utils/0001).
