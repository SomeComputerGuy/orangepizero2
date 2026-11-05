# Runner package: VP9 inter-frame UPSIZE (job vp9-upsize, DEV, ~10 min)

Command (host, as aruni, from /home/aruni/orangepizero2):

    bash harness/vp9-vectors/run-upsize.sh

What it tests: cedrus decoding `vp90-2-22-svc_1280x720_3.ivf` (inter frames grow 320x180 -> 640x360 -> 1280x720,
one key frame in the stream; the one "group B" vector of the 64) through the VIDIOC_REMOVE_BUFS renegotiation
(armbian-build branch `fix/sunxi-cedrus-vp9-inter-upsize`, commit 7897dec08), plus the 26 inter-frame downsize vectors
(f8be54bac, no regression) and a 25-vector profile-0 regression subset, with the same dev v4l2codecs plugin as job 10
(harness/vp9-vectors/patches/0001-0002; the bundle `build/vp9-vectors/bundle.tar` was rebuilt for the new chunks).

Kernel: the **newest cumulative kernel** (last line of kernel-check/cumulative-kernels.txt), which **must contain
7897dec08**: the script checks that with git before touching the board and exits 2 with `logs/upsize/BLOCKED`
("does not contain the upsize fix") otherwise. If BLOCKED: report it verbatim; the coordinator has to merge the branch
into test-cumulative and cumul-build first, then re-queue. Otherwise the script is run-job.sh (board lock owner
`runner-vp9-<epoch>`, trial kernel with the vdec fallback armed, HTTP server 10.56.0.1:8643, bundle shipped to
/root/vp9, pre-flight on vp90-2-00-quantizer-00.webm, stall watchdog 300 s, results copied after every chunk, stock
kernel vmlinuz-7.3.1-edge-sunxi64 restored, lock released) with the chunks u1 (27 vectors, ~2 min) and u2 (25 vectors,
~3 min; contains the 1920x1080 and two key-frame-resize vectors). Resumable: chunks in `logs/upsize/state` are skipped.
Wait with one background command.

Exit codes: 0 = both chunks ran (judge with the checks); 2 = blocked (report `logs/upsize/BLOCKED` + the last 10 lines
of `logs/upsize/runner.log`); 1 = setup error (bundle or kernel package missing).

Results: `harness/vp9-vectors/logs/upsize/`: `runner.log`, `kernel.txt`, `fix.txt`, `chunk-u1.txt`, `chunk-u2.txt`,
`dmesg-u1.txt`, `dmesg-u2.txt`, `out/u1.md`, `out/u2.md` (fluster summaries, tokens OK/KO/ER/TO/NS), `out/u1.log`,
`out/u2.log`, `out/pre.md`, `out/pre.gst.txt`, `out/env.txt`, `check.txt`.

## Checks (mechanical)

Run (the script already does it at the end; re-run if needed):

    python3 -I harness/vp9-vectors/check-results.py harness/vp9-vectors/logs/upsize upsize

and copy its `CHECK ...: PASS|FAIL (...)` lines, the `VERDICT:` line and the `| group | success | total | failing |`
table into the summary verbatim. The checks are:

| # | check | PASS if |
|---|---|---|
| 0 | kernel and pre-flight | kernel.txt's test-cumulative sha contains 7897dec08 (git) and `out/pre.md` has vp90-2-00-quantizer-00.webm = OK |
| 1 | both chunks ran | u1.md and u2.md present, 27 + 25 = 52 vectors seen |
| 2 | **the fix**: vp90-2-22-svc_1280x720_3.ivf | Success |
| 3 | no regression of f8be54bac: 24 x vp90-2-21-resize_inter_* + 05-resize + 18-resize | 26/26 Success |
| 4 | regression subset (u2) | all 25 Success; the failing names are listed |
| 5 | dmesg | no `timed out`, IOMMU fault, Oops, WARNING |
| 6 | fluster | no per-vector timeout (90 s) |

If CHECK 2 fails with KO (wrong output) while 3 and 4 pass, the hardware decoded the frame but with the wrong layout
or scaling: copy the `v4l2slvp9dec`/`v4l2codecs` lines of `out/u1.log` for that vector. If it fails with ER, copy the
`gst-launch` error lines of `out/u1.log` for that vector and every cedrus line of `dmesg-u1.txt`
("larger than its", "reference frame not found", "Failed to setup").

The summary must list: the kernel (`kernel.txt`, both lines, and `fix.txt`), start/end times, the 7 CHECK lines, the
VERDICT line, the group table, `out/env.txt` lines containing `MISSING` (if any), and every line of `dmesg-u*.txt`
that contains cedrus, timed out, fault, Oops or WARNING, copied exactly. If the script exited 2, the summary lists
`logs/upsize/BLOCKED` verbatim (and the last 10 lines of runner.log if it exists) instead of the checks.
