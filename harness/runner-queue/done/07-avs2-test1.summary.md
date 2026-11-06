# 07-avs2-test1 (t1fix): ALL PASS
Start 2026-11-05 22:58:45 UTC, end 23:07:06 UTC. Kernel c17 (Image md5 22330a4caccc513b757e743934c2700f), uname -v: #18 SMP PREEMPT Thu Nov  5 22:07:30 UTC 2026.
Checks: ROUND-DONE=1 PASS; frames 2096 differing 0 PASS; five streams PASS; timeouts 0 first/last and new-timeouts 0 PASS; files/t1.got 2096 lines PASS.
```
kernel 7.3.1 #18 SMP PREEMPT Thu Nov  5 22:07:30 UTC 2026 timeouts 0
[seq] sequence: profile 0x20 level 0x4a 854x480 progressive 8-bit (enc 8) lcu 32 rcs 8 reorder 3 wq 0 bg 0
[differing frames] 
[count] frames 2096 differing 0
[test1-perframe] decode errors 0 timeouts 0
[test1.avs2] PASS 95caa0eea2d5b1681ff1ce53b2515837 rc=0 37.8s new-timeouts 0 errors 0 | 2096 pictures decoded, 2096 output, md5 95caa0eea2d5b1681ff1ce53b2515837
[main-2160p-ra.avs2] PASS 3a3d5d7eb9a6f548042e160d9e461388 rc=0 7.6s new-timeouts 0 errors 0 | 20 pictures decoded, 20 output, md5 3a3d5d7eb9a6f548042e160d9e461388
[cctv4k-10bit.avs2] PASS be9985dea38abffc850d73024165c990 rc=0 221.8s new-timeouts 0 errors 0 | 292 pictures decoded, 292 output, md5 be9985dea38abffc850d73024165c990
[main-1080p-ra.avs2] PASS 13dbb783682495dd423b05f6decee8b2 rc=0 2.8s new-timeouts 0 errors 0 | 30 pictures decoded, 30 output, md5 13dbb783682495dd423b05f6decee8b2
[BQSquare_416x240_60_ra.avs2] PASS cf9babd3440b696c998179071a608b85 rc=0 0.5s new-timeouts 0 errors 0 | 100 pictures decoded, 100 output, md5 cf9babd3440b696c998179071a608b85
timeouts 0
```
dmesg-1.txt: boot lines only (no timed out/fault/error); exact: ../research/vdec-perf/logs/runner-t1fix/dmesg-1.txt
Results: harness/research/vdec-perf/logs/runner-t1fix/. Board restored to stock kernel, lock released.
