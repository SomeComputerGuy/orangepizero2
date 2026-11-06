# 10-vp9-vectors: PASS (VERDICT: PASS; 303/305 Success, HIGH 1/6)
Start 2026-11-06 01:59:55 UTC, end 02:16:41 UTC.
```
cumulative c25 test-cumulative 04964f921 2026-11-06 01:52:16 Image md5 de8e87b28a1cb43b3b96d83c69f3577e
7.3.1 #24 SMP PREEMPT Fri Nov  6 01:50:06 UTC 2026
CHECK 0 kernel is a cumulative kernel >= c10 (contains f8be54bac) and the pre-flight vector decoded: PASS (kernel.txt: cumulative c25 test-cumulative 04964f921 2026-11-06 01:52:16 Image md5 de8e87b28a1cb43b3b96d83c69f3577e; pre-flight vp90-2-00-quantizer-00.webm: Success)
CHECK 1 all chunks ran (c1 c2 c3 c5 c4.md present, 71/137/59/38/6 vectors): PASS (missing chunks: []; vectors seen: 311 of 311)
CHECK 2 inter-frame downsize vectors (24 x vp90-2-21-resize_inter_*, 05-resize, 18-resize) all Success: PASS (26/26 Success; failing: )
CHECK 3 every other decodable vector Success (302 of the 305 + 10-bit 4:2:0 of HIGH): PASS (0 failing: )
CHECK 4 expected-unsupported vectors (2 x vp91, 12-bit, vp93) are not Success: PASS (as expected)
CHECK 5 dmesg: no timeouts, IOMMU faults, Oops or WARNING: PASS (clean)
CHECK 6 no fluster per-vector timeouts (90 s): PASS (none)
VERDICT: PASS; VP9-TEST-VECTORS 303/305 Success, HIGH 1/6 Success
| group | success | total | failing |
|---|---|---|---|
| quantizer | 64 | 64 |  |
| sharpness | 7 | 7 |  |
| size-02 (8..66 px) | 71 | 71 |  |
| size-03 (196..226 px) | 65 | 65 |  |
| size-11 (odd) | 3 | 3 |  |
| resize on key frames (14) | 36 | 36 |  |
| resize on inter frames (21, 05, 18) | 26 | 26 |  |
| svc | 2 | 2 |  |
| show-existing-frame | 3 | 3 |  |
| intra-only | 1 | 1 |  |
| profile 1 (4:2:2/4:4:4) | 0 | 2 | vp91-2-04-yuv422.webm vp91-2-04-yuv444.webm |
| HIGH 10-bit 4:2:0 | 1 | 1 |  |
| HIGH unsupported (12-bit, 4:2:2/4:4:0/4:4:4) | 0 | 5 | vp92-2-20-12bit-yuv420.webm vp93-2-20-10bit-yuv422.webm vp93-2-20-10bit-yuv444.webm vp93-2-20-12bit-yuv422.webm vp93-2-20-12bit-yuv444.webm |
| other | 25 | 25 |  |
env.txt MISSING: none
2026-11-06 02:16:41 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 
```
dmesg: only boot lines (pid_max, NetLabel, PCI, bridge, systemd) matched the generic grep; no cedrus/timed out/fault/Oops/WARNING lines.
Results: harness/vp9-vectors/logs/runner/
