# DE33 writeback connector runner job wb40 (queue job 40): handoff

Command: `bash harness/research/de33-writeback/runner/wb-job.sh wb40`

Why job 40 (after job 30 on c27, FAIL): every flip+writeback commit returned -EINVAL and the XR30 capture buffer could
not be created. Causes: (1) test bug: kms-wb attached the writeback connector to the CRTC in the first writeback commit;
adding a connector to a CRTC is a full modeset, refused without ALLOW_MODESET. kms-wb now attaches it in its modeset
commit. (2) kernel bug: ADDFB2 refused XRGB2101010 (a writeback-only format, on no plane); fixed by 300d79df7. Also
fixed: 30706dcc8 (a capture could start one frame early, before its commit was latched), the flips result labels in
results.txt (shifted by one in job 30), and commit failures are now reported as `*_commit_errno` instead of
`fence_error -1`.

Purpose: mechanical check of the kernel branches `fix/sunxi-h616-de33-writeback` (1b4c0f53b + 6dbed6c18) and
`fix/sunxi-h616-de33-wb-fb-formats` (300d79df7 + 30706dcc8, armbian-build, in test-cumulative from c35; the H616 DE33 real-time write-back unit exposed as a DRM writeback connector, see
harness/research/impl-de33-writeback.md). The board has no monitor: HDMI-A-1 is forced on (`echo on > status`), the test runs
at 1024x768@60 and the writeback connector captures the composed frame into memory, where the test client
(harness/kms-wb/out/kms-wb, libdrm only) compares it with the framebuffer it displayed. This is the first check that sees the
picture itself: a solid colour or colour bars must come back pixel-exact, and a page-flip sequence between two colours must
never capture a frame with rows of both colours (a torn frame), which complements job 19 (register write timing).

Precondition (coordinator): the newest cumulative kernel must contain 30706dcc8 (c35 = test-cumulative 30cee6952, Image md5
f3ec40c60dfbc0bfa94fdcf53ec9169b, already built) and be served as kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz. The script installs
the NEWEST cumulative tag (last line of kernel-check/cumulative-kernels.txt) via harness/research/vdec-perf/install-kernel.sh
with the one-shot fallback armed; the HTTP server on 10.56.0.1:8643 must be up. install-kernel.sh also installs the tag's
Zero2 DTB (kernel-check/vdec-serve/sun50i-h616-orangepi-zero2.dtb.<tag>): job 21 was BLOCKED because the stock DTB has no
writeback@10000 node (no connector) and only Image + modules were installed. It checks that 30706dcc8 is an ancestor of
the tag's commit, that the booted DTB has the tag's md5, that /sys/module/sun8i_mixer/parameters/de33_wb_jobs exists and
that /sys/class/drm/card*-Writeback-1 exists; otherwise it writes BLOCKED and exits 2 (report that, not a FAIL, with the
first 30 lines of files/blocked-<tag>/state.txt: DT nodes, devices_deferred; files/blocked-<tag>/dmesg.txt is the full
dmesg, files/blocked-connector/drm-classes.txt the DRM class list). The restore goes through
harness/research/vdec-perf/restore-kernel.sh (Image, DTB, modules). The client
is shipped to /root/wb/kms-wb if the board copy differs. The board must start on the stock image kernel.

DEV or TEST: DEV-length, about 7 min: install + reboot (~3 min), 11 short runs (~1.5 min), restore (~1 min). Runs: probe;
solid 3c7ab4, c81e5a, 000000, ffffff (3 XR24 captures each); bars (3 XR24 captures); nv12 (NV12 capture, tolerance 3);
xr30 (XRGB2101010 capture, tolerance 4, informational); flips-d0, flips-d4, flips-d12 (300 page flips between 40c0e0 and
e04020 with one capture per flip, the commit issued right after the flip event, 4 ms after it (inside the active video, ~line
190 of 806) and 12 ms after it). Resumable: re-running skips chunks listed in logs/runner-wb40/state. Every board command has a step timeout (ssh 120 s,
the chunk 560 s, install 900 s, restore 600 s, scp 300 s) and the chunk has a stall watchdog (no output for 120 s = killed). The stock kernel
vmlinuz-7.3.1-edge-sunxi64 is restored at the end and before every lock hand-over.

