# DE33 writeback connector (datasheet W23 "write-back"): implementation, host checks, board package

Agent task 2026-11-06. State for a fresh agent: section "RESULTS" at the end. Raw material: harness/research/de33-writeback/
(LibreELEC reference patches under dl/, runner package under runner/), kernel-check/de33-writeback/ (patch scratch tree a/ b/,
de33-writeback.diff, build-check.sh/.log), harness/kms-wb/ (test client).

## 1. What the hardware offers (sources)

- H616 User Manual V1.0 p. 296: DE feature "Supports write back only for high efficient dual display and miracast"; block
  diagram RT-Mixer / Write-Back / TCON behind one MBUS port; table 3-8: IOMMU master 0 = DE (1 DI, 2 VE_R, 3 VE, 6 G2D). No
  register description.
- Vendor BSP (orange-pi-5.4-sun50iw9 disp2, harness/research/display-tearing/dl/vendor-disp2-5.4-sun50iw9/):
  de_wb_type.h (register layout, formats), de_wb.c (programming: size/crop, addresses, format, coarse+fine scaler with the
  two 16-phase Lanczos2 tables, CSC d0-d2/c0-c2, start bit written last; stop = GCTRL 0x20000010), de_top.c (RT-WB block
  at DE+0x10000 with the core at +0x1000 and a CDC at +0x8000; routing register DE+0x8020: bits[2:0] source
  (0 blender0, 1 DSC0, 2 blender1, ...), bit4 start, bit5 self-timing; clock/reset bits 4 of 0x8004/0x8000 = CLK_WB/RST_WB
  of the DE33 CCU), de_disp_capture.c (one capture per start, status read at the next vsync: FINISH bit4, OVERFLOW bit5,
  TIMEOUT bit6, BUSY bit8, W1C 0x71).
- LibreELEC (dl/, fetched 2026-11-06): 0235 DE3 writeback connector (H6), 0238 DE33/H616 support via the RCQ (blender
  mux value = port * 2, CSC coefficients, scaler programming with chroma subsampling, SFTM 0x20, routing register 0x20 added
  to the de2 CCU syscon), 0240 "Share the DE33 DMA address space" (all DE33 memory clients share one IOMMU master; the
  sun50i IOMMU attaches one domain at a time, so the write-back must allocate through the planes device).

## 2. Design (armbian-build branch fix/sunxi-h616-de33-writeback, worktree wt-de33-writeback, fork only)

Patch patches.armbian/drm-sun4i-de33-add-a-writeback-connector-for-the-RT-WB-unit.patch (last in series.conf), commits
1b4c0f53b (feature) + 6dbed6c18 (review follow-up, see below). Files: new sun50i_wb.{c,h}, sun8i_mixer.{c,h} (wb pointer,
vblank hook), sun8i_csc.{c,h} (DE33 CSC table accessor), sun4i_drv.c (component), Makefile, ccu-sun8i-de2.c (syscon range
0x20..0x2c), sun50i-h616.dtsi (writeback@10000 node), new binding allwinner,sun50i-h616-de33-writeback.yaml.

- DT: `writeback@10000 { compatible = "allwinner,sun50i-h616-de33-writeback"; reg = <0x10000 0x10000>; clocks =
  <&display_clocks CLK_WB>; clock-names = "mod"; resets = <&display_clocks RST_WB>; allwinner,top = <&display_clocks>; }`.
  No `iommus`: the unit uses the DE's IOMMU master 0 together with the planes; a second IOMMU device would get its own
  default domain and the single-domain sun50i IOMMU would detach the planes' domain. Buffers are DRM dumb/GEM buffers
  allocated through the DRM DMA device (= planes device), the addresses programmed are their IOVAs. Nothing bypassed.
- Binding to DRM: sun4i_drv_probe adds the node as a component after the of_graph pipelines, so sun50i_wb_bind runs when
  all CRTCs exist; it creates one drm_writeback_connector with possible_crtcs = the CRTCs whose engine is a DE33 mixer
  without RCQ (compatible check + cfg), marks the encoders as mutual clones, and sets mixer->wb for those mixers.
  A failure to create the connector only warns (display output unaffected).
