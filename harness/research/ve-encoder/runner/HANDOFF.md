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

Precondition (coordinator): `fix/sunxi-h616-venc` at d6d2ce09b (f35cdf390 encoder + ac009bb5b/c307dd053 "register
the encoder's own media entities" + 201516cc5 "give every encoder address register a buffer" (the job 34 IOMMU page
fault for address 0 at the start of every picture) + 4d9a200e8 v4l2-compliance fixes + 4727ed447 (job 35: puts of at
most 24 bits, so the start codes and the SPS VUI timing fields reach the stream; a picture-sized macroblock info
buffer; SPS/PPS with nal_ref_idc 3) + d6d2ce09b (job 37: the NV12 source buffer gets one more macroblock row, because
the engine reads past the end of the picture: the 1366x768 fault at 0xfff83000 of jobs 35 and 37; the IOVA and size of
every encoder buffer in /sys/kernel/debug/cedrus/encoder-buffers and in dmesg after an encode timeout)) merged into
`test-cumulative` and built: c33 is the first such kernel (c32 = job 37: r1-r4 PASS, r5 fault; c31 = job 35:
undecodable streams + the r5 fault; c29 = job 34 faulted on every picture;
c26-c28 hang in every MEDIA_IOC_G_TOPOLOGY, job 32). Served as kernel-check/vdec-serve/Image.<tag> + modules-<tag>.tgz + DTB. The script installs the NEWEST
cumulative tag (last line of kernel-check/cumulative-kernels.txt) via harness/research/vdec-perf/install-kernel.sh
with the one-shot fallback armed; the HTTP server on 10.56.0.1:8643 must be up. It checks that 4727ed447 is an
ancestor of the tag's commit and that the booted kernel logged `cedrus ... Encoder registered as /dev/videoN`;
otherwise it writes BLOCKED and exits 2 (report that, not a FAIL). FIX in the script is d6d2ce09b. The test tool
(harness/research/ve-encoder/tools/out/h264enc-test, static aarch64, built by tools/build.sh) and the raw clips
(generated on the host by the script with ffmpeg testsrc2, 41 + 31 + 8 MB, xz-compressed for the transfer) are shipped
only when the board copies differ. The board must start on the stock image kernel. Host ffmpeg: /usr/local/bin/ffmpeg.

DEV or TEST: DEV-length, about 10 min: clip generation + shipping (~2 min the first time), install + reboot (~3 min),
compliance + seven encodes + hardware decodes (~2 min), restore (~1 min). Resumable: re-running skips chunks listed in
logs/runner-venc/state. The stock kernel vmlinuz-7.3.1-edge-sunxi64 is restored at the end and before every lock
hand-over.

Every board step announces itself (`STEP <name>` in chunk-venc.txt: probe, topology, enc-info, compliance, encode rN,
hwdec rN, dmesg) and runs under its own `timeout -k 5`. On a stall the host logs `STALL ... in step '<name>'`, collects
files/stall-diag-venc.txt (D/R tasks, their /proc/PID/stack, dmesg tail) over a fresh ssh session and restores through
restore-kernel.sh (a reboot with a stuck task takes up to ~6 min; the script waits 500 s). Report a stall as FAIL
(STALL) with the step name and the first 40 lines of stall-diag-venc.txt.

