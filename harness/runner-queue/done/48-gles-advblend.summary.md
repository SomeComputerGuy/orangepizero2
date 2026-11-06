# 48-gles-advblend summary
Verdict: FAIL (fix not effective: mixedSequence still fails). Job ran fully, 8 of 8 chunks, exit 0.
Kernel: stock, `uname -v` = #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 (no install/restore). Start 2026-11-06 14:05:34, end 14:10:40.
Results: research/gles-advblend/logs/runner/

## Check 1 (runner.log)
2026-11-06 14:05:34 fork: 02df5721016 (contains dc7266d584b), libgallium b3a8a91350b9edfdca72093a7eb8b133
kernel: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026
2026-11-06 14:06:00 deployed gl1 ok (libgallium md5 f5b0b74fbec7bbdd4d666a4eb75fdb9d)
No "note: ... stale build" line. (Earlier run at 11:03 was the old blocked attempt; lines above are from the 14:05 run.)

## Check 2 repro: FAIL
Version string is "git-02df572101" (fork 02df5721016, which contains dc7266d584b), not "git-dc7266d584": the literal version check fails for all fork TAGs; reported as is.
Results: fork-mixed, fork-mixed-2, fork-mixed-3, fork-mixed-x8 RESULT FAIL; fork-mixed-256, fork-multiply, fork-mixed-barrier RESULT PASS.
All TAG lines verbatim:
TAG sys-mixed: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4-1ubuntu1 | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 199056 of 1048576 RESULT FAIL 
TAG sys-mixed-barrier: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4-1ubuntu1 | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=1 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS 
TAG fork-mixed: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 290432 of 1048576 RESULT FAIL 
TAG fork-mixed-2: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 303600 of 1048576 RESULT FAIL 
TAG fork-mixed-3: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 283312 of 1048576 RESULT FAIL 
TAG fork-multiply: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq multiply x1, 1024x1024, barrier=0 first pixel: 4,4,4,255 ref 4,4,4,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS 
TAG fork-mixed-barrier: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=1 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 1048576 RESULT PASS 
TAG fork-mixed-x8: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x8, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 676544 of 1048576 RESULT FAIL 
TAG fork-mixed-256: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 256x256, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 1; pixels != first: 0 of 65536 RESULT PASS 
TAG knob-opaque: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 298400 of 1048576 RESULT FAIL 
TAG knob-overdraw: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 287088 of 1048576 RESULT FAIL 
TAG knob-persample: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 285872 of 1048576 RESULT FAIL 
TAG knob-opaque-overdraw: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 285168 of 1048576 RESULT FAIL 
TAG knob-opaque-persample: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 285584 of 1048576 RESULT FAIL 
TAG knob-overdraw-persample: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 286736 of 1048576 RESULT FAIL 
TAG knob-all: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 287152 of 1048576 RESULT FAIL 
TAG knob-all-2: renderer: Mali-G31 MC1 (Panfrost) | version: OpenGL ES 3.1 Mesa 26.2.4 (git-02df572101) | coherent ext: 1 | seq mixed x4, 1024x1024, barrier=0 first pixel: 32,32,32,255 ref 32,32,32,255 OK; distinct values: 2; pixels != first: 285136 of 1048576 RESULT FAIL 

## Check 3 khr-adv: FAIL
KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence,Fail,0.00,results differ
SUMMARY cases=88 {'Pass': 87, 'Fail': 1} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0 (REGRESSIONS=0 but mixedSequence is Fail; FIXED lines: none)

## Check 4 CTS chunks: all PASS (REGRESSIONS=0 MISSING=0, no FIXED/CHANGED lines)
- deqp-fbfetch: SUMMARY cases=146 {'Pass': 146} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- deqp-ms: SUMMARY cases=410 {'Pass': 408, 'NotSupported': 2} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- khr-ms: SUMMARY cases=199 {'Pass': 161, 'NotSupported': 38} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- deqp-fbo: SUMMARY cases=118 {'NotSupported': 41, 'Pass': 76, 'Fail': 1} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- gles3-blend-a: SUMMARY cases=1152 {'Pass': 1152} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
- gles3-blend-b: SUMMARY cases=1152 {'Pass': 1152} REGRESSIONS=0 FIXED=0 CHANGED=0 MISSING=0
Note: deqp-fbo has 1 Fail (dEQP-GLES31.functional.fbo.no_attachments.maximums.all), same as baseline (not a regression).

## Check 5 dmesg: PASS (0 hits of js fault|Soft-stop failed|Page fault|Unhandled in every chunk)
gpu sched timeout counts (data): dmesg-repro.txt:13 dmesg-khr-ms.txt:0 dmesg-deqp-fbo.txt:3 dmesg-deqp-fbfetch.txt:0 dmesg-gles3-blend-a.txt:0 dmesg-deqp-ms.txt:0 dmesg-gles3-blend-b.txt:0 dmesg-khr-adv.txt:1 

## Check 6: all 8 chunks end with ROUND-DONE
state file: repro khr-adv deqp-fbfetch deqp-ms khr-ms deqp-fbo gles3-blend-a gles3-blend-b 
