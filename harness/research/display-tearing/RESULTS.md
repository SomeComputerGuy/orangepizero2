# DE33 display tearing: remaining items (late latch, event-before-flush race, job-19 seq_gaps) and the writeback check

State file for the task (2026-11-06). Background, first fix (b04527be4 vblank latch) and job 19 design:
harness/research/impl-display-tearing.md. Kernel scratch (a/ b/ trees, build logs): kernel-check/tearing-late/.

## Root causes
(a) Late latch flush (de33_latch_flushes_late 0-1 per run in the writeback jobs 41/42/55, line_max 339-369 of 806;
    0 in job 19). Exactly one per run, at a mid-frame line, never under steady flipping: by the pattern (and the code)
    not IRQ latency but a stale vblank status bit (to be confirmed by job 58, see "Proof" below). The TCON GINT0 status bits (VBLANK_INT) are set at every vblank whether
    the interrupt is enabled or not, and only sun4i_tcon_handler() clears them. When the vblank IRQ had been off (drm
    vblank off delay 5 s between runs, modeset with the writeback connector), drm_crtc_vblank_get() from the latch commit
    enabled it with the bit already set -> the handler ran at once, at the current (arbitrary) line, counted a vblank,
    sent events and flushed the latch into active video. sun4i_tcon_enable_vblank() never cleared the status bits.
    Proof on the board: job 58 `vblank_stale_cleared_delta` >= 1 on the idle bursts with `latch_flushes_late_delta 0`.
    Residual real IRQ latency (e.g. the serial console: the TEMP note in sun4i_tcon.c measured ~9.5 ms for a printk in
    hard IRQ) is covered by the deferral below and measured by kmsg-rand.
(b) Event before flush: sun4i_crtc_atomic_flush() armed the flip event with drm_crtc_arm_vblank_event(), so
    drm_crtc_handle_vblank() sent it in sun4i_tcon_handler() BEFORE engine->ops->vblank_quirk() wrote the registers.
    A client woken by it (flip_done completes with the same send) could get its next commit's snapshot in before the
    flush; and a flush that was late still reported the flip. Second race in the same area: sun50i_mixer_latch_commit()
    took the mixer and planes snapshots outside latch_lock while the flush writes planes then mixer under it, so an
    unsynced commit (legacy cursor: flip_done completed at once) could interleave and write one commit's planes with the
    next one's blender.
(c) Job 19 seq_gaps (1 in 4 of 6 runs, stock AND fix kernel): always at flip 0->1 (every csv: the only gap is flip 1,
    commit of flip 1 16-25 ms after flip 0's event). afbc-kms-play drew buffer 1 in full (a whole 1024x768 frame through
    the write-combined dumb map) only after flip 0's event, so flip 1 missed its vblank. Test-client artefact, not the
    kernel. Fixed in harness/afbc-kms-play/afbc-kms-play.c (both buffers drawn before the first commit; rebuilt, sha256
    7804b61a...). kms-wb `tear` pre-draws its ring too.

## Fix (kernel)
armbian-build `fix/sunxi-h616-de33-latch-event` 8af646391 (worktree wt-tearing-late, off test-cumulative 2658acbe4,
pushed to fork), patch patches.armbian/drm-sun4i-de33-send-the-flip-event-after-the-latch-flush.patch (after the wb-retry
patch in series.conf):
- sunxi_engine_ops.hold_event / .drain (sunxi_engine.h); sun4i_crtc_atomic_flush() hands the event to the engine after
  drm_crtc_vblank_get(); engines without hold_event (DE2/DE3, A523 RCQ) arm it as before. sun4i_crtc_atomic_disable()
  drains before drm_crtc_vblank_off().
- sun8i_mixer.c (DE33 latch): events of the pending snapshot on mixer->latch_events, sent (drm_crtc_send_vblank_event +
  vblank_put) right after the flush that writes them, with that vblank's count/time; if the snapshot was already flushed
  when the event arrives, sent at once (de33_latch_events_now). Snapshot under latch_lock.
- Deferral: flush at TCON line >= line_deadline (= line_active - ceil(50 us / line time), at most half the window;
  1024x768: 35 -> 33) waits for the next vblank with its events (de33_latch_deferred), at most 2 vblanks, then is written
  anyway (de33_latch_forced, counted late) and later late ones are not deferred until a flush lands in time again (a mode
  whose line counter misbehaves degrades to the old behaviour instead of freezing).
