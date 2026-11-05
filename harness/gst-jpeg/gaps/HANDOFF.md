# Runner package: v4l2sljpegdec caps gaps (DEV, ~5-10 min)

Command (host, as aruni, from /home/aruni/orangepizero2):

    harness/gst-jpeg/gaps/run-job.sh

It takes the board lock as `gst-jpeg-gaps`, ships `build/gst-jpeg/bundle-gaps` (dev plugins with
patches/gstreamer 0101-0105, vectors, jpegtest) to the board, runs it on the booted kernel (nothing
installed: plugins load from a private GST_PLUGIN_SYSTEM_PATH/GST_REGISTRY under /root/gstjpeg-gaps,
removed afterwards), copies the results to `build/gst-jpeg/results-gaps/`, releases the lock and
runs `compare.py` on the host. Every gst-launch is under `timeout 60`; the whole run is capped at
1800 s. Wait with one background command. Kernel: any; the `z4096x4096` case needs a kernel with
`fix/sunxi-cedrus-enum-framesizes` (test-cumulative c11 or later) and is SKIPPED on an older one.

What it tests: JPEGs the hardware cannot decode (Cb/Cr quantisation or Huffman tables differ,
several scans, 4096x4096) must be refused by the caps so decodebin/playbin plug jpegdec, and JPEGs it
can decode (Cr pointing at a second table with the same content) must still go to v4l2sljpegdec.

Checks (results in `build/gst-jpeg/results-gaps/`):

| # | check | PASS if |
|---|---|---|
| 1 | `out/inspect.txt` | contains `v4l2sljpegdec`, a line with `scans:` and `1`, and a line with `component-tables:` containing `shared` and `luma-chroma` |
| 2 | `compare.txt` cases | every case line (`NAME [expect]: ...`) ends its tag with `PASS` or is `SKIPPED`; the `SUMMARY:` line has `0 fail` |
| 3 | hardware still taken | the `s420`, `crtq2` and `mj-crtq2` lines are `PASS` (the `hw` cases; their line reports PSNR >= 48 dB) |
| 4 | fallback | the `crtable`, `crhuff`, `noninter`, `noninter2`, `dri7-noninter`, `mj-crhuff`, `mj-noninter` lines are `PASS` |
| 5 | size | `z4096x4096` is `PASS`, or `SKIPPED` when `out/inspect.txt` has `KSIZES=0` (kernel without ENUM_FRAMESIZES: report "not applicable on this kernel", not FAIL) |
| 6 | no hangs | no line in `out/results.txt` has `rc=124` or `rc=137` |
| 7 | driver untouched by refused images | `compare.txt` last block says `DMESG: clean` (no `cedrus`, `Oops`, `WARNING` lines during the run) |

Summary must list: kernel (`kernel.txt`), `KSIZES` value, every `compare.txt` case line verbatim, the
`SUMMARY:` and `DMESG:` lines, and the paths of the copied results. Nothing else to judge: a case
that is not PASS/SKIPPED is a FAIL, copy its line.