- Jobs: connector helper atomic_commit (called by drm_atomic_helper_commit_writebacks after the planes are programmed and,
  on the DE33, latched) builds a precomputed register image (size, addresses, pitches, format, coarse/fine scaler, CSC) and
  queues it; it takes a drm_crtc_vblank_get() so the TCON interrupt keeps running. sun50i_mixer_vblank_quirk() calls
  sun50i_wb_vblank() right after the latch flush: a running job's status is read (FINISH -> done; OVERFLOW/TIMEOUT -> -EIO;
  still busy after 4 vblanks -> -ETIMEDOUT), the unit is stopped and reset (GCTRL 0x20000010, routing START cleared), the
  fence is signalled (drm_writeback_signal_completion), and the next pending job of this mixer is programmed and started
  in the same blanking (routing mux = blender(engine.id), GCTRL AUTO_GATE|START, routing START). So a capture records the
  first frame scanned out with the committed registers; completion is one vblank later. The encoder's atomic_disable (CRTC
  off or modeset) cancels all jobs with -ECANCELED in queue order.
- Formats: XRGB/ARGB8888 and the other 32-bit RGB orders (hw 4-7), RGB888/BGR888 (0/1), XRGB2101010 (out_bit, no
  scale/CSC, untested), NV12 (0xc), NV21 (0xd), YUV420 (8). fb may be smaller than the mode (coarse >2:1 then Lanczos2 fine
  scaler, vendor coefficients), width <= 2048 (output line buffer). CSC: RGB -> BT.601 limited YCbCr (rgb2yuv_de3 of
  sun8i_csc.c, d0-d2 = 0, same register layout as the DE33 layer CSC) when the blender is RGB and the output YUV; the
  inverse (yuv2rgb_de3 limited/601) on the TV encoder path (mixer->output_yuv) for RGB output.
- Counters (read-only module params): /sys/module/sun8i_mixer/parameters/de33_wb_{jobs,done,failed,busy_frames,status_last}.
- Review follow-up 6dbed6c18: sun4i commits planes with DRM_PLANE_COMMIT_ACTIVE_ONLY (commit_tail_rpm), so a cancel hook
  in the mixer commit could never see an inactive CRTC; the cancel moved to the encoder atomic_disable. Reset settle
  (readback + 1 us) before programming; fine-scaler registers written for every format; non-fatal connector init.
- Not done: the DE interrupt (GIC SPI 88, one line for the whole DE) for immediate completion instead of the per-frame poll;
  10-bit output verification; the H616 RCQ path (unchanged decision).

## 3. Host checks (kernel-check/de33-writeback/build-check.log)

ARMBIAN=wt-de33-writeback WORK=kernel-check/work-tearing STAGE=dtbs build-kernel.sh: 844 patches applied, 0 failed, dtbs
exit 0 with 0 dtc warnings, DT_CHECK writeback@10000 + compatible present in the decompiled Zero2 DTB (clocks <0x0f 8> =
CLK_WB, resets <0x0f 2> = RST_WB); `make W=1 drivers/gpu/drm/sun4i/ drivers/clk/sunxi-ng/ccu-sun8i-de2.o`: exit 0, no
warnings. sparse/smatch are not installed on this host.

## 4. Test client harness/kms-wb/ (libdrm only, build.sh against the ffmpeg-afbc sysroot, out/kms-wb)

`kms-wb [-c HDMI-A-1] [-m WxH@R] [-w XR24|NV12|XR30] [-t tol] [-r n] [-D us] [-o dumpdir] probe | solid RRGGBB | bars |
flips N`. probe: lists connectors, the writeback formats blob and whether the writeback encoder reaches the display CRTC.
solid/bars: XR24 dumb buffer shown via a modeset commit, then `-r` blocking commits each with a writeback job
(WRITEBACK_FB_ID, CRTC_ID, WRITEBACK_OUT_FENCE_PTR), fence waited (poll + SYNC_IOC_FILE_INFO status), pixel compare (RGB
bytes exact for XR24; NV12 against BT.601 limited with a tolerance; XR30 top 8 bits with a tolerance). flips: N page flips
between two solid colours with a writeback job each (ring of 4 capture buffers, the previous capture's fence waited after
the next flip event), rows classified as colour A / colour B / other; a frame with both A and B rows is TORN, one with other
rows BAD. `-D` sleeps after the flip event before the next commit (as job 19) to place the commit in the active video.
Every value is a `RESULT key value` line; exit 0 pass, 1 fail, 2 setup, 3 mode unavailable (NOT TESTED).

## 5. Runner job 21 (harness/runner-queue/21-de33-writeback.md, package harness/research/de33-writeback/runner/)

wb-job.sh wb: one chunk on the newest cumulative kernel (must contain 6dbed6c18; else BLOCKED), HDMI-A-1 forced on at
1024x768@60: probe; solid 3c7ab4/c81e5a/000000/ffffff and bars (3 XR24 captures each, exact); nv12 (tol 3); xr30 (tol 4,
informational); flips 300 with d0/d4/d12. Checks 0-8 in HANDOFF.md: connector present and reaching the CRTC, 0 mismatches,
frames_torn == frames_bad == fence_errors == 0, wb_jobs_delta == wb_done_delta, no IOMMU fault/OOPS in dmesg.