Fail fast: the serial log and the chunk's dmesg are watched for `Unable to handle|Oops|WARNING:|flip_done timed out|vblank
wait timed out|workqueue lockup|iommu.*fault|Page fault`; a hit ends the job (exit 3, lines in logs/runner-wb40/OOPS): report
FAIL (OOPS) with the OOPS content and the last 10 lines of runner.log. An IOMMU fault here means the write-back wrote through
an unmapped address: report it verbatim.

Results: harness/research/de33-writeback/logs/runner-wb40/: runner.log, results.txt (one line per value: `wb <run> <key>
<value>`), chunk-wb.txt, files/wb/{kernel.txt,connectors.txt,<run>.txt,<run>.params.before/.after,dmesg-chunk.txt,dump/*.raw
(mismatching captures, raw pixels)}, OOPS / BLOCKED only when they happened.

Exit codes: 0 = chunk ran, judge with the checks below; 3 = Oops/WARN/IOMMU fault, FAIL; 2 = blocked (report BLOCKED and
the last 10 lines of runner.log); 1 = setup or lock error.

## Checks (mechanical, all on results.txt unless stated)
Any `capture<N>_commit_errno`, `modeset_commit_errno`, `flip_commit_errno` or `capture_buffer_errno` line in a run of
checks 3, 4 or 6 makes that check FAIL: report the key and value (22 = EINVAL) and the run's first 5 lines of
files/wb/<run>.txt that contain `atomic commit` or `dumb buffer`.
0. Display rule: if results.txt has `wb all mode_unavailable 1` or `wb probe mode_unavailable 1`, the chunk is NOT TESTED
   (the forced connector offered no 1024x768 mode), never FAIL; report files/wb/connectors.txt and skip the other checks.
1. runner.log contains a `kernel: ` line, a `kernel dtb: ` line and `kernel writeback: present`. Report all three.
2. Connector present: `wb probe writeback_connectors` >= 1, `wb probe wb_reaches_crtc 1`, `wb probe wb_format_offered 1`,
   `wb probe probe ok`, `wb probe rc 0` -> PASS, else FAIL (report files/wb/probe.txt). Also report `wb probe wb_formats`.
3. Exact captures: for each of solid1..solid4 and bars: `rc` is 0, `captures_failed` is 0 and every `capture<N>_mismatches`
   is 0 -> PASS. Else FAIL with the values (mismatches, max_dev, the `first` position line from files/wb/<run>.txt, and the
   dump file names). Report `capture<N>_fence_ms` (expected 20-60 ms: the job starts at the next vblank and completes at
   the one after).
4. NV12 capture: `wb nv12 rc 0`, `captures_failed 0`, every `capture<N>_mismatches 0` (tolerance 3 per component against
   BT.601 limited range) -> PASS, else FAIL with `capture<N>_max_dev` and the first-mismatch line. A FAIL here with checks
   2-3 green means the CSC/chroma path of the write-back needs work, not the connector.
5. XR30 capture buffer: results.txt has no `wb xr30 capture_buffer_errno` line and `wb xr30 rc` is 0 or 1 (not 2) -> PASS
   (the XRGB2101010 framebuffer can be created and committed), else FAIL with the errno. The pixel values are
   informational: report `captures_failed`, `capture<N>_mismatches`, `capture<N>_max_dev` (top 8 bits of each 10-bit
   component vs the 8-bit source, tolerance 4), `capture<N>_commit_errno` / `capture<N>_fence_error` if present.
6. Tearing (the picture-level check), for flips-d0, flips-d4 AND flips-d12: `rc 0`, `flips_requested 300`,
   `frames_captured` >= 298 (of 300),
   `frames_torn 0`, `frames_bad 0`, `fence_errors 0`, `seq_gaps 0` -> PASS. Any miss -> FAIL with the values, the
   `first_torn_flip` and the `RESULT flip <n> TORN ...` lines (first 5) from files/wb/<run>.txt. Also report
   `flip_rate` (expected 29-31: one capture completes per two frames), `frames_a`, `frames_b`, and for d4/d12
   `commits_outside_blanking` of `commits_counted` (expected: all outside, the commit was placed in the active video on
   purpose), plus `latch_flushes_late_delta` (expected 0: the latch wrote every frame in the blanking).
7. Kernel counters, per run: `wb_jobs_delta` == `wb_done_delta` and `wb_failed_delta 0` -> PASS, else FAIL with the
   values; report `wb_busy_frames_delta` (data: captures not finished by the next vblank) and `wb_status_last`.
8. dmesg: `wb all dmesg_bad 0` -> PASS; else FAIL, copy the matching lines from files/wb/dmesg-chunk.txt exactly. Report
   `wb all dmesg_iommu` and any `iommu|sun50i|drm|sun4i|sun8i` lines (first 10).

The summary must list: the kernel line, the per-run table (run, rc, and the keys of checks 2-7 for that run), the dmesg
counts, the state file content, and OOPS/BLOCKED verbatim if they exist.
