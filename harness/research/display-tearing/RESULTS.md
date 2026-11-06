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
- Next: runner job 60-tearing-wb3 on c45 (harness/runner-queue/60-tearing-wb3.md, package runner-wb/ with J=t60,
  FIX=3e0255e2f, vemem-rand x3); a fresh agent judges done/60-tearing-wb3.summary.md with HANDOFF checks 0-9.
  PASS -> status item 9 "Display tearing" = fixed and verified by writeback; cherry-pick b04527be4's follow-ups
  (8af646391, 93b00281a, 3e0255e2f) into stonking-orangepizero2 with the other writeback commits after the user's build.
  WRONG again with wb_busy_frames/lost 0 -> a real early latch (look at the flush/held-event path); MIXED -> job-58 notes.
- Job 58 FAIL branches kept for reference: MIXED with boundary_row small (< 40) on most frames -> the flush lands in
  active video (TCON line counter not zeroed at vsync start; sun4i_tcon1_mode_set doubles vtotal) -> fix
  sun50i_mixer_latch_mode_set() line_active/line_deadline. WRONG early -> event/snapshot race still open.
  forced/late > 0 outside kmsg -> real IRQ latency > 2 frames: look at what holds IRQs off (printk.txt, dmesg).
- Not done: RCQ port (vendor RTMX_USE_RCQ; would latch in hardware); not needed for frame coherence.
