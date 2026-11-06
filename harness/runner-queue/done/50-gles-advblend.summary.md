# Job 50-gles-advblend summary
Kernel: c38 (uname -v: #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026). Start ~15:09, end 15:16:23. Verdict: ALL PASS.
Check 1 PASS:
- 2026-11-06 15:09:05 fork: 02df5721016 (contains dc7266d584b), libgallium c4bd54cc9865f932a5a1f2cd5521942b
- kernel: #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026
- 2026-11-06 15:10:56 kernel fix: present (c38 contains e17629bba, panfrost.ko md5 9014bbc7a2b41c667e3c562193d22eec)
- 2026-11-06 15:11:19 deployed gl1 ok (libgallium md5 f5b0b74fbec7bbdd4d666a4eb75fdb9d)
Check 2 PASS (7 fork TAGs RESULT PASS). Data TAG lines (sys-*, knob-*, all with RESULT PASS, version/ms/TO) verbatim:
- TAG sys-mixed: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4-1ubuntu1 | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=4947 TO=1
- TAG sys-mixed-barrier: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4-1ubuntu1 | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=1 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1278 TO=1
- TAG fork-mixed: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1204 TO=2
- TAG fork-mixed-2: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1256 TO=3
- TAG fork-mixed-3: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1199 TO=4
- TAG fork-multiply: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq multiply x1, 1024x1024, barrier=0 first pixel: 4,4,4,255 ref 4,4,4,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=599 TO=4
- TAG fork-mixed-barrier: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=1 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1220 TO=4
- TAG fork-mixed-x8: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x8, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1893 TO=6
- TAG fork-mixed-256: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 256x256, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 65536 RESULT PASS  ms=353 TO=6
- TAG knob-opaque: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1215 TO=7
- TAG knob-overdraw: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1198 TO=8
- TAG knob-persample: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1199 TO=9
- TAG knob-opaque-overdraw: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1198 TO=10
- TAG knob-opaque-persample: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1198 TO=11
- TAG knob-overdraw-persample: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1202 TO=12
- TAG knob-all: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1199 TO=13
- TAG knob-all-2: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS  ms=1246 TO=14
Check 3 PASS: KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence,Pass,0.00,; khr-adv SUMMARY: SUMMARY cases=88 {'Pass': 88} REGRESSIONS=0 FIXED=1 CHANGED=0 MISSING=0; FIXED KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence Fail -> Pass
Check 4 PASS (REGRESSIONS=0 MISSING=0 all six):
- deqp-fbfetch: SUMMARY cases=146 {'Pass': 146} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- deqp-ms: SUMMARY cases=410 {'Pass': 408, 'NotSupported': 2} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- khr-ms: SUMMARY cases=199 {'Pass': 161, 'NotSupported': 38} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- deqp-fbo: SUMMARY cases=118 {'NotSupported': 41, 'Pass': 77} REGRESSIONS=0 FIXED=1 CHANGED=0 MISSING=0
- gles3-blend-a: SUMMARY cases=1152 {'Pass': 1152} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- gles3-blend-b: SUMMARY cases=1152 {'Pass': 1152} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- deqp-fbo: FIXED dEQP-GLES31.functional.fbo.no_attachments.maximums.all Fail -> Pass
Check 5 PASS: fault-pattern grep count 0 in all dmesg-*.txt; "gpu sched timeout" count 0 in all 8 dmesg files.
TRACE: TIMEDOUT per chunk: repro 14, khr-adv 1, deqp-fbfetch 0, deqp-ms 0, khr-ms 0, deqp-fbo 9, gles3-blend-a 0, gles3-blend-b 0 (data)
Check 6 PASS: all 8 chunks end with ROUND-DONE, no STALLED.
Check 7 PASS: 2026-11-06 15:16:23 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 
State file: repro khr-adv deqp-fbfetch deqp-ms khr-ms deqp-fbo gles3-blend-a gles3-blend-b 
Results: harness/research/gles-advblend/logs/runner2/
