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
run (`norank16`) is expected to run into that timeout; the board part is capped at 900 s. Wait with one
background command. Exit 2 with `results-recheck/BLOCKED` = blocked (report its text verbatim, no checks).

What it tests: on a kernel that enumerates frame sizes, (a) a 4096x4096 JPEG is refused by the
v4l2sljpegdec caps and decoded by jpegdec (job 05 ran it on a kernel without ENUM_FRAMESIZES because
its KSIZES probe matched the src template; fixed), (b) pictures smaller than one macroblock (1x1, 8x8,
15x15) still go to the hardware (patch 0107: the sink caps lower bound is 1, not the 16x16 coded
minimum), (c) odd-size 4:2:2 and 4:4:4 stills and the odd-size clip decode to the engine-exact
reference (job 06's c-ref/psnr failures were the reference model of compare.py; fixed), (d) no case
writes to the kernel log, (e) without the rank override the stateful v4l2jpegdec (gst-plugins-good) declines
an odd-size picture on a kernel that enumerates frame sizes (its probed caps carry the driver's 16-pixel
step, so 1921x1081 gives EMPTY sink caps) and decodebin decodes it with v4l2sljpegdec (`norank`), and (f) a
16-aligned picture (1920x1088) does go to the stateful decoder, whose hang on this stateless device is the
work-list item: recorded with a GStreamer debug log (`norank16`), not judged.

Job 11 (2026-11-05, c17) failed checks 1 and 8 on wrong expectations, both fixed 2026-11-06 (RESULTS.md
"Job 11 analysed"): gst-inspect's `Name` line is the plugin name (v4l2codecs), never the element's, so the
element is now proven by `gst-inspect-1.0 --exists` (`EXISTS=0`); and `norank` expected the stateful decoder
to be picked, which only holds on a kernel without ENUM_FRAMESIZES (job 11's GST_DEBUG log shows
`<v4l2jpegdec0> Returning sink caps EMPTY`, then v4l2sljpegdec decoded, rc=0, dmesg +0).

Checks (results in `build/gst-jpeg/results-recheck/`):

| # | check | PASS if |
|---|---|---|
| 0 | not blocked | no file `BLOCKED`; `kernel.txt` first line starts with `cumulative c` (c15 or later) |
| 1 | `compare.txt` `INSPECT:` line | tag `PASS` (= `EXISTS=0`, Long-name, rank 257, sink range) and the line contains `KSIZES=1` and `sink-range ok` (if it says `KSIZES=0`: "kernel without ENUM_FRAMESIZES", the job did not run on the cumulative kernel: BLOCKED, not FAIL) |
| 2 | `compare.txt` cases | every case line (`NAME [still|size|clip ...]: ...`) has the tag `PASS`; the `SUMMARY:` line has `0 fail, 0 skipped` |
| 3 | size | `z4096x4096 [size 420]: PASS` (refused by the caps, decoded by jpegdec) |
| 4 | hardware path | `s420`, `z17x33-411`, `z33x17-422`, `z15x15-444`, `z1x1`, `z8x8` lines are `PASS` (hw == driver, vs reference max|d| <= 3, autoplug picks v4l2sljpegdec) |
| 5 | clip | `mj-z33x17 [clip 33x17*30]: PASS` |
| 6 | no hangs | no line in `out/results.txt` other than the `norank` line has `rc=124` or `rc=137` |
| 7 | quiet driver | every `NAME dmesg +N` line in `out/results.txt` has `+0` |
| 8 | norank | `NORANK:` line in `compare.txt` has the tag `PASS` (= rc=0, picked contains v4l2sljpegdec, `dmesg +0`, `stateful-empty-caps` >= 1: the stateful v4l2jpegdec was tried and declined 1921x1081) |
| 9 | norank16 | `NORANK16:` line present (`norank16 rc=... picked=[...] dmesg +N stateful-empty-caps=0`); report it verbatim with the size of `out/norank16.gstdebug.txt` (`ls -l`); recorded only, rc=124 and `dmesg +N` > 0 are expected there |

Summary must list: `kernel.txt` (all lines), the `INSPECT:` line, every `compare.txt` case line verbatim, the
`SUMMARY:`, `NORANK:`, `NORANK16:` and `DMESG:` lines, the `runner.log` lines containing `restored:` and `BLOCKED` (if any), and the
paths of the copied results. Nothing else to judge: a case that is not PASS is a FAIL, copy its line (the `FAIL(...)`
reasons name the failed checks, see the header of compare.py).
