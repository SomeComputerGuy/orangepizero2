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
- Next: runner job 58 on c43; a fresh agent judges done/58-tearing-wb.summary.md with HANDOFF checks 0-8.
  PASS -> status item 9 "Display tearing" = fixed and verified by writeback; cherry-pick b04527be4's follow-ups
  (8af646391) into stonking-orangepizero2 with the other writeback commits after the user's build.
  FAIL check 2 MIXED with boundary_row small (< 40) on most frames -> the flush lands in active video: the TCON line
  counter is not zeroed at vsync start (sun4i_tcon1_mode_set doubles vtotal; see the note in sun4i_tcon.c) -> fix
  sun50i_mixer_latch_mode_set() line_active/line_deadline. WRONG early -> event/snapshot race still open.
  check 4 forced/late > 0 outside kmsg -> real IRQ latency > 2 frames: look at what holds IRQs off (printk.txt, dmesg).
- Not done: RCQ port (vendor RTMX_USE_RCQ; would latch in hardware); not needed for frame coherence.