Fail fast: the serial log and the chunk's dmesg are watched for `Unable to handle|Oops|WARNING:|workqueue lockup|
iommu.*fault|Page fault|frame processing timed out`; a hit ends the job (exit 3, lines in logs/runner-venc/OOPS):
report FAIL (OOPS) with the OOPS content and the last 10 lines of runner.log. A dmesg hit is found only after the chunk
ended, so every run was attempted and results.txt is complete: still apply checks 1-8 and report all of them (job 35's
summary wrongly said "r2+ aborted"; r1-r4 had completed and the fault was r5's). An IOMMU fault here means the encoder
read or wrote through an unmapped address: report the lines verbatim (they name the master and the address).

Results: harness/research/ve-encoder/logs/runner-venc/: runner.log, results.txt (one line per value: `venc <run> <key>
<value>`), chunk-venc.txt, files/venc/{kernel.txt,nodes.txt,probe.txt,dmesg-probe.txt,enc-D.txt,dec-D.txt,enc-all.txt,enc-ctrls.txt,enc-fmt-*.txt,
compliance.txt,compliance-enc.txt (the encoder node's section),compliance-dec-fails.txt,r1..r7.txt (encoder log),
r1..r7.h264 (the streams),r1..r7.dmesg.txt (dmesg of that run),r1..r7.buffers.txt (IOVA start, end, size of every
encoder buffer of the run's last picture),r1..r7.ffmpeg-err.txt,r1..r7.psnr.txt,r1..r7.hwdec.txt,dmesg-chunk.txt}, OOPS / BLOCKED only when they happened.

Runs (all QP fixed, CAVLC, constrained baseline): r1 1280x720 30 frames all IDR QP 26; r2 1280x720 30 frames IDR every
10 + P QP 26; r3 1920x1080 10 frames all IDR QP 20; r4 1920x1080 10 frames IDR every 10 + P QP 30; r5 1366x768 5 frames
all IDR QP 26 (a size that is not a multiple of 16: cropping and the 8-pixel ISP units; its NV12 picture fills its last
page to the byte, so a read past the end faults: jobs 35 and 37); r6 720x480 10 frames IDR every 5 + P QP 26; r7
854x480 10 frames IDR every 5 + P QP 26 (a width that is not a multiple of 16, with P pictures).

Shipping (job 38 r7 package bug, fixed for job 39): every clip is shipped in a for loop and its sha256 is checked on the
board afterwards; runner.log must show `clips on the board: 5 of 5 current` before the kernel install, else the job
is BLOCKED (`clip <name>.nv12 missing or different on the board after shipping`): report BLOCKED, not FAIL.

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
   files/venc/compliance-enc.txt (first 20) and its `Total` line. Only the encoder node counts: with `-m` the tool also
   tests the decoder node, whose `fail: v4l2-test-codecs.cpp(161)` (job 35) is the known stock v4l2-compliance 1.32
   limitation with the cedrus decoder's extra fourccs (harness/research/impl-cedrus-compliance.md); report
   `venc all compliance_dec_fail` (expected 1) and the lines of files/venc/compliance-dec-fails.txt as information; `venc all compliance SKIP` -> SKIP (v4l2-compliance not on
   the board), report as SKIP, not FAIL. Report `venc all compliance_failed` (expected 1: the test VIDIOC_G/S_PARM,
   `fail: v4l2-test-formats.cpp(1445)`, is justified: v4l2-compliance 1.32 allows the frame-rate ioctls only on
   stateful encoders and predates the stateless encode uAPI, which needs them; the OPi5 Hantro/VEPU580 encoders fail
   the same test; `compliance_unexpected` counts the other `fail:` lines) and `venc all compliance_warnings`.
3. Encode, for each of r1..r7: `rc 0`, `errors 0`, `frames` equal to the run's frame count (30, 30, 10, 10, 5, 10, 10) and
   `stream_bytes` > 0 -> PASS, else FAIL with the `RESULT` line and the `ERROR`/`error` lines of files/venc/<run>.txt.
   Report `bytes`, `keyframes` (expected 30, 3, 10, 1, 5, 2, 2), `avg_us` and `max_us` (the engine takes about 3 ms at
   720p and 7 ms at 1080p; the figure includes the request round trip).
4. Decode on the host, for each run: `ffmpeg_errors 0` and `decoded` equal to the run's frame count -> PASS, else FAIL
   with files/venc/<run>.ffmpeg-err.txt (first 10 lines).
5. Quality, for each run: `psnr_avg` >= 30 and `psnr_min` >= 28 (dB, luma, against the source clip) -> PASS, else FAIL
   with the values. Report both values and `psnr_frames` for every run; a QP 26 encode of testsrc2 is expected around
   38-45 dB, QP 30 around 35, a wrong encode below 20.
6. Hardware decode, for each run: `hwdec_frames` equal to the frame count and `hwdec_md5_match 1` -> PASS; `hwdec SKIP`
   (no gst-launch-1.0 on the board) -> SKIP; else FAIL with the last 5 lines of files/venc/<run>.hwdec.txt. A FAIL
   here with checks 3-5 PASS means the H.264 decoder or GStreamer, not the encoder: report it as such.
   The md5 is over the visible pixels only (since job 39): GStreamer's NV12 dump has stride ROUND_UP_4(width) and its
   padding bytes are not written by the decoder, so job 38's r5 (1366 wide, stride 1368) "mismatch" was the padding.
   The `HWDEC` line in <run>.hwdec.txt also gives `raw <bytes of the GStreamer dump>` and `crop frames N stride S rest R`;
   report them for r5 and r7 (expected r5: raw 7879680, crop frames 5 stride 1368 rest 0; r7: raw 6163200 (stride
   856), crop frames 10 stride 856 rest 0). `rest` other than 0 -> FAIL (the dump layout is not GStreamer's default).
7. dmesg: `venc all dmesg_bad 0`, `dmesg_iommu 0`, `dmesg_timeout 0`, `dmesg_encode_failed 0` -> PASS; else FAIL, copy
   the matching lines from files/venc/dmesg-chunk.txt exactly (first 20). `dmesg_encode_failed` counts only the encode
   steps (files/venc/dmesg-encodes.txt): the v4l2-compliance "Requests" test queues requests without the SPS/PPS/encode
   controls and the driver logs `Failed to setup encoding job: -22` twice for them (expected, in dmesg-chunk.txt only).
   Per run, report `dmesg_iommu` and `dmesg_timeout` of each rN (files/venc/rN.dmesg.txt): they name the run a fault
   belongs to (job 35's fault was r5's, after r1-r4 had completed).
8. Stream framing, for each run (job 35's streams had no start codes): `start_first 1`, `sps_ref_idc 3`,
   `nal_idr` equal to `keyframes`, `nal_sps` equal to `nal_idr` (SPS and PPS before every IDR), `nal_pps` equal to
   `nal_sps`, and `nal_idr` + `nal_p` equal to the frame count -> PASS, else FAIL with the values and `head_hex`.
   Expected: r1 30/30/0 (sps/idr/p), r2 3/3/27, r3 10/10/0, r4 1/1/9, r5 5/5/0, r6 2/2/8, r7 2/2/8. Report `head_hex` of r1 (should begin
   `000000016742c028`).

9. Encoder buffers, for each run: `buffers_format 1` (the list's `format WxH` line is this run's size: the list is
   written only after an encode with RC 0, else buffers.txt says `NO-ENCODE RC n`), `buffers_file 4` and `source_room 1` (the `source_bytes` value is at least its `want`
   value: the source buffer has the macroblock row of room past the picture) -> PASS, else FAIL with the
   `source_bytes` line and files/venc/<run>.buffers.txt. `buffers_file 0` with buffers.txt saying "No such file" = the
   kernel lacks d6d2ce09b or debugfs is not mounted. On any IOMMU fault (check 7), copy the run's buffers.txt verbatim
   next to the fault line, and also the dmesg lines that follow `frame processing timed out!` (`encoder buffers: ...`
   and one line per buffer): together they name the buffer the faulting address belongs to.

The summary must list: the kernel line, check 1 and 2 values (compliance_failed, compliance_unexpected, warnings,
compliance_dec_fail), the per-run table (run, size, frames, keyframes, bytes, avg_us, decoded, ffmpeg_errors,
psnr_avg, psnr_min, hwdec_frames, hwdec_md5_match, start_first, nal_sps/nal_idr/nal_p, dmesg_iommu, source_bytes,
source_room, PASS/FAIL per check), r1's head_hex, the dmesg
counts, the state file content, and OOPS/BLOCKED verbatim if they exist.