## RESULTS (state for a fresh agent)

- Branch fix/sunxi-h616-de33-writeback (fork): 1b4c0f53b + 6dbed6c18, host-build-checked (W=1, dtbs clean), NOT merged,
  NOT board-tested. Default behaviour unchanged (connector is additional, unit in reset until a job is queued).
- Board check queued: harness/runner-queue/21-de33-writeback.md (needs the branch in the next cumulative kernel, c23+).
- Next: coordinator merges 6dbed6c18 into test-cumulative, builds/serves; runner runs job 21; a fresh agent judges
  done/21-de33-writeback.summary.md with HANDOFF.md checks 0-8. Green = picture-level proof of the latch (job 19) and a
  working W23 write-back row; then docs/datasheet-checklist.md row "Write-back" -> implemented (writeback connector).
- If check 3 fails with a uniform offset/garbage: suspect the routing mux value (blender 0 vs vendor's DSC0 = 1) or the
  capture window (SIZE/CROP); if NV12 alone fails: CSC/chroma path (vendor de_csc_table.c not fetched). If every fence
  times out: the FINISH status is not set at the next vblank; read de33_wb_status_last. An IOMMU fault line = the unit's
  writes did not go through master 0 as assumed; stop and report.

### Job 21 (2026-11-06, c24): BLOCKED, root cause = DTB never installed (harness bug, not the driver)
- Summary harness/runner-queue/done/21-de33-writeback.summary.md: "no Writeback-1 connector / de33_wb_* parameters" although
  c24 contains 6dbed6c18. files/ was empty (nothing collected when blocked).
- Evidence: the writeback is a DT node (writeback@10000 in sun50i-h616.dtsi + the de33 clock syscon range), and
  harness/research/vdec-perf/install-kernel.sh installed only Image + modules; harness/serial.log shows every trial boot
  loading the image's stock DTB (`Load fdt: /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb`, 53821 bytes; c24's is 54221).
  Without the node sun50i_wb has nothing to bind and the mixer keeps the display up without a connector (6dbed6c18 behaviour).
  The de33_wb_* parameters (built-in sun8i-mixer) were probably present; the check tested both in one `&&` so it cannot say.
- Fix (project repo, shared with jobs 26/20): install-kernel.sh installs the tag's DTB (symlink, .stock kept), new
  restore-kernel.sh, fallback script re-points the DTB on non-trial boots; wb-job.sh verifies the DTB md5, checks the
  parameters and the connector separately and collects files/blocked-<tag>/ (dmesg, DT nodes, devices_deferred, DRM classes).
- Re-queued as harness/runner-queue/30-de33-writeback.md (kernel 6dbed6c18 unchanged; c26 has it). Next: fresh agent judges
  job 30 with HANDOFF checks 0-8.

### Job 30 (2026-11-06, c27): FAIL, two -EINVALs, analysed; fixes in c35, re-queued as job 40
- Summary harness/runner-queue/done/30-de33-writeback.summary.md, logs logs/runner-wb/files/wb/. Connector present and
  reaching the CRTC (checks 1, 2 PASS); every flip+writeback commit -EINVAL; xr30 "dumb buffer: Invalid argument"; no job
  ever reached the driver (wb_jobs_delta 0).
- -EINVAL 1 (flip + writeback), TEST BUG: kms-wb set the writeback connector's CRTC_ID first in the writeback commit, without
  DRM_MODE_ATOMIC_ALLOW_MODESET. Attaching a connector to a CRTC sets connectors_changed (update_connector_routing,
  drm_atomic_helper.c), i.e. a full modeset, and drm_atomic_check_only refuses it ("requires full modeset"). Fix:
  harness/kms-wb/kms-wb.c attaches the writeback connector in its initial modeset commit; writeback commits then change
  only WRITEBACK_FB_ID/fence. Commit failures are now reported as `RESULT capture N commit_error <errno>` /
  `flip N commit_error` / `modeset_commit_error` / `capture_buffer_error` (job 30 printed them as fence_error -1).
