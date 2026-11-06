# Runner package: MPEG-1 through GStreamer v4l2slmpeg2dec on MG1S (job gst-mpeg1, DEV)

Command (host, as aruni, from /home/aruni/orangepizero2; DEV run, about 15-20 min of board time incl. two reboots):

    bash harness/gst-mpeg1/run-job.sh

What it does (results under `build/gst-mpeg1/results/`):

1. Refuses to start (exit 2, `results/BLOCKED`) unless the **newest cumulative kernel** (last line of
   kernel-check/cumulative-kernels.txt) contains armbian-build commit 8140b4eeb241ea13b872edbe93dadac618de2130
   (`fix/sunxi-cedrus-mpeg1-mg1s`: MG1S uAPI + cedrus). Same precondition as job 11-mpeg1-mg1s.
2. Takes the board lock (owner `gst-mpeg1-<epoch>`), starts the HTTP server 10.56.0.1:8643 if needed, ships
   `build/gst-mpeg1/bundle` (dev `libgstv4l2codecs.so` + patched `libgstcodecs-1.0.so.0` built from patches/gstreamer
   0001-0017, 0101-0107, 0201; the 8 test streams; board-test.sh) to `/root/gstmpeg1`. Nothing is installed system-wide:
   the plugins are loaded from a private GST_PLUGIN_SYSTEM_PATH/GST_REGISTRY, the library with LD_LIBRARY_PATH.
3. Phase `stock` on the **stock image kernel** (the board must be on vmlinuz-7.3.1-edge-sunxi64 at start): coded formats
   of the cedrus node, `gst-inspect` of v4l2slmpeg2dec, ccm1/tcela-15/mcp10ccett explicit hw pipelines, decodebin for
   ccm1/tcela-18/tcela-15, playbin3 for ccm1 (`out-stock/`).
4. Installs the newest cumulative kernel with the vdec fallback armed (harness/research/vdec-perf/install-kernel.sh),
   reboots, verifies the Image md5, records `kernel.txt`, runs phase `test`: the same plus the MPEG-1 hw pipelines for
   ccm1, tcela-18 (31 D-pictures), MEI.stream16.long, MEI.stream16v2, tcela-16, tcela-19 (`out-test/`). Every gst run is
   under `timeout 120`; each phase is capped at 1200 s. Each run logs rc, md5 and size of the I420 dump, the cedrus IRQ
   delta and (autoplug runs) the decoder decodebin/playbin3 picked.
5. Copies `out-stock/` and `out-test/` (incl. the I420 dumps, ~70 MB) to the host, restores the stock kernel, releases the
   lock, then runs `compare.sh` (host ffmpeg software references with -idct simple/int/faani and the simple~int envelope,
   tcela-18 against the exact DC reference legacy-dec/m1-dpic.py -> `compare.tsv`) and `check-results.sh` -> `check.txt`.

Exit codes: 0 = ran (judge with the checks below); 2 = blocked (report `results/BLOCKED` and the last 10 lines of
`results/runner.log`); 1 = setup error (bundle missing: `harness/gst-mpeg1/make-bundle.sh`, or kernel package missing).
Wait for the script with one background command; do not re-read logs in between.

## Checks (mechanical)

    bash harness/gst-mpeg1/check-results.sh build/gst-mpeg1/results

(already run by the script; `results/check.txt`). Copy its `CHECK n ...: PASS|FAIL|SKIP (...)` lines and the `VERDICT:`
line into the summary verbatim. The checks:

| # | check | PASS if |
|---|---|---|
| 0 | kernels | `kernel-stock.txt` is `stock 7.3.1 ...`, `kernel.txt` names a cumulative kernel (`cumulative cN ...`) |
| 1 | **software fallback without MG1S** | stock phase, no MG1S in `out-stock/fmts.txt`: `inspect.txt` has `MPEG-1 not supported` and no `mpegversion: 1`; `ccm1 db` line rc=0, picked a software decoder (avdec_mpeg2video or mpeg2dec, not v4l2slmpeg2dec), irqs=0. SKIP if the stock kernel already enumerates MG1S. **NOT-TESTABLE** if `inspect.txt` has no `SWDEC=` line: the board image has no software MPEG-1 decoder (job 12: "Missing element: MPEG-1 Video decoder"; the image fix adds gstreamer1.0-libav to every variant, userpatches/config-opiz2-printserver.conf, and needs an image rebuild + reflash). Report the line as printed; it is neither PASS nor FAIL |
| 2 | **MG1S caps on the test kernel** | `out-test/fmts.txt` one MG1S line; `inspect.txt` has `MPEG-1 supported` and `mpegversion: 1` |
| 3 | **ccm1 hw** | `ccm1 hw` rc=0 irqs=129; `compare.tsv` ccm1 `simple: frames=129 exact=129` |
| 4 | **tcela-18 D-pictures in hardware** | `tcela-18 hw` rc=0 irqs=31; `compare.tsv` tcela-18 `frames=31 exact=31` vs the DC reference; `tcela-18.hw.log` has `D-pictures are decoded by the device` |
| 5 | IDCT envelope | MEI.stream16.long (61), MEI.stream16v2 (4), tcela-16 (31), tcela-19 (31): rc=0, all frames, irqs == frames, HW max abs diff to the closest software IDCT <= max(2, simple~int envelope) |
| 6 | MPEG-2 regression | test: `tcela-15 hw` rc=0 irqs=61 `frames=61 exact=61`, `mcp10ccett hw` rc=0 irqs=4 `frames=4 exact=4`; tcela-15 hw md5 equal on stock and test kernel |
| 7 | autoplug | test: `ccm1 db`, `tcela-18 db`, `tcela-15 db`, `ccm1 pb3`: rc=0, picked contains v4l2slmpeg2dec, md5 equal to the stream's `hw` line |
| 8 | no hangs | no rc=124 or rc=137 in either `results.txt` |
| 9 | dmesg | no `timed out`, `fault` (as a word; "default" in the boot lines does not count, job 12's FAIL), Oops, WARNING, `bug:` in `out-*/dmesg.txt` |

`VERDICT:` is `PASS` (all PASS/SKIP), `INCOMPLETE (...)` (no FAIL, but check 1 NOT-TESTABLE on this image) or `FAIL`.

Reference (FFmpeg path, job 11 / impl-legacy-decode.md 6.1): ccm1 129/129 bit-exact, tcela-18 31/31 bit-exact,
MEI/tcela-16/19 max 2 within envelope 2-3. OPi5 (Hantro): GStreamer MPEG-1 md5s bit-identical to the FFmpeg HW md5s.

The summary must list: `kernel-stock.txt` and both lines of `kernel.txt`, start/end times (`runner.log`), the 10 CHECK
lines and the VERDICT line, both `results.txt` files verbatim, the `MPEG-1`/`mpegversion` lines of both `inspect.txt`,
`compare.tsv` cut to 200 columns, the first `D-pictures are` line of `out-test/tcela-18.hw.log`, and every line of
`out-*/dmesg.txt` containing timed out, fault, Oops, WARNING or bug, copied exactly. If the script exited 2:
`results/BLOCKED` verbatim and the last 10 lines of runner.log instead of the checks.
