# H616 VE H.264 encoder runner job venc: handoff

Command: `bash harness/research/ve-encoder/runner/venc-job.sh venc`

Purpose: first board check of the cedrus stateless H.264 encoder (armbian-build branch `fix/sunxi-h616-venc`, commit
f35cdf390: Paul Kocialkowski's stateless H.264 encode uAPI core, patches 0801-0809 shared byte for byte with the OPi5
project, plus the cedrus encoder as a second video device "cedrus-enc" on the H616 video engine; see
harness/research/ve-encoder/RESULTS.md). Nothing of it has run on hardware yet: the register programming follows the
vendor library as recorded by the Hardened-BliKVM lab on an H616 and Bootlin's V3s encoder. The job checks that the
encoder probes, passes v4l2-compliance, encodes raw NV12 test clips (all-intra and I+P, 720p, 1080p, 1366x768) into
H.264 that the host ffmpeg decodes without errors with the right frame count and a sane PSNR, that the board's own
hardware decoder decodes the same streams bit-exactly, and that no IOMMU fault or engine timeout happens.

Precondition (coordinator): `fix/sunxi-h616-venc` at 4d9a200e8 (f35cdf390 encoder + ac009bb5b/c307dd053 "register
the encoder's own media entities" + 201516cc5 "give every encoder address register a buffer" (the job 34 IOMMU page
fault for address 0 at the start of every picture) + 4d9a200e8 v4l2-compliance fixes) merged into `test-cumulative`
and built: c30 is the first such kernel (c29 = job 34 faulted on every picture; c26-c28 hang in every
MEDIA_IOC_G_TOPOLOGY, job 32). Served as kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz + DTB. The script installs the NEWEST
cumulative tag (last line of kernel-check/cumulative-kernels.txt) via harness/research/vdec-perf/install-kernel.sh
with the one-shot fallback armed; the HTTP server on 10.56.0.1:8643 must be up. It checks that 4d9a200e8 is an
ancestor of the tag's commit and that the booted kernel logged `cedrus ... Encoder registered as /dev/videoN`;
otherwise it writes BLOCKED and exits 2 (report that, not a FAIL). The test tool
(harness/research/ve-encoder/tools/out/h264enc-test, static aarch64, built by tools/build.sh) and the raw clips
(generated on the host by the script with ffmpeg testsrc2, 41 + 31 + 8 MB, xz-compressed for the transfer) are shipped
only when the board copies differ. The board must start on the stock image kernel. Host ffmpeg: /usr/local/bin/ffmpeg.

DEV or TEST: DEV-length, about 10 min: clip generation + shipping (~2 min the first time), install + reboot (~3 min),
compliance + five encodes + hardware decodes (~2 min), restore (~1 min). Resumable: re-running skips chunks listed in
logs/runner-venc/state. The stock kernel vmlinuz-7.3.1-edge-sunxi64 is restored at the end and before every lock
hand-over.

Every board step announces itself (`STEP <name>` in chunk-venc.txt: probe, topology, enc-info, compliance, encode rN,
hwdec rN, dmesg) and runs under its own `timeout -k 5`. On a stall the host logs `STALL ... in step '<name>'`, collects
files/stall-diag-venc.txt (D/R tasks, their /proc/PID/stack, dmesg tail) over a fresh ssh session and restores through
restore-kernel.sh (a reboot with a stuck task takes up to ~6 min; the script waits 500 s). Report a stall as FAIL
(STALL) with the step name and the first 40 lines of stall-diag-venc.txt.

