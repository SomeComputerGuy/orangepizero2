# Job 39-ve-encoder (DEV-length, ~10 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault/engine timeout) = job 38 re-queued on c33 (package fixes only)
Package: harness/research/ve-encoder/runner/ (script venc-job.sh, HANDOFF.md, checks 1-9 there).
Command: `bash harness/research/ve-encoder/runner/venc-job.sh venc`
Why again: job 38 (c33) passed r1-r6 with no fault. Its two failures were package bugs, now fixed: r7 854x480 never ran
because its clip was not shipped (shipping loop lost its input), and r5's hardware-decode md5 compared GStreamer's
padded NV12 dump (stride 1368 for 1366 wide) with ffmpeg's tight output (now only the visible pixels are hashed). The
debugfs buffer list is now per run (`buffers_format`, check 9). All seven runs r1-r7 run again; r5 and r7 are the ones
that must turn PASS. Job 38's evidence is archived in harness/research/ve-encoder/logs/job38-c33/ (logs/runner-venc/ is
fresh: no state file, so the chunk runs).
Kernel: the newest cumulative kernel, which must contain d6d2ce09b (c33 or later; the script blocks (exit 2) on an older
one or when no encoder device is logged). The board must start on the stock image kernel. HTTP server 10.56.0.1:8643 up.
Host: /usr/local/bin/ffmpeg, python3, gawk. Board: python3 (used for the hwdec crop; present, the vdec jobs use it).
Shipping: runner.log must show `clips on the board: 5 of 5 current` before the kernel install (else BLOCKED, exit 2).
Tool: harness/research/ve-encoder/tools/out/h264enc-test (unchanged), shipped if the board copy differs.
Checks: HANDOFF.md "Checks" 1-9, for every run r1-r7; check 6 also: report the `raw` and `crop` fields of the r5 and r7
HWDEC lines (expected in HANDOFF.md check 6); check 9: `buffers_format 1` for every run.
Exit 3 (OOPS): results.txt is still complete; apply and report checks 1-9 anyway (HANDOFF.md "Fail fast"), with the
faulting run's buffers.txt and the `encoder buffers:` dmesg lines verbatim (check 9).
Results: harness/research/ve-encoder/logs/runner-venc/. Summary per HANDOFF.md "Checks" into
harness/runner-queue/done/39-ve-encoder.summary.md.
Submitted by the ve-encoder job-38 fix agent, 2026-11-06.
