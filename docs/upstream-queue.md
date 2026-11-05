# Upstream queue (held: send only after the user says go)

Order agreed 2026-11-04: get the non-minimal (server) image building first, push git, then send these.

| # | Fix | Target | Draft | State |
|---|-----|--------|-------|-------|
| 1 | MPEG-4 interlaced field-direct vertical MV scaling (software decoder bug; vm_dec 14496-5 arbitration, harness/research/impl-legacy-decode.md §6.3c) | FFmpeg (ffmpeg-devel ML) | harness/research/legacy-dec/ffmpeg-mpeg4-field-direct-DRAFT.patch (git form: patches/ffmpeg/0301) | draft, needs FATE run + format-patch |
| 2 | MPEG-4 frame-threading: p_field_mv_table not synced (co-located field MVs read as zero) | FFmpeg (bug report or patch) | described in the field-direct draft file | report only, no patch yet |
| 3 | v4l2-request MPEG-4: fall back to software at init for interlaced streams that allow B-VOPs (pairs with the cedrus refusal) | Jernej's FFmpeg v4l2-request fork (not upstream FFmpeg: MPEG-4 request API is not upstream) | harness/research/legacy-dec/ffmpeg-v4l2request-mpeg4-ilace-b-fallback.patch (git form: patches/ffmpeg/0302) | draft; board 2026-11-05: interlaced-B stream falls back to SW at init |
| 4 | Other FFmpeg drafts: GMC1 AMV rshift, MPEG-1 via v4l2-request | check each before sending | harness/research/legacy-dec/ffmpeg-gmc1-amv-rshift-fix.patch (patches/ffmpeg/0303), ffmpeg-mpeg1-v4l2request.patch (now row 7) | review |
| 6 | armbian/configng: desktop YAML for Ubuntu 26.10 stonking (copy of resolute) | armbian/configng PR | docs/prs/configng/0001-desktops-add-Ubuntu-26.10-stonking-as-a-copy-of-reso.patch | draft (our image applies the same change at build time, userpatches/desktop/configng-add-release.py) |
| 7 | FFmpeg v4l2-request MPEG-1 (`mpeg1_v4l2request`; needs the downstream MPEG-1 flags in the MPEG-2 uAPI) | the shared v4l2-request series (Kwiboo/Jernej), not FFmpeg until the kernel uAPI is upstream | patches/ffmpeg/0304 (supersedes legacy-dec/ffmpeg-mpeg1-v4l2request.patch) | board-tested 2026-11-05 (1080p30 within IDCT envelope) |
| 8 | FFmpeg cavs hwaccel plumbing + `cavs_v4l2request` (AVS1/AVS+, downstream cedrus AVSF uAPI) | same; the cavsdec plumbing part could go to FFmpeg once a uAPI exists | patches/ffmpeg/0305-0306 | board bit-exact (impl-desktop-ffmpeg-avs.md) |
| 9 | FFmpeg native hwaccel-only AVS2 decoder + `avs2_v4l2request` (downstream cedrus AVS2 uAPI) | same | patches/ffmpeg/0307-0308 | board bit-exact on 17 8-bit streams (impl-desktop-ffmpeg-avs2.md) |
| 5 | Cedrus MPEG-4 VE reset + interlaced qpel / interlaced B-VOP refusals | Armbian PR (cedrus MPEG-4 is not in mainline) | branches fix/sunxi-h616-mpeg4-ve-reset, fix/sunxi-h616-mpeg4-ilace-qpel-refuse | merged into stonking-orangepizero2 |

The FFmpeg rows 3 and 7-9 live in the one shared series patches/ffmpeg (README.md there; Kwiboo PR 20847 base, shared with
the orangepi5 project). Nothing is sent.

Rules: FFmpeg patches need the user's go, real author Arun Iyengar, AI disclosure per the target's policy.
Mesa/panfrost items are NOT in this queue (never upstream without asking).
