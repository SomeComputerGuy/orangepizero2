# 12-avs2-queue (avs2q): FAIL (md5 count 10 PASS / 4 FAIL, 4 'download failed' lines)
Start 2026-11-05 23:11:41 UTC, end 23:17:02 UTC. Kernel (uname -v): #18 SMP PREEMPT Thu Nov  5 22:07:30 UTC 2026 (c17).
ROUND-DONE=1 PASS; 'download failed' lines: 4 -> FAIL; [binary] sha256 01a23cd93c89daf9 avs2-decoder 1 PASS; cctv4k md5 PASS; gaps holdback starved n=1 and n=1 (<=3) PASS; lowdelay r1 X=152 (data); md5 PASS count 10 (need 18) FAIL; md5 FAIL count 4 FAIL; timeouts first/last 0, all shown new-timeouts 0 PASS; dmesg-1.txt no 'timed out' PASS, no Page fault.
```
kernel 7.3.1 #18 SMP PREEMPT Thu Nov  5 22:07:30 UTC 2026 clk 624000000 timeouts 0
[binary] sha256 01a23cd93c89daf9 avs2-decoder 1
[gaps cctv4k-10bit holdback r1] rc=0 jobs=292 wall=5.62s span=4.86s | setup 0.17ms ve 16.27ms (max 17.65) | gap ready n=290 avg 0.090ms (wq 0.086ms) | gap starved n=1 avg 32.95ms max 32.95ms fps: ve-only 61.5, ve+setup 60.8, pipeline(span) 60.1, wall 51.9 | idle share: setup 1.0% ready-gap 0.5% star
[gaps cctv4k-10bit holdback r2] rc=0 jobs=292 wall=5.58s span=4.82s | setup 0.15ms ve 16.25ms (max 17.61) | gap ready n=290 avg 0.077ms (wq 0.076ms) | gap starved n=1 avg 11.76ms max 11.76ms fps: ve-only 61.5, ve+setup 61.0, pipeline(span) 60.5, wall 52.3 | idle share: setup 0.9% ready-gap 0.5% star
[gaps cctv4k-10bit lowdelay r1] rc=0 jobs=292 wall=5.75s span=5.05s | setup 0.14ms ve 16.36ms (max 17.68) | gap ready n=140 avg 0.193ms (wq 0.137ms) | gap starved n=152 avg 0.44ms max 14.29ms fps: ve-only 61.1, ve+setup 60.6, pipeline(span) 57.9, wall 50.8 | idle share: setup 0.8% ready-gap 0.5% sta
[md5 cctv4k-10bit] PASS be9985dea38abffc850d73024165c990 ref=be9985dea38abffc850d73024165c990 rc=0 new-timeouts 0 errors 0
[md5 BasketballPass_416x240_50_ai] PASS 531837190a7b825598d7b40c968f2ce4 ref=531837190a7b825598d7b40c968f2ce4 rc=0 frames=100 new-timeouts 0 errors 0
[md5 BasketballPass_416x240_50_ld] PASS b3c024f8937e84a064403c37e49e0eaa ref=b3c024f8937e84a064403c37e49e0eaa rc=0 frames=100 new-timeouts 0 errors 0
[md5 BasketballPass_416x240_50_ra] PASS 095fb60d8c2be3442c9d3b5a1c7d8231 ref=095fb60d8c2be3442c9d3b5a1c7d8231 rc=0 frames=100 new-timeouts 0 errors 0
[md5 BQMall_832x480_60_ra] PASS f81cf1cb18bb1c75a27a028bec3ea7cc ref=f81cf1cb18bb1c75a27a028bec3ea7cc rc=0 frames=150 new-timeouts 0 errors 0
[md5 BQSquare_416x240_60_ld] PASS 346e3fd17650e52fff5e1ea6482fc7f0 ref=346e3fd17650e52fff5e1ea6482fc7f0 rc=0 frames=100 new-timeouts 0 errors 0
[md5 BQSquare_416x240_60_ra] PASS cf9babd3440b696c998179071a608b85 ref=cf9babd3440b696c998179071a608b85 rc=0 frames=100 new-timeouts 0 errors 0
[md5 ParkScene_1920x1080_24_ra] PASS 5362883e842d53ce466c1ec01167ccb0 ref=5362883e842d53ce466c1ec01167ccb0 rc=0 frames=200 new-timeouts 0 errors 3
[md5 main-1080p-ldp] PASS d499bea0e77a27bd89974533094b3f71 ref=d499bea0e77a27bd89974533094b3f71 rc=0 frames=30 new-timeouts 0 errors 0
[md5 main-1080p-lf] PASS 18c32c2e84cec242608b6742c0c1cb5e ref=18c32c2e84cec242608b6742c0c1cb5e rc=0 frames=30 new-timeouts 0 errors 0
timeouts 0
[md5 cctv4k-10bit] PASS be9985dea38abffc850d73024165c990 ref=be9985dea38abffc850d73024165c990 rc=0 new-timeouts 0 errors 0
[md5 BasketballPass_416x240_50_ai] PASS 531837190a7b825598d7b40c968f2ce4 ref=531837190a7b825598d7b40c968f2ce4 rc=0 frames=100 new-timeouts 0 errors 0
[md5 BasketballPass_416x240_50_ld] PASS b3c024f8937e84a064403c37e49e0eaa ref=b3c024f8937e84a064403c37e49e0eaa rc=0 frames=100 new-timeouts 0 errors 0
[md5 BasketballPass_416x240_50_ra] PASS 095fb60d8c2be3442c9d3b5a1c7d8231 ref=095fb60d8c2be3442c9d3b5a1c7d8231 rc=0 frames=100 new-timeouts 0 errors 0
[md5 BQMall_832x480_60_ra] PASS f81cf1cb18bb1c75a27a028bec3ea7cc ref=f81cf1cb18bb1c75a27a028bec3ea7cc rc=0 frames=150 new-timeouts 0 errors 0
[md5 uare_416x240_60_ai] FAIL download failed
[md5 BQSquare_416x240_60_ld] PASS 346e3fd17650e52fff5e1ea6482fc7f0 ref=346e3fd17650e52fff5e1ea6482fc7f0 rc=0 frames=100 new-timeouts 0 errors 0
[md5 BQSquare_416x240_60_ra] PASS cf9babd3440b696c998179071a608b85 ref=cf9babd3440b696c998179071a608b85 rc=0 frames=100 new-timeouts 0 errors 0
[md5 ParkScene_1920x1080_24_ra] PASS 5362883e842d53ce466c1ec01167ccb0 ref=5362883e842d53ce466c1ec01167ccb0 rc=0 frames=200 new-timeouts 0 errors 3
[md5 -ra] FAIL download failed
[md5 main-1080p-ldp] PASS d499bea0e77a27bd89974533094b3f71 ref=d499bea0e77a27bd89974533094b3f71 rc=0 frames=30 new-timeouts 0 errors 0
[md5 n-1080p-tid] FAIL download failed
[md5 main-1080p-lf] PASS 18c32c2e84cec242608b6742c0c1cb5e ref=18c32c2e84cec242608b6742c0c1cb5e rc=0 frames=30 new-timeouts 0 errors 0
[md5 -2160p-ra] FAIL download failed
```
Results: harness/research/vdec-perf/logs/runner-avs2q/. Board restored to stock, lock released.
