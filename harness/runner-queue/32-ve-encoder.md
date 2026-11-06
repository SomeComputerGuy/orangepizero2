# Job 27-ve-encoder (DEV-length, ~10 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault/engine timeout)
Package: harness/research/ve-encoder/runner/ (script venc-job.sh, HANDOFF.md, checks 1-7 there).
Command: `bash harness/research/ve-encoder/runner/venc-job.sh venc`
Kernel: the newest cumulative kernel, which must contain fix/sunxi-h616-venc at f35cdf390 (wt-venc; the stateless H.264
encode uAPI core 0801-0809 + the cedrus H.264 encoder "cedrus-enc" on the H616 VE). Coordinator: merge f35cdf390 into
test-cumulative and build/serve it first (c24 or later; c23 is refused). The script blocks (exit 2) if the installed
kernel lacks it or logs no encoder device. The board must start on the stock image kernel. HTTP server 10.56.0.1:8643 up.
Host: /usr/local/bin/ffmpeg generates the raw NV12 test clips (first run, ~80 MB) and decodes/compares the streams.
Tool: harness/research/ve-encoder/tools/out/h264enc-test (built 2026-11-06 by tools/build.sh), shipped if the board copy differs.
Results: harness/research/ve-encoder/logs/runner-venc/ (results.txt has the values for the checks; the .h264 streams are kept).
Submitted by the ve-encoder agent, 2026-11-06.
