# 04-vp9-vectors: FAIL
Kernel (kernel.txt): 7.3.1 #14 SMP PREEMPT Thu Nov  5 19:57:13 UTC 2026. Start 2026-11-05 20:17:46 UTC, end 20:31:49 UTC. runner.log: 'job end: 3 of 4 chunks done'; state: c1 c2 c4 (c3 missing, no c3.md/dmesg).
Whether kernel contains f8be54bac was not judged.
Every vector in c1, c2, c4 is ER/not Success (0/305 VP9-TEST-VECTORS, 0/6 HIGH); no per-vector timeouts.
```
CHECK 1 all four chunks ran (c1..c4.md present, 71/137/97/6 vectors): FAIL (missing chunks: ['c3']; vectors seen: 214 of 311)
CHECK 2 inter-frame resize vectors (24 x vp90-2-21-resize_inter_*, 05-resize, 18-resize) all Success: FAIL (0/0 Success; failing: )
CHECK 3 every other decodable vector Success (302 of the 305 + 10-bit 4:2:0 of HIGH): FAIL (209 failing: vp90-2-00-quantizer-00.webm vp90-2-00-quantizer-01.webm vp90-2-00-quantizer-02.webm vp90-2-00-quantizer-03.webm vp90-2-00-quantizer-04.webm vp90-2-00-quant
CHECK 4 expected-unsupported vectors (2 x vp91, svc_1280x720_3, 12-bit, vp93) are not Success: PASS (as expected)
CHECK 5 dmesg: no timeouts, IOMMU faults, Oops or WARNING: FAIL (dmesg-c1.txt: [    0.124783] iommu: Default domain type: Translated
CHECK 6 no fluster per-vector timeouts (90 s): PASS (none)
VERDICT: FAIL; VP9-TEST-VECTORS 0/305 Success, HIGH 0/6 Success
```
Group table (counts only):
 group | success | total 
 quantizer | 0 | 64 
 sharpness | 0 | 7 
 size-02 (8..66 px) | 0 | 71 
 size-03 (196..226 px) | 0 | 65 
 HIGH 10-bit 4:2:0 | 0 | 1 
 HIGH unsupported (12-bit, 4:2:2/4:4:0/4:4:4) | 0 | 5 
 other | 0 | 1 
Group counts: quantizer 0/64, sharpness 0/7, size-02 0/71, size-03 0/65, HIGH 10-bit 0/1, HIGH unsupported 0/5, other 0/1 (full list in harness/vp9-vectors/logs/runner/check.txt)
env.txt MISSING lines: none
dmesg-c<N>.txt lines matching cedrus/timed out/fault/Oops/WARNING (identical in c1-c4):
[    0.001435] pid_max: default: 32768 minimum: 301
[    0.124783] iommu: Default domain type: Translated
[    0.129350] NetLabel:  unlabeled traffic allowed by default
[    0.142275] PCI: CLS 0 bytes, default 64
[    0.242022] cedrus 1c0e000.video-codec: Device registered as /dev/video0
[    0.266572] bridge: filtering via arp/ip/ip6tables is no longer available by default. Update your scripts to load br_netfilter if you need this.
[    8.272270] systemd[1]: Queued start job for default target graphical.target.
Results: harness/vp9-vectors/logs/runner/ (check.txt, runner.log, out/)
