# For the OPi5 session: FFmpeg 0313, AVS2 decoder output hold-back (two decode requests in flight)

From the orangepizero2 (H616, cedrus) project, 2026-11-05. Nothing here goes upstream; it is for the shared
`ffmpeg-shared` series (`work/_out/ffmpeg-shared/patches`, branch `final`).

## What
`0313-avcodec-avs2dec-return-a-picture-only-after-the-next.patch` (orangepizero2 `patches/ffmpeg/`, 2 files, +42/-6,
`libavcodec/avs2dec.[ch]` only). The native `avs2` decoder (0307) has no frame threading and bumped a picture out of
its DPB as soon as it was decoded, so with an `HWACCEL_CAP_ASYNC_SAFE` hwaccel (v4l2request queues in end_frame() and
waits when the frame is returned) the application waited on the only request in flight for every low-delay picture and
for half the pictures of a random-access GOP: the VE idled while the next picture was read, parsed and queued.
0313 holds the picture being decoded back until the next picture has been queued (asynchronous hwaccel and
`AV_CODEC_FLAG_LOW_DELAY` not set); draining lifts the hold; `has_b_frames` gains the one extra picture of delay.
Output order and pictures are unchanged. `-flags low_delay` restores the old behaviour in the same binary.

## Board result (H616, cumulative kernel c9, VE 624 MHz; vdec-perf round aq1, logs/queue-aq1/round.txt)
- cctv4k Main10 (3840x2160, 292 pictures): starved VE gaps (next request not queued at IRQ time) 151-152 per run
  without the hold-back (unpatched binary and `-flags low_delay`) -> 1 per run with it; wall 5.62-5.72 s against
  5.73-6.23 s; pipeline fps 60.1-60.2 against 57.4-58.5.
- ParkScene 1080p RA (200 pictures): starved gaps 103 -> 0.
- md5 PASS (unchanged references): AVS2 8-bit main-2160p-ra, cctv4k Main10 P010, and the 17 8-bit conformance streams
  decode with rc=0. The whole set is re-checked as runner job 12-avs2-queue (17 8-bit md5s + Main10 + gap count).
- rkvdec/RK3588 is the same case (v4l2request, ASYNC_SAFE), so the same gain is expected there; the patch has no
  driver- or uAPI-specific code.

## How to adopt
1. Copy the patch file byte-for-byte into `work/_out/ffmpeg-shared/patches/` (sha256
   `251cdec797b0d461449726d9024abf2bb08c451e19e41d2ace92c487737b9d9c`). It applies with fuzz 0 on the series head
   (`final` = 9dbb2de521, 0312) and anywhere after 0307: 0308-0312 do not touch `avs2dec.[ch]`. It was exported with
   `git format-patch --zero-commit --no-signature --numbered --start-number 313 -1` (`core.abbrev=10`) from the commit
   on `kernel-check/ffmpeg-avs2-queue/src` branch `avs2-queue` (07e8811ff5, parent 9dbb2de521). Alternative: squash it
   into 0307 (then the "Holding the picture back ..." paragraph of the 0313 message belongs in 0307's); we kept it
   separate so that the board A/B stays reproducible.
2. README.md: our row, after 0312:
   `| 0313 | orangepizero2: AVS2 decoder output hold-back for asynchronous hwaccels (two decode requests in flight on v4l2request; `-flags low_delay` turns it off; aq1: starved VE gaps 151 -> 1 per 4K Main10 run, md5 unchanged) |`
   and "All 35 apply" -> "All 36 apply".
3. SHA256SUMS: add the 0313 line and refresh the README.md line. Note: your current SHA256SUMS lists README.md as
   89f978e586..., but the README.md in the same directory hashes to 0dbc642437... (the orangepizero2 copy, 8298d00,
   already carries the corrected line); after the 0313 row ours is a73c080b61....
4. Trailers are already as the README requires: `Assisted-by: LLM`, then Arun's `Signed-off-by` last.
5. Bump your ffmpeg deb revision and rebuild; a before/after check on rkvdec is the `ve-timeline`-style starved-gap
   count or simply the wall time of a 4K AVS2 decode (`-f null -`) with and without `-flags low_delay`.

Once adopted, the two sets are byte-identical again (orangepizero2 `patches/ffmpeg` = yours + 0313, README row, SHA256SUMS).
