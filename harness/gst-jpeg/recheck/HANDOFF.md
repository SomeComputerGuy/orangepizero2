# Runner package: v4l2sljpegdec recheck of the job 05/06 failures (DEV, ~8-10 min incl. two reboots)

Command (host, as aruni, from /home/aruni/orangepizero2):

    harness/gst-jpeg/recheck/run-job.sh

It takes the board lock (owner `gst-jpeg-recheck-<time>`), installs the NEWEST CUMULATIVE KERNEL
(last line of `kernel-check/cumulative-kernels.txt`, c15 or later; installed with the vdec fallback
armed, Image md5 checked after the reboot), ships `build/gst-jpeg/bundle-recheck` (dev plugins with
patches/gstreamer 0101-0107, vectors, jpegtest) to the board, runs it (nothing installed: plugins load
from a private GST_PLUGIN_SYSTEM_PATH/GST_REGISTRY under /root/gstjpeg-recheck, removed afterwards),
copies the results to `build/gst-jpeg/results-recheck/`, restores the stock image kernel (reboot),
releases the lock and runs `compare.py` on the host. Every gst-launch is under `timeout 60`; the last
case (`norank`) is expected to run into that timeout; the board part is capped at 900 s. Wait with one
background command. Exit 2 with `results-recheck/BLOCKED` = blocked (report its text verbatim, no checks).

What it tests: on a kernel that enumerates frame sizes, (a) a 4096x4096 JPEG is refused by the
v4l2sljpegdec caps and decoded by jpegdec (job 05 ran it on a kernel without ENUM_FRAMESIZES because
its KSIZES probe matched the src template; fixed), (b) pictures smaller than one macroblock (1x1, 8x8,
15x15) still go to the hardware (patch 0107: the sink caps lower bound is 1, not the 16x16 coded
minimum), (c) odd-size 4:2:2 and 4:4:4 stills and the odd-size clip decode to the engine-exact
reference (job 06's c-ref/psnr failures were the reference model of compare.py; fixed), (d) no case
writes to the kernel log, and the `norank` run (stateful v4l2jpegdec, hangs) is recorded with a
GStreamer debug log for the work-list analysis.

Checks (results in `build/gst-jpeg/results-recheck/`):

| # | check | PASS if |
|---|---|---|
| 0 | not blocked | no file `BLOCKED`; `kernel.txt` first line starts with `cumulative c` (c15 or later) |
| 1 | `compare.txt` `INSPECT:` line | tag `PASS` and the line contains `KSIZES=1` and `sink-range ok` (if it says `KSIZES=0`: "kernel without ENUM_FRAMESIZES", the job did not run on the cumulative kernel: BLOCKED, not FAIL) |
| 2 | `compare.txt` cases | every case line (`NAME [still|size|clip ...]: ...`) has the tag `PASS`; the `SUMMARY:` line has `0 fail, 0 skipped` |
| 3 | size | `z4096x4096 [size 420]: PASS` (refused by the caps, decoded by jpegdec) |
| 4 | hardware path | `s420`, `z17x33-411`, `z33x17-422`, `z15x15-444`, `z1x1`, `z8x8` lines are `PASS` (hw == driver, vs reference max|d| <= 3, autoplug picks v4l2sljpegdec) |
| 5 | clip | `mj-z33x17 [clip 33x17*30]: PASS` |
| 6 | no hangs | no line in `out/results.txt` other than the `norank` line has `rc=124` or `rc=137` |
| 7 | quiet driver | every `NAME dmesg +N` line in `out/results.txt` has `+0` |
| 8 | norank | `NORANK:` line in `compare.txt`: `picked=[` contains `v4l2jpegdec` (expected); report its `dmesg +N` value and the size of `out/norank.gstdebug.txt` (`ls -l`), both only recorded |

Summary must list: `kernel.txt` (all lines), the `INSPECT:` line, every `compare.txt` case line verbatim, the
`SUMMARY:`, `NORANK:` and `DMESG:` lines, the `runner.log` lines containing `restored:` and `BLOCKED` (if any), and the
paths of the copied results. Nothing else to judge: a case that is not PASS is a FAIL, copy its line (the `FAIL(...)`
reasons name the failed checks, see the header of compare.py).
