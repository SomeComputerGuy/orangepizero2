# 23-avs2-queue2 (avs2q rerun): ALL PASS
Start 2026-11-06 01:39:23 UTC, end 01:46:07 UTC. Kernel #23 SMP PREEMPT Fri Nov  6 00:46:05 UTC 2026.
Checks: ROUND-DONE=1, download failed 0, binary sha256 01a23cd93c89daf9 avs2-decoder 1, holdback starved n=1 and n=1 (<=3), lowdelay r1 X=151 (data), cctv4k md5 PASS, md5 PASS count 18, FAIL count 0, timeouts 0 first/last and new-timeouts 0 everywhere, dmesg-1.txt no 'timed out', no Page fault: all PASS.
```
kernel 7.3.1 #23 SMP PREEMPT Fri Nov  6 00:46:05 UTC 2026 clk 624000000 timeouts 0
[binary] sha256 01a23cd93c89daf9 avs2-decoder 1
[gaps cctv4k-10bit holdback r1] rc=0 jobs=292 wall=5.61s span=4.85s | setup 0.15ms ve 16.27ms (max 17.18) | gap ready n=290 avg 0.080ms (wq 0.078ms) | gap starved n=1 avg 28.97ms max 28.97ms fps: ve-only 61.5, ve+setup 60.9, pipeline(span) 60.2, wall 52.1 | idle share: setup 0.9% ready-gap 0.5% starved 0.6%  rtime=5.019s
[gaps cctv4k-10bit holdback r2] rc=0 jobs=292 wall=5.58s span=4.82s | setup 0.15ms ve 16.26ms (max 17.72) | gap ready n=290 avg 0.078ms (wq 0.077ms) | gap starved n=1 avg 11.54ms max 11.54ms fps: ve-only 61.5, ve+setup 61.0, pipeline(span) 60.5, wall 52.4 | idle share: setup 0.9% ready-gap 0.5% starved 0.2%  rtime=4.999s
[gaps cctv4k-10bit lowdelay r1] rc=0 jobs=292 wall=5.78s span=5.03s | setup 0.15ms ve 16.24ms (max 16.65) | gap ready n=141 avg 0.091ms (wq 0.087ms) | gap starved n=151 avg 0.67ms max 4.72ms fps: ve-only 61.6, ve+setup 61.0, pipeline(span) 58.0, wall 50.5 | idle share: setup 0.9% ready-gap 0.3% starved 2.0%  rtime=5.209s
timeouts 0
--- dmesg-1.txt lines
12
```
Results: harness/research/vdec-perf/logs/runner-avs2q/. Stock kernel restored.