Fail fast: the serial log and the chunk's dmesg are watched for `Unable to handle|Oops|WARNING:|workqueue lockup|
iommu.*fault|Page fault|frame processing timed out`; a hit ends the job (exit 3, lines in logs/runner-venc/OOPS):
report FAIL (OOPS) with the OOPS content and the last 10 lines of runner.log. An IOMMU fault here means the encoder
read or wrote through an unmapped address: report the lines verbatim (they name the master and the address).

Results: harness/research/ve-encoder/logs/runner-venc/: runner.log, results.txt (one line per value: `venc <run> <key>
<value>`), chunk-venc.txt, files/venc/{kernel.txt,nodes.txt,probe.txt,dmesg-probe.txt,enc-D.txt,dec-D.txt,enc-all.txt,enc-ctrls.txt,enc-fmt-*.txt,
compliance.txt,r1..r5.txt (encoder log),r1..r5.h264 (the streams),r1..r5.ffmpeg-err.txt,r1..r5.psnr.txt,
r1..r5.hwdec.txt,dmesg-chunk.txt}, OOPS / BLOCKED only when they happened.

Runs (all QP fixed, CAVLC, constrained baseline): r1 1280x720 30 frames all IDR QP 26; r2 1280x720 30 frames IDR every
10 + P QP 26; r3 1920x1080 10 frames all IDR QP 20; r4 1920x1080 10 frames IDR every 10 + P QP 30; r5 1366x768 5 frames
all IDR QP 26 (a size that is not a multiple of 16: cropping and the 8-pixel ISP units).

Exit codes: 0 = chunk ran, judge with the checks below; 3 = Oops/WARN/IOMMU fault, FAIL; 2 = blocked (report BLOCKED
and the last 10 lines of runner.log); 1 = setup or lock error.

## Checks (mechanical, all on results.txt unless stated)
1. Probe: `venc all probe_registered 1` and `venc all encoder_node 1` -> PASS, else FAIL (report files/venc/dmesg-probe.txt
   and nodes.txt). Report the `kernel: ` and `kernel encoder: ` lines of runner.log and `venc all controls` (expected 20;
   job 34 had 21 before MIN_BUFFERS_FOR_OUTPUT was dropped).
   Media controller (the job 32 hang): `venc all boot_warnings 0` (no kernel WARNING at boot; job 32 had the
   mc-device.c:619 one twice; on a FAIL report the first 40 lines of files/venc/boot-warnings.txt), `venc all media_node /dev/mediaN` (not `none`; job 34's `none` was the package looking in /sys/class/media
   instead of /sys/bus/media/devices, fixed), `venc all media_info 1` (v4l2-ctl -D on
   the encoder prints "Media Driver Info": the topology ioctl answered) and `venc all dec_D_rc 0` (same on the decoder
   node) -> PASS, else FAIL with the values, the `venc all media` lines and files/venc/enc-D.txt (first 20 lines).
   `media_info 0` with enc-D.txt ending in `RC 124` or `RC 137` = the topology hang is back.
2. Compliance: `venc all compliance_unexpected 0` -> PASS; a number > 0 -> FAIL, report every `fail:` line of
   files/venc/compliance.txt (first 20) and the `Total` line; `venc all compliance SKIP` -> SKIP (v4l2-compliance not on
   the board), report as SKIP, not FAIL. Report `venc all compliance_failed` (expected 1: the test VIDIOC_G/S_PARM,
   `fail: v4l2-test-formats.cpp(1445)`, is justified: v4l2-compliance 1.32 allows the frame-rate ioctls only on
   stateful encoders and predates the stateless encode uAPI, which needs them; the OPi5 Hantro/VEPU580 encoders fail
   the same test; `compliance_unexpected` counts the other `fail:` lines) and `venc all compliance_warnings`.
3. Encode, for each of r1..r5: `rc 0`, `errors 0`, `frames` equal to the run's frame count (30, 30, 10, 10, 5) and
   `stream_bytes` > 0 -> PASS, else FAIL with the `RESULT` line and the `ERROR`/`error` lines of files/venc/<run>.txt.
   Report `bytes`, `keyframes` (expected 30, 3, 10, 1, 5), `avg_us` and `max_us` (the engine takes about 3 ms at
   720p and 7 ms at 1080p; the figure includes the request round trip).
4. Decode on the host, for each run: `ffmpeg_errors 0` and `decoded` equal to the run's frame count -> PASS, else FAIL
   with files/venc/<run>.ffmpeg-err.txt (first 10 lines).
5. Quality, for each run: `psnr_avg` >= 30 and `psnr_min` >= 28 (dB, luma, against the source clip) -> PASS, else FAIL
   with the values. Report both values and `psnr_frames` for every run; a QP 26 encode of testsrc2 is expected around
   38-45 dB, QP 30 around 35, a wrong encode below 20.
6. Hardware decode, for each run: `hwdec_frames` equal to the frame count and `hwdec_md5_match 1` -> PASS; `hwdec SKIP`
   (no gst-launch-1.0 on the board) -> SKIP; else FAIL with the last 5 lines of files/venc/<run>.hwdec.txt. A FAIL
   here with checks 3-5 PASS means the H.264 decoder or GStreamer, not the encoder: report it as such.
7. dmesg: `venc all dmesg_bad 0`, `dmesg_iommu 0`, `dmesg_timeout 0`, `dmesg_encode_failed 0` -> PASS; else FAIL, copy
   the matching lines from files/venc/dmesg-chunk.txt exactly (first 20). `dmesg_encode_failed` counts only the encode
   steps (files/venc/dmesg-encodes.txt): the v4l2-compliance "Requests" test queues requests without the SPS/PPS/encode
   controls and the driver logs `Failed to setup encoding job: -22` twice for them (expected, in dmesg-chunk.txt only).

The summary must list: the kernel line, check 1 and 2 values (compliance_failed, compliance_unexpected, warnings), the per-run table (run, size, frames, keyframes, bytes,
avg_us, decoded, ffmpeg_errors, psnr_avg, psnr_min, hwdec_frames, hwdec_md5_match, PASS/FAIL per check), the dmesg
counts, the state file content, and OOPS/BLOCKED verbatim if they exist.