- -EINVAL 2 (xr30 capture buffer), KERNEL BUG: the dumb buffer itself was fine (bpp 32); ADDFB2 failed in
  drm_gem_fb_init_with_funcs(): drm_any_plane_has_format() - no sun4i plane has XRGB2101010 (DE3 VI layers only have
  the ARGB2101010 orders), so the writeback-only format was unusable. The hardware does write it (vendor de_wb.c
  DISP_FORMAT_A2R10G10B10 "equal x2p10p10p10"). Fix 300d79df7 (patches.armbian/drm-sun4i-accept-framebuffers-in-
  writeback-only-formats.patch): sun4i_fb_create creates linear fbs in a format only a writeback connector offers without
  that check; planes still reject them in the atomic check.
- Found on the way, KERNEL BUG: drm_atomic_helper_commit_tail_rpm() calls the writeback atomic_commit from
  commit_modeset_enables(), BEFORE commit_planes (the driver comment said after). A vblank between the two started the
  capture on the previous frame (not caught by the solid/flips checks: it gives a pure frame of the other colour). Fix
  30706dcc8 (drm-sun4i-de33-writeback-start-a-capture-after-its-commit-is-latched.patch): jobs queued unarmed;
  sun50i_mixer_latch_commit() arms them with mixer->latch_seq under the latch lock (sun50i_wb_arm()); the vblank starts an
  armed job only when latch_flushed_seq >= its seq. Lock order latch_lock -> wb->lock (the IRQ never nests them).
- Package fixes: results.txt flips labels were shifted by one pair (awk loop started at $3); now `flips_requested` + pairs
  from $4. wb-job.sh job name wb40 (logs/runner-wb40, job 30's kept), FIX=30706dcc8, ssh step timeouts (120 s, chunk 560 s,
  install 900, restore 600, scp 300) + the existing 120 s stall watchdog. HANDOFF: check 5 XR30 buffer creation is now
  pass/fail (pixels informational), commit errno lines fail checks 3/4/6.
- Branch fix/sunxi-h616-de33-wb-fb-formats (fork): 300d79df7 + 30706dcc8, W=1 clean, merged into test-cumulative:
  c34 = ed36b239c (300d79df7 only, Image md5 e40a7ba3152f13fad9f03d6165c38177, superseded), c35 = 30cee6952 (both,
  871 patches 0 failed, Image md5 f3ec40c60dfbc0bfa94fdcf53ec9169b). Pushed to fork, verified with ls-remote.
- Queued: harness/runner-queue/40-de33-writeback.md (`wb-job.sh wb40`, needs c35+). Next: fresh agent judges
  done/40-de33-writeback.summary.md with HANDOFF checks 0-8. If check 3 fails now with real captures, see "If check 3
  fails" above (mux value / capture window).

### Job 40 (2026-11-06, c35): checks 0-5, 7, 8 PASS; check 6 FAIL = test-client crash, fixed; re-queued as job 41
- PASS: probe (14 formats incl. XR30/NV12/NV21/YU12), solid1-4 + bars pixel-exact (fence 18.9-33.4 ms), NV12 max_dev 0,
  XR30 mismatches 0 (10-bit path verified at 8-bit depth), counters jobs==done, failed 0, dmesg clean. Kernel side done
  for static captures; 300d79df7 + 30706dcc8 confirmed.
- Check 6 FAIL: flips-d0/d4/d12 all rc 139 (SIGSEGV), output only "RC 139", 1 wb job done / 0 failed per run.
  Cause (TEST bug, kms-wb): commit() called drmModeAtomicCommit(..., NULL) as the page-flip event user data while the
  flips path set DRM_MODE_PAGE_FLIP_EVENT; drmHandleEvent() hands that user data to flip_handler(), which wrote
  ev->done through NULL on the first flip event (after the first writeback commit: hence exactly 1 job done). The
  RESULT lines were lost because stdout to a file is fully buffered. Not a kernel problem: the commit, the flip event
  and the out fence all arrived (the crash is in the event handler, before any fence handling).
- Fix: commit() takes the event user data (void *event, &fe from cmd_flips; fe.done reset before the commit),
  flip_handler ignores NULL data, stdout line-buffered. Client sha256 a30d348af2a0... (job 41 file has it).
- wb-job.sh: per-job RUNS list; `wb41` = probe, solid1, flips-d0/d4/d12 (CT 400 s); extract loops over RUNS
  (host-tested on a synthetic flips output; board script rendered + bash -n). HANDOFF: job 41 notes at the top
  (checks 0,1,2,3 solid1,6,7,8; 4/5 not run).
- Queued: harness/runner-queue/41-de33-writeback.md (`wb-job.sh wb41`, kernel c35 unchanged, logs/runner-wb41).
  Next: fresh agent judges done/41-*.summary.md; a real TORN/BAD frame or seq gaps there is a kernel latch/timing issue
  (see job 19 display tearing and 30706dcc8), not the client.
