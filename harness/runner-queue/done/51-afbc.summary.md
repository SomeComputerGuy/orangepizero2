# Job 51-afbc summary
Kernel: 7.3.1 #38 SMP PREEMPT Fri Nov 6 10:29:47 UTC 2026 (c38); restored stock #17. Start 2026-11-06 15:31, end 15:37 (5 of 5 chunks).
Verdict: NOT TESTABLE (GPU has no AFBC)
Check 0: PASS  2026-11-06 15:33:35 deployed main ok (mesa 15bd751e896, libgallium-27.0.0-devel.so md5 4d42fdd7c40fcb1961740d856fd6cdba)
Per chunk (vp9p2 hevc10 avs2 hevc8 vp9p0): GL_RENDERER Mesa 27.0.0-devel (not system Mesa) PASS; all chunks print 'afbc: NOT TESTABLE on the GPU'; per-case F/C/M/X table N/A (no case ran).
Probe lines (first chunk, vp9p2), verbatim:
```
[gl] probe: gpu prod-id 0x7093, AFBC_FEATURES 0x10001 -> gpu-afbc no
[gl] probe: dma-buf format YU08 listed
[gl] probe: dma-buf format YU10 listed
[gl] probe: YU08 modifiers (0):
[gl] probe: YU10 modifiers (0):
[hevc8q] dec rc 0 check rc 2 1 s |  | input: 3840x2160 YU08 modifier 0x0800000000000061 size 13057056, 8-bit, layout nv12, 600 reference md5s import with pitch 5760 failed: EGL 0x3009 import with pitch 7680 failed: EGL 0x3009 import with pitch 5760 failed: EGL 0x3009 import with pitch 3840 failed: EGL 0x3009 import with pitch 15360 failed: EGL 0x3009 import-failed: gpu-has-no-afbc (AFBC_FEATURES != 0: Mesa lists no AFBC modifier on this GPU) 
[hevc8q] probe: YU08 modifiers (0):
[hevc8q] probe: YU10 modifiers (0):
[hevc8q] hdr frame 0 sb 0: 00 f8 07 c0 5a 4f 29 25 ce d8 7b fe bd c7 02 7b
[hevc8q] hdr frame 0 sb 1: 80 f9 07 d0 58 3f e7 24 ce da 7a fc 39 f7 f6 5b
[hevc8q] hdr frame 0 sb 2: 00 fb 07 c0 d8 56 4a a1 ce d8 5b dd bd f7 fa 7b
[hevc8q] hdr frame 0 sb 3: 80 fc 07 c0 d8 4e 69 2d ce d8 7b fe bd e7 f8 7a
[hevc8q] hdr frame 0 sb 240: 00 60 09 a0 58 67 21 04 9e 92 4a 30 a5 c4 34 4b
[hevc8q] hdr frame 0 sb 32399: 80 ce c5 20 c8 11 00 00 04 80 00 03 10 01 00 20
[hevc8q] import-failed: gpu-has-no-afbc (AFBC_FEATURES != 0: Mesa lists no AFBC modifier on this GPU)
```
Files in files/: frame-0.afbc-head (binary, not committed), hevc8q.check.txt, hevc8q.dec.txt, probe.txt
Logs: harness/research/vdec-perf/logs/runner-afbc/ (chunk-*, dmesg-*, runner.log)
Abnormal dmesg (fault/timeout/BUG/Oops/WARN grep): 5 lines
