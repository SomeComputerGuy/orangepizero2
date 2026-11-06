# 13-vp9-upsize: PASS (all 7 checks)
Start 2026-11-05 23:17:24 UTC, end 23:25:22 UTC.
```
cumulative c17 test-cumulative 7897dec08 2026-11-05 22:09:58 Image md5 22330a4caccc513b757e743934c2700f
7.3.1 #18 SMP PREEMPT Thu Nov  5 22:07:30 UTC 2026
kernel c17 test-cumulative 7897dec08 2026-11-05 22:09:58 Image md5 22330a4caccc513b757e743934c2700f contains the upsize fix 7897dec08
CHECK 0 kernel contains the upsize fix 7897dec08 (fix/sunxi-cedrus-vp9-inter-upsize) and the pre-flight vector decoded: PASS (kernel.txt: cumulative c17 test-cumulative 7897dec08 2026-11-05 22:09:58 Image md5 22330a4caccc513b757e743934c2700f; contains fix: True; pre-flight vp90-2-00-quantizer-00.webm: Success)
CHECK 1 all chunks ran (u1 u2.md present, 27/25 vectors): PASS (missing chunks: []; vectors seen: 52 of 52)
CHECK 2 inter-frame UPSIZE vector vp90-2-22-svc_1280x720_3 Success: PASS (result: Success)
CHECK 3 inter-frame downsize vectors (24 x vp90-2-21-resize_inter_*, 05-resize, 18-resize) all Success: PASS (26/26 Success; failing: )
CHECK 4 regression subset (u2, 25 profile-0 vectors) all Success: PASS (0 failing: )
CHECK 5 dmesg: no timeouts, IOMMU faults, Oops or WARNING: PASS (clean)
CHECK 6 no fluster per-vector timeouts (90 s): PASS (none)
VERDICT: PASS; upsize job 52/52 Success (of 52), svc_1280x720_3 Success

| group | success | total | failing |
|---|---|---|---|
| quantizer | 2 | 2 |  |
| sharpness | 1 | 1 |  |
| size-02 (8..66 px) | 3 | 3 |  |
| size-03 (196..226 px) | 1 | 1 |  |
| size-11 (odd) | 1 | 1 |  |
| resize on key frames (14) | 2 | 2 |  |
| resize on inter frames (21, 05, 18) | 26 | 26 |  |
| svc | 2 | 2 |  |
| show-existing-frame | 2 | 2 |  |
| intra-only | 1 | 1 |  |
| other | 11 | 11 |  |

CHECK 0 kernel contains the upsize fix 7897dec08 (fix/sunxi-cedrus-vp9-inter-upsize) and the pre-flight vector decoded: PASS (kernel.txt: cumulative c17 test-cumulative 7897dec08 2026-11-05 22:09:58 Image md5 22330a4caccc513b757e743934c2700f; contains fix: True; pre-flight vp90-2-00-quantizer-00.webm: Success)
```
env.txt MISSING: none. dmesg cedrus lines (exact): '[    0.242071] cedrus 1c0e000.video-codec: Device registered as /dev/video0'; no timed out/fault/Oops/WARNING.
Results: harness/vp9-vectors/logs/upsize/. Stock kernel restored (#17 Fri Oct 30), lock released.
