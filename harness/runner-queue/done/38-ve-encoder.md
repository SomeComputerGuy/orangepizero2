# Job 38-ve-encoder (DEV-length, ~10 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault/engine timeout) = job 37 re-queued on c33
Package: harness/research/ve-encoder/runner/ (script venc-job.sh, HANDOFF.md, checks 1-9 there).
Command: `bash harness/research/ve-encoder/runner/venc-job.sh venc`
Why again: job 37 (c32) passed r1-r4 (720p and 1080p, I and I+P, 44-54 dB, framing right) but the first 1366x768
picture (r5) faulted at 0xfff83000, as on c31. That address is the end of the first NV12 source buffer (387 pages at
the topmost 2 MiB IOVA slot): the engine reads past the end of the picture, and 1366x768 is the only size whose picture
fills its last page to the byte. Fixed by fix/sunxi-h616-venc d6d2ce09b (one more macroblock row in the source
buffer; every encoder buffer's IOVA and size in /sys/kernel/debug/cedrus/encoder-buffers and in dmesg after an encode
timeout), merged into test-cumulative 342cfa31c = c33. New runs r6 720x480 and r7 854x480 (I+P, GOP 5), new check 9
(buffers_file 4, source_room 1 per run). Job 37's evidence is archived in harness/research/ve-encoder/logs/job37-c32/.
Kernel: the newest cumulative kernel, which must contain d6d2ce09b (c33 or later; the script blocks (exit 2) on an older
one or when no encoder device is logged). The board must start on the stock image kernel. HTTP server 10.56.0.1:8643 up.
Host: /usr/local/bin/ffmpeg, python3, gawk (the script generates the two new clips itself, ~11 MB).
Tool: harness/research/ve-encoder/tools/out/h264enc-test (unchanged), shipped if the board copy differs.
Exit 3 (OOPS): results.txt is still complete; apply and report checks 1-9 anyway (HANDOFF.md "Fail fast"), with the
faulting run's buffers.txt and the `encoder buffers:` dmesg lines verbatim (check 9).
Results: harness/research/ve-encoder/logs/runner-venc/. Summary per HANDOFF.md "Checks" into
harness/runner-queue/done/38-ve-encoder.summary.md.
Submitted by the ve-encoder job-37 fix agent, 2026-11-06.
