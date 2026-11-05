# FFmpeg AVS2: two decode requests in flight (output hold-back)

`0313-avcodec-avs2dec-return-a-picture-only-after-the-next.patch`: the native `avs2` decoder (patches/ffmpeg 0307)
holds the picture being decoded back, when the hwaccel is `HWACCEL_CAP_ASYNC_SAFE` (v4l2request), until the request
for the next picture is queued, so the application never waits on the only request in flight. 2 files, +42/-6 (`libavcodec/avs2dec.[ch]`).

**Where it goes in the shared series (`patches/ffmpeg`, owner: desktop agent):** it is a revision of 0307; either
squash it into 0307 (`avcodec: add a native AVS2 decoder for hardware acceleration`, the commit message of 0307 then
gets the "Holding the output back by one picture..." paragraph) or keep it as its own patch directly after 0308 (it
only touches `avs2dec.[ch]`; 0309-0312 do not touch them, so it applies anywhere after 0307 and was exported as
0313 from a commit on the series head `9dbb2de521`, branch `final` = `opiz2/shared`). Trailers as the README requires:
`Assisted-by: LLM`, then Arun's `Signed-off-by` last.

Source of the export: `kernel-check/ffmpeg-avs2-queue/src` (private clone of `kernel-check/ffmpeg-deb/src` at
`opiz2/shared`, branch `avs2-queue`, 1 commit); board binary built with `harness/ffmpeg/dev-build.sh` into
`kernel-check/ffmpeg-avs2-queue/build`, staged as `kernel-check/vdec-serve/avs2/ffmpeg-avs2q`.

Root cause, A/B method and numbers: `harness/research/impl-desktop-ffmpeg-avs2.md` §4; board round
`harness/research/vdec-perf/board-queue-aq1.sh` (session `session-aq1.sh`, logs `logs/queue-aq1/`).
`-flags low_delay` turns the hold-back off (the old behaviour) in the same binary, which is how the A/B was run.

**Hand-over state (2026-11-05 21:40):** landed as `patches/ffmpeg/0313-...patch` (same export, `[PATCH 313/313]`, 10-char
index abbreviations; the copy here is that final file), README row + SHA256SUMS, ffmpeg deb REV 4. OPi5 note:
`harness/research/ffmpeg-shared/HANDOFF-avs2-queue.md`. Board re-check: runner job `harness/runner-queue/12-avs2-queue.md`.
