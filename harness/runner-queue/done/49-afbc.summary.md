# Job 49-afbc summary
Kernel: c38 (uname -v: #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026). Start 2026-11-06 15:03:37, end 15:08:40. Stock kernel restored (#17).
Verdict: INCONCLUSIVE (quick: ok=0 in every chunk; dma-buf import failed for every pitch, EGL 0x3009).
- Check 0: PASS: deployed main ok (mesa 15bd751e896, libgallium-27.0.0-devel.so md5 4d42fdd7c40fcb1961740d856fd6cdba)
- GL_RENDERER (all 5): Mali-G31 MC1 (Panfrost), OpenGL ES 3.1 Mesa 27.0.0-devel (git-15bd751e89): PASS (not system Mesa)
- quick: ok=0 (all 5): per HANDOFF every case INCONCLUSIVE, not FAIL.
Per case (F/C/M/X not produced; no "done:" line):
- vp9p2: dec rc 0 check rc 2; afbc-gpu-check: dma-buf import failed for every pitch
- hevc10: dec rc 0 check rc 2; same
- avs2: dec rc 141 (harmless) check rc 2; same
- hevc8: dec rc 0 check rc 2; same
- vp9p0: dec rc 0 check rc 2; same
Each case line: "import with pitch N failed: EGL 0x3009" for pitches 7200/5760, 7680, 5760, 3840, 15360.
Results: research/vdec-perf/logs/runner-afbc/ (chunk-*.txt, dmesg-*.txt, files/). dmesg: only benign boot lines (iommu group/domain info), no faults/timeouts.