- sun4i_tcon.c: sun4i_tcon_enable_vblank() clears the VBLANK/TRI_FINISH status bits in the enabling write; counter
  /sys/module/sun4i_tcon/parameters/vblank_stale_cleared. Applies to every sun4i TCON (correct everywhere).
- New counters: de33_latch_{line_deadline,deferred,forced,events,events_now}. Nothing disabled, IOMMU untouched.
- Build check: ARMBIAN=wt-tearing-late WORK=work-cumul STAGE=all: 879 patches, 0 failed, 0 C warnings, dtc 0 warnings;
  W=1 drivers/gpu/drm/sun4i clean (kernel-check/tearing-late/build-check.log).
- c43 = test-cumulative c65ef3449 (merge of 8af646391), 2026-11-06 18:36, Image md5 1a65e6a622f769e4f2bd2aa35c3f822f,
  879 patches, 0 C warnings, served in kernel-check/vdec-serve (*.c43). Pushed to fork.

## Job 58 result (c43, 2026-11-06 18:40-18:50) and the follow-up fix
No tearing anywhere: 14 tear runs, mixed/bad/wrong 0, ok == flips, late/forced 0, 60.003 fps unloaded, stale_cleared 2
per run (the stale-bit cause of (a) confirmed: the bit was set at every vblank-IRQ enable and was cleared, late 0).
Open items and causes:
1. Check 6 FAIL (de33_latch_events / _now 0 while flushes == commits): a real kernel bug, not a counter bug. Upstream
   sun4i_crtc_atomic_begin() moves crtc->state->event to scrtc->event (sent by sun4i_tcon_finish_page_flip() in the TCON
   handler, BEFORE the vblank_quirk flush); atomic_flush, where 8af646391 hands the event to hold_event, therefore never
   saw one. The client did request DRM_MODE_PAGE_FLIP_EVENT (nonblocking atomic). So race (b) was still open for every
   client (atomic, legacy page_flip and the helper's internal commit->event all go through atomic_begin). Fix 93b00281a:
   atomic_begin leaves the event in the state for an engine with hold_event (sunxi_engine_holds_events(); only the DE33
   non-RCQ ops have it); DE2/DE3/RCQ unchanged. The tearing pixels were fine in job 58 because the flush follows the early
   event in the same hard IRQ (microseconds), before a woken client can get its next commit in; the window is real but
   narrow (another CPU, a long IRQ path such as a printk), so the counters, not the pixels, prove the fix.
   Client proof added: kms-wb tear `RESULT event_order events_got N unheld U unflushed F`: at every flip event it reads
   de33_latch_events(+_now) and de33_latch_flushes, which the kernel increments under the latch lock before sending; an
   event that arrives before the counters moved by k (k-th event) is unheld/unflushed. Pre-fix kernel: unheld == N.
2. Check 7 NOT TESTED (ve_irqs 89-95 per 10 s run): package bug, two parts. (i) ffmpeg -hwaccel v4l2request without
   -hwaccel_output_format drm_prime downloads every 4K NV12 frame to system RAM, capping the decode at ~9.5 frames/s;
   now drm_prime (fallback to system frames if < 20 IRQs/2 s). (ii) The VE loop of vemem-rand survived ve_stop (ffmpeg
   took > 2 s to exit after SIGTERM, ve.stop was already removed, so the loop restarted: kmsg-rand still had 94 VE IRQs)
   and then spun 3385x on the deleted /dev/shm/in.mkv ("Error opening input file"). ve_stop now kills the loop shell
   first, then ffmpeg, waits until none is left (SIGKILL after 10 s), and the stop flag is cleared only by ve_start.
3. STALL after ROUND-DONE: the same surviving loop held the ssh session's stdout open, so ssh never ended. All background
   loads now run with stdin/stdout/stderr off the session, the chunk end kills leftovers (LEFTOVER-VE counted as
   `load all ve_leftover`).
4. Memory load flip_rate 49-56, seq_gaps 87-110 (no tearing): client CPU/DRAM starvation, not a kernel issue. The kernel
   side is clean in those runs (latch_deferred 0, coalesced 0, late 0, wb 600/600 done, no overflow); the gaps follow
   commits that the client made 18-38 ms after the previous event although asked for 4 ms (mem-d4 commit_phase mean 7.9,
   max 38.8 ms vs 4.07/4.11 unloaded), because its per-frame check (3 MB capture read, mean 8.4 max 32 ms vs 4.4/5.1) and
   draw (2.4/16 vs 1.1/2.3 ms) slow down under the 4-thread 2.37 GB/s memcpy that also takes all 4 cores. A commit that
   misses its vblank simply goes out one later. No work-list item; a stricter variant would run the client SCHED_FIFO
   or the memload at nice 19 (not done).

Fix commit: armbian-build fix/sunxi-h616-de33-latch-event 93b00281a (same patch file, regenerated from
kernel-check/tearing-late/{a,b}; previous diff kept as raw-8af646391.diff), pushed to fork. Build check
(kernel-check/tearing-late/build-check2.log): 879 patches, 0 failed, 0 C warnings, dtc 0. c44 = test-cumulative cf976bccc
(merge of 93b00281a), 2026-11-06 19:00, Image md5 a471ce426a7389b518b5420835b01f95, DTB md5 aa4d5bbb... (unchanged),
served in kernel-check/vdec-serve (*.c44), pushed to fork. Client kms-wb sha256 2730ba1f... (event_order).
Package updated for job 59 (J=t59, FIX=93b00281a, checks 6/7 extended, check 9 = no STALL): runner job
harness/runner-queue/59-tearing-wb2.md, logs harness/research/display-tearing/logs/runner-t59/.

## Job 59 result (c44, 2026-11-06 19:01-19:11) and the writeback fix
Everything PASS (no MIXED/BAD anywhere, events held 100 %, unheld/unflushed 0, late/forced/deferred 0, VE load real at
506-549 IRQs, no STALL) except load/vemem-rand: 2 WRONG "early" (flip 560 captured tag 49 want 48, flip 561 tag 50 want
49), ok 598/600. Root cause: a writeback measurement bug, not the display. vemem-rand de33_wb_busy_frames delta = 2
(0 in every other run) = the unit was still writing out capture 559 at the vblank that flushed commit 560 (DRAM load).
sun50i_wb_vblank() only looks at the queue head when the unit is idle, and its "picture unchanged" check (20e682fc2)
compared against the snapshot seen when the job FIRST reached an idle unit (frame_seq), not the job's own latch_seq: so
job 560 started one vblank late (after commit 561's flush) and recorded 561's picture with a good fence; job 561 the
same one frame later (busy again), job 562 was right because commit 563 came 15 frames later (csv: 563 commit_phase
237 ms). The scan-out was right: every flip has its own flush (commits delta 603 == flushes 603, coalesced 0), its
events in consecutive vblanks (seq 10751, 10752, 10753), held and flushed. The same bug would have shown a coalesced
commit's job as the next commit's picture.
Fix: armbian-build fix/sunxi-h616-de33-latch-event 3e0255e2f, patches.armbian/drm-sun4i-de33-writeback-capture-only-
the-job-s-own-snapshot.patch (after the latch-event patch in series.conf): a job starts only while flushed ==
job->latch_seq; else -EIO + de33_wb_lost, and the loop goes on to the next job in the same IRQ (so the job whose picture
is on screen still starts at once). eligible/frame_seq removed. Scratch: kernel-check/wb-ownsnap/{a,b,tools,hdr.txt}.
Classifier unchanged (WRONG stays a FAIL); HANDOFF check 3 L made exact: fence_errors == wb_failed_delta, <= overflow +
timeout + lost, lost <= busy_frames + deferred + coalesced + overflow + timeout, ok >= 570.
Build check (kernel-check/wb-ownsnap/build-check.log): 880 patches, 0 failed, 0 C warnings, dtc 0. c45 = test-cumulative
7a7ee8e23 (merge of 3e0255e2f), 2026-11-06 19:23, Image md5 751c43fc9fbcc188c93f8a20ee42daeb, served in kernel-check/vdec-serve (*.c45).
Runner job harness/runner-queue/60-tearing-wb3.md (package J=t60, logs logs/runner-t60/).

## Job 60 result (c45, 2026-11-06 19:24-19:34) and the late-capture fix
All checks PASS except 2/3a under VE load: ve-rand 596/600 (2 WRONG), vemem-rand 599/600 (1 WRONG), vemem-rand3 594/600
(3 WRONG). No MIXED/BAD anywhere, base 100 % OK, events held 100 %, late/forced 0. Verdict from the per-flip logs
(files/load/<run>.{txt,csv}): the scan-out was never wrong; the writeback unit captured one frame late.
- Every WRONG flip N holds the picture of N+1, uniform over the frame (ntags 1, no boundary), with a good fence. In 5 of 6
  cases the client's next line is `flip N+1 fence_error status=-5` (= de33_wb_lost: job N+1 found commit N+2 already on
  screen when the unit got free); in vemem-rand flip 426 is OK (commit 427 came a frame later, so job 426 could still
  start on its own snapshot: lost 0). Per run wrong == busy_frames (2/2, 1/1, 3/3) and lost == the fence errors.
- Not mis-attribution: drm_writeback_signal_completion() completes the oldest job, the driver's done list is built in
  queue order (job N 0, then job N+1 -EIO in the same IRQ), and the client's fence/flip map is per flip (each flip's
  out-fence is its own capture fb). Fence order matches; the pixels in fb N really are commit N+1's.
