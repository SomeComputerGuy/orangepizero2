# Job 69-image-check: new image on the board + image checks (runner package)

Type: DEV (takes the whole board). Expected duration: 70-90 min (reflash 20-40, restage of /root/cts 5-15, checks
~30: OpenCL suites ~15, GLES/Vulkan ~5 each). Read harness/AGENT-RULES.md and harness/RUNNER.md first.

## What it does
`image-check.sh` takes its own board lock (owner `image-check-<time>`), reflashes the board's SD card with the newest
SERVER image (harness/reflash.sh: dry run, real run, the REFLASH.md retry rules scripted), then checks the image on the
image's own kernel: kernel + boot, verify-board.sh, our +opiz2 packages (gst-plugins-bad/-good, Mesa fork 26cb3c93a58 = +opiz2.2),
GStreamer elements + JPEG decodes, gst-libav (job 24 check 1), `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` everywhere,
vulkaninfo / vkcube / dEQP-VK smoke + 9 subgroup cases, GLES and OpenCL regressions on the SYSTEM Mesa, dmesg. It also
restages /root/cts (harness/analysis/gpu/cts-restage.sh, without --start), which the reflash wipes and job 68 needs.
No trial kernel is installed, nothing is installed into the system. Results: harness/research/image-check/logs/runner/.

- Image: `armbian-build/output/images/Armbian-unofficial_26.11.0-trunk_Orangepizero2_stonking_edge_<kver>.img.xz`
  (newest; the server image = no `_minimal`/`_desktop` suffix) with its `.sha`. `<kver>` is read from the file name
  (7.3.3 for the 2026-11-07 build); nothing assumes 7.3.1. The script refuses to start without it.
- Debs inside the image: out/debs-media (gst-plugins-bad1.0 1.28.6-1ubuntu1+opiz2.1, gst-plugins-good1.0
  1.28.7-1build1+opiz2.1, mesa 26.2.4-1ubuntu1+opiz2.2 since the 2026-11-07 Vulkan 1.1 refresh; job 69 ran +opiz2.1); the server image has no FFmpeg/mpv.
- Preconditions (the script checks them): image + .sha present, scripts/serial-log.py running, ssh/serial on
  ttyOPIZ2 (reflash.sh checks the rest). Start when the coordinator says the user's ./build-all.sh has finished.

## Command (from /home/aruni/orangepizero2, one background command, wait for it; no polling under 10 min)
    bash harness/research/image-check/runner/image-check.sh > harness/research/image-check/logs/runner-stdout.txt 2>&1; echo "rc=$?" >> harness/research/image-check/logs/runner-stdout.txt
    bash harness/research/image-check/runner/image-check.sh --check

Exit codes: 0 all 11 steps done; 2 BLOCKED (logs/runner/BLOCKED has the reason) or unfinished steps; 4 paused;
1 setup/lock error (the log says which). Exit 2 with "unfinished steps": run the same command ONCE more (finished steps
are skipped); still unfinished -> report NOT FINISHED with `tail -5` of each unfinished step's `<step>.txt`.
BLOCKED: report the reason verbatim and stop (do not reflash by hand). "Host key verification failed" = BLOCKED.
Pause: `touch harness/research/image-check/logs/runner/PAUSE` (stops before the next step, releases the lock, exit 4);
resume: `rm` the PAUSE file and run the same command. Other sessions waiting for the board get it between steps.
Stall watchdog: every step is killed after 15 min without output (reflash: 40 min) or its timeout.

