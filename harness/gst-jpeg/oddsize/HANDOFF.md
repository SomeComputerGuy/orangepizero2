# Runner package: v4l2sljpegdec odd picture sizes and resolution changes (DEV, ~6-8 min)

Command (host, as aruni, from /home/aruni/orangepizero2):

    harness/gst-jpeg/oddsize/run-job.sh

It takes the board lock as `gst-jpeg-oddsize`, ships `build/gst-jpeg/bundle-oddsize` (dev plugins with
patches/gstreamer 0101-0106, vectors, jpegtest) to the board, runs it on the booted kernel (nothing
installed: plugins load from a private GST_PLUGIN_SYSTEM_PATH/GST_REGISTRY under /root/gstjpeg-oddsize,
removed afterwards), copies the results to `build/gst-jpeg/results-oddsize/`, releases the lock and runs
`compare.py` on the host. Every gst-launch is under `timeout 60`; the last case (`norank`) is expected to
run into that timeout; the whole run is capped at 1800 s. Wait with one background command. Kernel: any.
On a kernel with `fix/sunxi-cedrus-jpeg-quiet-refusals` (test-cumulative c14 or later) the `NORANK:` line
should show few or no kernel log lines; on an older kernel it shows many. Either is recorded, not judged.

What it tests: JPEGs of odd and sub-MCU sizes (17x33, 33x17, 15x15, 1x1, 8x8, 1921x1081, 2049x64,
4095x2303) in 4:2:0, 4:2:2, 4:4:4 and 4:1:1 decode to the right pixels on the hardware path (direct and
through decodebin/playbin), equal to the driver's own output and to ffmpeg; MJPEG clips whose picture size
changes (640x480 -> 320x240, 320x240 -> 640x480) and an odd-size clip (33x17) come out with every frame
at its own size through both the hardware and the jpegdec path, and jpegparse's caps follow the image
size; no case writes to the kernel log.

Checks (results in `build/gst-jpeg/results-oddsize/`):

| # | check | PASS if |
|---|---|---|
| 1 | `out/inspect.txt` | contains `v4l2sljpegdec` and `Rank` `primary + 1` |
| 2 | `compare.txt` cases | every case line (`NAME [still|clip ...]: ...`) has the tag `PASS`; the `SUMMARY:` line has `0 fail` |
| 3 | stills | the nine `[still ...]` lines are `PASS` (hw == driver, vs ffmpeg, autoplug, caps, no dmesg) |
| 4 | clips | the `mjmix`, `mjmix-up` and `mj-z33x17` lines are `PASS` (hw and jpegdec output every frame at its size, caps sizes as the file) |
| 5 | no hangs | no line in `out/results.txt` other than the `norank` line has `rc=124` or `rc=137` |
| 6 | quiet driver | every `NAME dmesg +N` line in `out/results.txt` has `+0` |
| 7 | norank | `NORANK:` line in `compare.txt`: `picked=[` contains `v4l2jpegdec` (expected; documents why the MARGINAL override stays); report its `dmesg +N` value |

Summary must list: kernel (`kernel.txt`), every `compare.txt` case line verbatim, the `SUMMARY:`, `NORANK:` and
`DMESG:` lines, and the paths of the copied results. Nothing else to judge: a case that is not PASS is a FAIL,
copy its line (the `FAIL(...)` reasons name the failed checks, see the header of compare.py).