- Not the display: commit N+1 was made 2.4-14.1 ms AFTER flip N's event (e.g. ve-rand flip 18 commit 212.600290, event 17
  212.591367), its event came at the very next vblank (6837 -> 6838, 12651 -> 12652, 10766 -> 10767, ...), flushes ==
  commits, forced/late 0. The frame after vblank N can only show N (a live register write would be MIXED, not uniform
  N+1). So the capture started at vblank N recorded the frame after vblank N+1: the RT-WB began one frame after its
  start. That is also what de33_wb_busy_frames counted (not finished at vblank N+1), and it was job 59's case too: the
  "unit still writing out the previous capture" reading there was wrong, it was the same late begin.
- Hole in 3e0255e2f: it checks the snapshot only when a job starts; the frame the unit records is decided later.
- Tag 255 -> 0 (vemem-rand3 flip 511): 511 & 0xff = 255 expected, 0 = 512 & 0xff captured: the same one-ahead case,
  counted as early by the classifier; no 8-bit wrap bug.
Fix: armbian-build fix/sunxi-h616-de33-latch-event 906968398, patches.armbian/drm-sun4i-de33-writeback-fail-a-capture-
that-ran-into-the-next-snapshot.patch (after the own-snapshot patch): at every vblank at which the running capture is
not finished, a snapshot other than the job's latch_seq on screen marks it replaced; it then ends -EIO (de33_wb_lost +
de33_wb_replaced) instead of 0, no OVERFLOW retry. Same snapshot = same picture, stays good. Instrumentation for the
next run: de33_wb_busy_start_line_min / de33_wb_quick_start_line_max (start line of the first captures busy / finished
at the next vblank): if busy starts sit above all quick ones, the late begin follows IRQ latency (start after some
TCON line; ve-rand reached start line 28 of 35 blanking lines) and a later item could defer such starts. Classifier and
client unchanged and strict (WRONG = FAIL); HANDOFF check 3 L adds (f) replaced <= busy_frames, replaced <= lost.
Build check (kernel-check/wb-replaced/build-check.log, scratch a/b/tools there): 881 patches, 0 failed, 0 C warnings,
dtc 0. c46 = test-cumulative 266499b02 (merge of 906968398), 2026-11-06 19:45, Image md5 7b46b2a92515f23d7c1db63bb6e7a5d1,
DTB md5 aa4d5bbb... (unchanged), served in kernel-check/vdec-serve (*.c46), pushed to fork. Runner job
harness/runner-queue/61-tearing-wb4.md (package J=t61, FIX=906968398, logs logs/runner-t61/).
Image branch: 20e682fc2 (writeback retry) is already in the image branch. The c45/c46 writeback fixes (3e0255e2f,
906968398) only make the writeback fence honest (no capture of another commit's picture reported as good); they belong
with 20e682fc2 and must follow it into the image (together with 8af646391/93b00281a) at the next build if job 61 passes.

## Job 61 result (c46, 2026-11-06 19:47-19:56) and the accounting fix
Display clean everywhere: 0 WRONG/MIXED/BAD/FULL in all 18 tear runs, events held 100 % (unheld/unflushed 0), late/forced
0, no dmesg issue, VE load real (524-555 IRQs). Two check failures, both analysed from files/{base,load}/<run>.{txt,csv}
and the params before/after:
1. Check 3(d) (ve-rand lost 7 > 5, vemem-rand2 6 > 4, vemem-rand3 4 > 2): one late RT-WB begin cost two captures. Every
   fence error but one comes in a pair of consecutive flips N, N+1 with events in consecutive vblanks (ve-rand 523/524
   seq 7624/7625, 576/577, 583/584; vemem-rand2 225/226, 512/513, 559/560; vemem-rand3 265/266, 276/277). Job N was busy
   at vblank N+1 (snapshot N+1 on screen) -> marked replaced, but 906968398 ended it only when the unit finished, at
   vblank N+2; job N+1 could not start while the unit was busy and at N+2 found snapshot N+2 on screen -> lost. Per run
   lost == 2 x replaced (+1 in ve-rand: flip 75, OVERFLOW at the first try, repeat found snapshot 76 already on screen;
   wb_overflow 2 = retries 2, the other repeat succeeded). vemem-rand2 busy 4 vs replaced 3: one busy frame with the
   snapshot unchanged, finished OK. The follower losses were needless: the replaced capture is failed in any case, so
   it can be stopped at the vblank that replaces it and the next job started in the same blanking.
2. Check 5 (base t-rand seq_gaps 1, deferred 0): flip 204 (same random phase in every run, the largest of the sequence):
   commit ioctl at 99.241212, 14.838 ms after flip 203's event 99.226374, i.e. 1.83 ms before vblank 2883; event at 2884.
   deferred 0 and coalesced 0 mean the snapshot was not pending at vblank 2883 (a pending one is flushed or counted
   deferred, its event held): the commit reached atomic_flush after that vblank. Not a lost flip in the latch. The same
   flip made it in jobs 58-60 with 1.82-1.86 ms (phase 14.78-14.81 ms); in job 61 commits with 1.86 ms made it. So the
   commit ioctl -> snapshot latency is sometimes > 1.8 ms on the idle board (nonblocking commit worker + plane updates;
   not measured before). The random phase goes up to frame - 2 ms by design, so such a flip is the test pushing the edge.
Fix: armbian-build fix/sunxi-h616-de33-latch-event 825596b48 (two patches after 906968398, scratch kernel-check/wb-account/
{a,b,tools}):
- drm-sun4i-de33-writeback-stop-a-capture-overtaken-by-the-next-snapshot.patch: a capture busy at a vblank with another
  snapshot on screen is stopped there (-ESTALE, de33_wb_replaced) and the next job starts in the same IRQ. Every failed
  job has exactly one reason, as its fence error and a counter: -EIO de33_wb_fail_error (data lost, not repeatable),
  -ENODATA de33_wb_fail_missed (picture gone before the start: start postponed / coalesced), -ESTALE de33_wb_replaced,
  -ETIMEDOUT de33_wb_fail_timeout, -ECANCELED de33_wb_fail_cancelled; failed == their sum, lost = missed + replaced.
- drm-sun4i-de33-record-the-vblank-and-time-of-each-latch-snapshot.patch: latch_vblanks counted under latch_lock in every
  vblank IRQ; de33_latch_snap_vbl / _flush_vbl / _snap_ns of the last snapshot.
- Client harness/kms-wb (sha256 4970f3b2...): `RESULT flip N fence_error status=S reason R`, `RESULT wb_fail_reasons`,
  per gap `RESULT flip N seq_gap g late_vblanks a deferred_vblanks b commit_margin_ms m snapshot_latency_ms l`,
  `RESULT seq_gap_account ... unexplained U client_late C commit_slow S`, `RESULT snapshot_latency`.
- HANDOFF check 3 L is now exact per reason (client == kernel for each, failed == sum, cause bounds: replaced <= busy,
  error <= overflow + timeout, missed <= deferred + coalesced); check 5 accounts every vblank between flips
  (unexplained 0 everywhere; t-rand late-commit gaps allowed and reported). Package no longer copies ve.stop.
Build check (kernel-check/wb-account/build-check.log): 883 patches, 0 failed, 0 C warnings, dtc 0 (c47 run: 17 old warnings of rebuilt A64/H5 DTBs, Zero2 DTB unchanged); W=1 sun50i_wb.o and
sun8i_mixer.o clean. c47 = test-cumulative 2dc70409e (merge of 825596b48), Image md5 b3938b2633e1bcc7cf9d5262fa66b5d1, DTB unchanged, served
in kernel-check/vdec-serve (*.c47). Runner job harness/runner-queue/62-tearing-wb5.md (J=t62, logs logs/runner-t62/).

## Done criteria / image
- Display fix = done when job 62 (or 61 as it stands) shows checks 2, 4, 6 and the display part of 5 (unexplained 0,
  no deferred-free gap other than a late commit) on all runs. Jobs 59, 60, 61 were already clean on these with
  8af646391 + 93b00281a: no torn/stale/garbled capture in ~24 000 captured flips (3 x ~8000), events held, late/forced 0.
- The display commits can go to the image on their own: the display patch (send-the-flip-event-after-the-latch-flush,
  8af646391 + 93b00281a) touches only sun4i_crtc.c, sun4i_tcon.c, sun8i_mixer.{c,h}, sunxi_engine.h; the writeback
  patches (3e0255e2f, 906968398, the wb half of 825596b48) touch only sun50i_wb.c and apply with or without it. The
  writeback ones make the writeback fence honest (no wrong picture reported as good, every failure with a reason) and
  belong with 20e682fc2 (already in the image); they should follow at the same build if job 62 check 3 passes, otherwise
  ship the display patch alone. The latch-record patch (mixer half of 825596b48) is diagnostics only; it needs the
  display patch and may go with it.

## Writeback tearing check (design, runner job 58)
harness/kms-wb `tear N` (kms-wb.c cmd_tear): ring of 4 source dumbs, frame i pixel = (i & 0xff) << 16 | y (red tags the
commit, green/blue the row), a writeback capture of every flip (ring 6), each capture classified on every 32nd pixel of
every row (+ last), the last 6 on every pixel: OK / WRONG (stale i-1 = captured before its commit was latched, early i+1 =
next commit latched in its place) / MIXED (rows of two commits = torn) / BAD (row disagreeing or misplaced: partial row,
shifted, unwritten). `selftest` proves the classifier tells all of those apart (passes on the host). `-D -1` = random
commit phase. `memload S T MB` = memcpy load.
Scope/limit: the RT-WB starts at the same vblank IRQ right after the flush, so a capture shows the first frame scanned
out with its commit's registers; it proves (1) the flush lands before the active video starts (else the top rows of a
capture carry the previous tag = MIXED; also validates the TCON line-counter assumption), (2) every commit is shown and
none replaces another (WRONG), (3) snapshot/flush atomicity, under VE/DRAM/printk load. A flush written mid-frame (forced)
would tear a frame the unit is not capturing (its start is deferred too), so that case is covered by the counters
(latch_flushes_late / forced == 0), not by pixels. No negative control on the kernel side (a bypass knob would switch off
a default); the classifier selftest is the sensitivity proof.
Package: harness/research/display-tearing/runner-wb/{tearing-wb-job.sh,HANDOFF.md}, job file
harness/runner-queue/58-tearing-wb.md, logs harness/research/display-tearing/logs/runner-t58/.

