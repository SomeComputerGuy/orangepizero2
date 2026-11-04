# Upstream queue (held: send only after the user says go)

Order agreed 2026-11-04: get the non-minimal (server) image building first, push git, then send these.

| # | Fix | Target | Draft | State |
|---|-----|--------|-------|-------|
| 1 | MPEG-4 interlaced field-direct vertical MV scaling (software decoder bug; vm_dec 14496-5 arbitration, harness/research/impl-legacy-decode.md §6.3c) | FFmpeg (ffmpeg-devel ML) | harness/research/legacy-dec/ffmpeg-mpeg4-field-direct-DRAFT.patch | draft, needs FATE run + format-patch |
| 2 | MPEG-4 frame-threading: p_field_mv_table not synced (co-located field MVs read as zero) | FFmpeg (bug report or patch) | described in the field-direct draft file | report only, no patch yet |
| 3 | v4l2-request MPEG-4: fall back to software at init for interlaced streams that allow B-VOPs (pairs with the cedrus refusal) | Jernej's FFmpeg v4l2-request fork (not upstream FFmpeg: MPEG-4 request API is not upstream) | harness/research/legacy-dec/ffmpeg-v4l2request-mpeg4-ilace-b-fallback.patch | draft |
| 4 | Other FFmpeg drafts: GMC1 AMV rshift, MPEG-1 via v4l2-request | check each before sending | harness/research/legacy-dec/ffmpeg-gmc1-amv-rshift-fix.patch, ffmpeg-mpeg1-v4l2request.patch | review |
| 5 | Cedrus MPEG-4 VE reset + interlaced qpel / interlaced B-VOP refusals | Armbian PR (cedrus MPEG-4 is not in mainline) | branches fix/sunxi-h616-mpeg4-ve-reset, fix/sunxi-h616-mpeg4-ilace-qpel-refuse | merged into stonking-orangepizero2 |

Rules: FFmpeg patches need the user's go, real author Arun Iyengar, AI disclosure per the target's policy.
Mesa/panfrost items are NOT in this queue (never upstream without asking).
