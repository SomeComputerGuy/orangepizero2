# Job 37-ve-encoder (DEV-length, ~10 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault/engine timeout) = job 35 re-queued on c32
Package: harness/research/ve-encoder/runner/ (script venc-job.sh, HANDOFF.md, checks 1-8 there).
Command: `bash harness/research/ve-encoder/runner/venc-job.sh venc`
Why again: job 35 (c31) encoded r1-r4 (rc 0) but no stream decoded (the bit writer dropped every 32-bit put: no start
codes, no SPS VUI timing fields; with those put back on the host all four decode at 44-54 dB PSNR-Y), and the first
1366x768 picture (r5) faulted at 0xfff83000 (the end of the 12 KiB macroblock info buffer). Fixed by fix/sunxi-h616-venc
4727ed447 (puts of at most 24 bits, picture-sized MB info buffer, SPS/PPS nal_ref_idc 3), merged into test-cumulative
91b91f9dc = c32. The decoder-node compliance fail `v4l2-test-codecs.cpp(161)` is a known stock-tool limitation and no
longer counts (check 2). New check 8 (stream framing) and per-run dmesg values.
Kernel: the newest cumulative kernel, which must contain 4727ed447 (c32 or later; the script blocks (exit 2) on an older
one or when no encoder device is logged). The board must start on the stock image kernel. HTTP server 10.56.0.1:8643 up.
Host: /usr/local/bin/ffmpeg, python3 (clips already in harness/research/ve-encoder/runner/clips/).
Tool: harness/research/ve-encoder/tools/out/h264enc-test (unchanged), shipped if the board copy differs.
Exit 3 (OOPS): results.txt is still complete; apply and report checks 1-8 anyway (HANDOFF.md "Fail fast").
Results: harness/research/ve-encoder/logs/runner-venc/ (job 35's are archived in logs/job35-c31/). Summary per HANDOFF.md
"Checks" into harness/runner-queue/done/37-ve-encoder.summary.md.
Submitted by the ve-encoder job-35 fix agent, 2026-11-06.
