# DE33 writeback -EIO under a 4K H.265 decode (state file, task wb-eio)

## Symptom (jobs 53 c38, 54 c39; harness/research/afbc-wb/logs/runner-j5{3,4}/files/real-hevc8/)
- Case real-hevc8 (hevc-main-2160p60.mkv, linear NV12 pass, 1024x768 window at 1408,704 of the 3840x2160 surface,
  1:1 on the VI plane, XR30 writeback): `RESULT frame N wb_error -5 0` on frames 2,6,8 (j53) and 2,6 (j54).
  wb_failed_delta 3/2, wb_busy_frames 0, status_last 0x10, dmesg clean.
- Always r1 = -5, r2 = 0: only the FIRST of the two captures per frame fails, the second (same picture) succeeds.
- Deterministic in content: the same frames in both runs (frame 8 only in j53); every successful capture has the same
  md5 in j53 and j54 (frames 0,1,3,4,5,7 identical), so the captures that complete are correct.
- Never: AFBC pass of the same stream, real-hevc10 linear (P010), VP9 4K, all 1024x768 synthetic streams.

## Root cause
- -5 = the driver's -EIO = the RT-WB status had OVERFLOW (bit 5) or TIMEOUT (bit 6) and no FINISH at the vblank after
  the start (sun50i_wb_vblank). Not a frame-done timeout (that is -ETIMEDOUT after 4 busy vblanks; busy_frames 0) and
  not a test-client artefact (the client only waits on the fence; the fence status comes from the kernel).
- Why only the first capture: FFmpeg's v4l2request hwaccel queues decode requests asynchronously
  (v4l2_request_queue_decode -> MEDIA_REQUEST_IOC_QUEUE, no wait); with the H.265 reorder delay the VE is still
  decoding the following 4K pictures (linear NV12 output = ~12 MB written per picture + references) while the client
  takes its first capture right after the blocking plane commit. The second capture ~33 ms later finds the VE idle.
  The frames that fail are the ones whose capture overlaps a heavy decode, hence content-determined, and marginal
  (frame 8 failed once in two runs). So: the RT-WB loses its output to DRAM contention (the unit shares MBUS with the
  scan-out, VE, CPU). AFBC output (compressed, less traffic) and the small synthetic streams never reach that load.
- Ruled out / not the cause: plane fetch (the shown picture is fine; successful captures bit-identical between runs);
  late vblank latch: no mechanism ties ~7 ms IRQ latency to fixed frames, cedrus has no long hard-IRQ work for H.265
  (post_process only JPEG/encoder) - but a start in active video is now also guarded (below) and counted.
- Hardware has no setting for this in our reach: vendor de_wb has no retry either (de_wb_get_status 0x71 -> done =
  false), bwc register is de331-only, MBUS QoS is set by U-Boot (dram_sun50i_h616.c mctl_set_master_priority, vendor boot0 values; master-to-unit map not verified).
- Not proven on the board which of OVERFLOW/TIMEOUT it is: the new counters (de33_wb_overflow/_timeout/_status_fail)
  record it in job 55.

## Fix (kernel)
- armbian-build fix/sunxi-h616-de33-wb-retry 20e682fc2 (worktree wt-wb-eio, off test-cumulative d67f25b42, fork only):
  patches.armbian/drm-sun4i-de33-writeback-repeat-a-capture-that-lost-data-to-memory.patch (end of series.conf).
  - OVERFLOW/TIMEOUT: the job goes back to the head of the queue and is captured again on the next frame, up to 4
    captures, as long as mixer->latch_flushed_seq is still the snapshot the job first could start on (same picture on
    screen); otherwise -EIO (de33_wb_lost).
  - A start with the TCON line >= line_active (vblank IRQ serviced in active video, as de33_latch_flushes_late) is
    postponed a frame, at most 4 times, instead of starting the unit mid-frame.
  - Counters de33_wb_{overflow,timeout,status_fail,retries,deferred,lost,start_line_max}.
  - sun50i_wb_vblank() gets cur_line from sun50i_mixer_vblank_quirk().
- Build check: ARMBIAN=wt-wb-eio WORK=kernel-check/work-cumul STAGE=all: 876 patches, 0 failed, 0 C warnings, dtbs 0
  warnings; W=1 sun50i_wb.o + sun8i_mixer.o clean (kernel-check/run-wb-eio-build.log).
- Merged into test-cumulative 6d124e150 = c40, built 2026-11-06 17:23, Image md5 d950e7ed64c3620b1983fc5217a99a7c, 876 patches,
  0 C warnings (dtc warnings 17 = pre-existing A64/H5 board DTS, none H616), served in kernel-check/vdec-serve (*.c40).
  test-cumulative and the fix branch pushed to fork.

## Runner job 55
harness/runner-queue/55-wb-eio.md -> harness/research/wb-eio/runner/wb-eio-job.sh (wrapper of afbc-wb-job.sh j55;
afbc-wb-job.sh got the j55 case set, FIX3 check, and the new counter deltas in results.txt; j53/j54 unchanged except
params also list de33_latch_flushes_late). Cases: syn-hevc8/-hevc10/-vp9p0/-hevc8-xr24, real-hevc8-r1..r5, real-hevc10.
Logs: harness/research/afbc-wb/logs/runner-j55/. Checks/verdict: harness/research/wb-eio/runner/HANDOFF.md.

## Related, not taken on (display-tearing work list)
- Late latch flush (~7 ms IRQ latency, line_max 339-369 seen in jobs 41/42, one per run) and the TCON
  flip-event-before-flush race: not the cause here (see above). Still open on the tearing list.

## State / next (fresh agent, after done/55-wb-eio.summary.md)
- PASS: real-hevc8 0 wb_error x5. Report which bit fired (wb_overflow/timeout_delta, wb_status_fail) and wb_retries;
  update afbc-wb RESULTS "Separate item", memory project-afbc-wb.md / project-de33-writeback.md; image branch merge
  of 20e682fc2 with the other writeback commits.
- FAIL with wb_lost_delta > 0: the picture changed before a retry: look at the client order (should not happen in
  afbc-wb). FAIL with retries exhausted (wb_retries_delta >= 4 per failed job): contention lasts > 4 frames -> look
  at a DE/VE MBUS priority or a bigger retry budget.
- deferred_delta > 0 or start_line_max >= 35: late vblank IRQs did happen; tie to the tearing item.