## Open / next
- Next: runner job 62-tearing-wb5 on c47 (harness/runner-queue/62-tearing-wb5.md, package runner-wb/ J=t62,
  FIX=825596b48); a fresh agent judges done/62-tearing-wb5.summary.md with HANDOFF checks 0-9.
  PASS -> status item 9 "Display tearing" = fixed and verified; cherry-pick 8af646391, 93b00281a, 3e0255e2f, 906968398,
  825596b48 into the image branch after 20e682fc2 at the next build. Check 3 fails only -> image gets the display patch
  alone (see "Done criteria / image").
  Check 3: a pair of failures (replaced N, missed N+1) again -> the stopped unit did not take the new start in the same
  blanking (look at wb_start_line_max / busy_start_line_min). replaced > 0 with wb_busy_start_line_min above
  wb_quick_start_line_max -> late begins follow the start line (a later item could defer starts past some line).
  Check 5: commit_slow gaps in base t-rand with snapshot_latency_max_ms > ~1.8 -> commit path latency (Deferred perf
  note, not a display defect); UNEXPLAINED -> a vblank without a flush of a pending snapshot = real latch bug.
- Job 58 FAIL branches kept for reference: MIXED with boundary_row small (< 40) on most frames -> the flush lands in
  active video (TCON line counter not zeroed at vsync start; sun4i_tcon1_mode_set doubles vtotal) -> fix
  sun50i_mixer_latch_mode_set() line_active/line_deadline. WRONG early -> event/snapshot race still open.
  forced/late > 0 outside kmsg -> real IRQ latency > 2 frames: look at what holds IRQs off (printk.txt, dmesg).
- Not done: RCQ port (vendor RTMX_USE_RCQ; would latch in hardware); not needed for frame coherence.
