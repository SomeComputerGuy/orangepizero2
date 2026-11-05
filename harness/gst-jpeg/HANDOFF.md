# Runner package: v4l2sljpegdec board test

Command (host, as aruni, from /home/aruni/orangepizero2):

    harness/gst-jpeg/run-job.sh

It takes the board lock as `gst-jpeg-run`, ships `build/gst-jpeg/bundle` (dev plugins, vectors, jpegtest),
runs it on the booted kernel (no kernel change, nothing installed: plugins are loaded from a private
GST_PLUGIN_SYSTEM_PATH/GST_REGISTRY under /root/gstjpeg, removed afterwards), copies the results to
`build/gst-jpeg/results/` and releases the lock. Every gst-launch is under `timeout 60`, so the whole run is
at most ~45 min (the script caps it at 2700 s). Wait with one background command.

Checks (results in `build/gst-jpeg/results/`; `out/results.txt` lines are `NAME TAG rc=N md5 ... picked=[...]`):

| # | check | PASS if |
|---|---|---|
| 1 | `out/inspect.txt` | contains `v4l2sljpegdec` and `Rank` `primary + 1` (257) |
| 2 | hw decode | for s420 s422 s444 s411 dri7 nodht opt420 z16x16 z2049x64 z4096x2304 mj420: line `NAME hw rc=0` and size > 0 |
| 3 | driver equality | `compare.txt`: s420 s422 s444 s411 dri7 nodht opt420 show `hw==drv EXACT` |
| 4 | quality | `compare.txt`: for s420 dri7 nodht opt420 mj420 the Y PSNR vs jpegdec >= 48 dB and Y max\|d\| <= 2 |
| 5 | autoplug hw | `db`, `pb`, `db3` lines of s420 s422 s444 s411 and `db` `pb` `pb3` of mj420: rc=0 and picked contains `v4l2sljpegdec` |
| 6 | autoplug fallback | `db`, `pb`, `db3` of grey prog s440 mjpeg422 and `db` `pb` `pb3` of mj422 mj444: rc=0 and picked contains `jpegdec` but not `v4l2sljpegdec` |
| 7 | no hangs | no line in `out/results.txt` has rc=124 or rc=137 |
| 8 | errors are clean | crtable and trunc `hw` lines: rc is not 124/137 (an error rc is fine) |
| 9 | resolution change | mjmix `hw` rc=0 |
| 10 | override still needed | `norank` line: picked contains `v4l2jpegdec` (expected; documents why the v4l2jpegdec MARGINAL override stays) |
| 11 | perf | report the two `perf mj1080` ms values (no threshold) |

Also copy any `cedrus` / `Oops` / `WARNING` lines from `out/dmesg.txt` verbatim into the summary.