## Pass/fail (mechanical: `--check` prints them; copy every CHECK line and the VERDICT line verbatim)
| # | check | PASS when |
|---|---|---|
| 0 | image | image.txt has the image path, kernel version, sha line |
| 1 | reflash | `FLASHER: RESULT OK` and `ssh ok:` in the reflash logs, last log ends `rc=0`, no oops/BUG:/panic |
| 2 | kernel + boot | `uname -r` = `<kver>-edge-sunxi64`, /boot/Image -> `vmlinuz-<kver>-edge-sunxi64` |
| 3 | verify-board | 0 `FAIL` lines, >= 20 `PASS` (CUPS, scan stack, GStreamer JPEG autoplug, ...) |
| 4 | packages | listed mesa/gst packages installed and `+opiz2`; no installed package of those 3 sources without `+opiz2`; repo file:/opt/opiz2-media |
| 5 | gst elements | v4l2sljpegdec, v4l2jpegdec, v4l2sl{h264,h265,mpeg2,vp8,vp9}dec, jpegdec, avdec_mpeg2video exist; v4l2jpegdec rank MARGINAL |
| 6 | JPEG decodes | 320x240 picture: v4l2sljpegdec and v4l2jpegdec rc=0, 115200 bytes, cedrus irqs >= 1; jpegdec rc=0; decodebin rc=0 and not v4l2jpegdec |
| 7 | gst-libav (job 24 check 1) | no MG1S on the image kernel; ccm1 via decodebin rc=0, 49536 bytes, irqs=0, picked avdec_mpeg*/mpeg2dec (SKIP if the kernel has MG1S) |
| 8 | Vulkan env | `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` in the ssh login shell, /etc/environment, system manager, user.conf.d, environment.d generator, a systemd-run service |
| 9 | vulkaninfo | login env without setting the variable: panvk device apiVersion `1.1.x` (Mesa +opiz2.2; job 69 on +opiz2.1 had 1.0.354), deviceName Mali-G31, driverInfo `+opiz2` |
| 10 | vkcube --c 100 | rc=0 on an HDMI display; no display connected = NOT-TESTED (vkcube has no headless WSI) |
| 11 | Vulkan offscreen | dEQP-VK.api.smoke.* Failed 0 and triangle Pass; 9/9 job 52 subgroup cases Pass (MESA_VK_VERSION_OVERRIDE=1.1 for those only, a no-op since +opiz2.2); 0 GPU fault lines |
| 12 | GLES | eglinfo renderer Mali-G31, `OpenGL ES 3.1` with `+opiz2`; gles3 derivate `556 cases`, `Pass 556`; 0 GPU fault lines |
| 13 | kmscube | rc=0 on an HDMI display; no display = NOT-TESTED |
| 14 | OpenCL | clinfo rc=0, platform rusticl, device Mali-G31; job 52's 8 suites all Pass; 0 GPU fault lines |
| 15 | dmesg | 0 Oops/BUG:/panic/INSTR_INVALID_ENC/js fault/Unhandled fault lines |
| 16 | /root/cts restaged | cts-restage.sh ended `staged; not started`, rc=0 |
| 17 | end state | board on `vmlinuz-<kver>-edge-sunxi64`, lock released |

VERDICT: `PASS`, `PASS (with NOT-TESTED checks: no display attached)` or `FAIL`. NOT-TESTED is never a FAIL.

## Summary (harness/runner-queue/done/69-image-check.summary.md) must list
The image file + sha line, start/end times, the kernel (`uname -v` from pkgs.txt), every CHECK line verbatim, the
VERDICT, the FAIL lines of verify.txt (if any), any DMESG-LINE lines, and the result paths
(harness/research/image-check/logs/runner/, files/). Commit the summary and logs/runner/*.txt, *.log, check.txt
(`git commit -- <paths>`, author Arun Iyengar, no Co-Authored-By), push origin main, report once.

## After this job
The board's stock kernel is now the image's `<kver>` (7.3.3), not 7.3.1. Then resume job 68 with its own command
(`bash harness/research/vk11/runner/vk11-main.sh`): vk11-main.sh, vdec-perf/install-kernel.sh, restore-kernel.sh and the
vdec fallback no longer assume 7.3.1 (fixed 2026-11-07: stock = the board's newest vmlinuz-*-edge-sunxi64, trial =
vmlinuz-<release>-vdec-<tag>, release read from the modules archive). /root/cts was restaged by check 16.
