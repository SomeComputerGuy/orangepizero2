# 46-rgb-tdim summary
Job ran fully: 12 of 12 chunks, script exit 0, no Oops. Start ~2026-11-06 14:13, end 14:53:41. Results: research/opencl-fixes/logs/runner-rgbtdim/ (stock kernel restored by script).
## Verdicts
- RGB-OVERFETCH: MIXED (rule: CONFIRMED needs FAULTS>0 for rgb8 or rgb32i in A; A had FAULTS 0 for rgb8 and rgb32i, faults only in rgb8s [A, A2] and rgb32is [A: 2 faults, A2: 1 fault]; B and B2 FAULTS 0 for all 6 cases)
- RGB-FIX: PASS (edgeB, edgeB2, ctsB, ctsB2, s32B all FAULTS 0 / F 0; ctsB, ctsB2, s32B PASS)
- TDIM: PASS (all 5 tests PASS)
## Check 1
kernel: #38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026
2026-11-06 14:13:38 kernel fix: present (panfrost.ko md5 9014bbc7a2b41c667e3c562193d22eec)
2026-11-06 14:14:21 deployed cl3 ok (mesa-cl 02df5721016, libRusticlOpenCL md5 598e32eada258ac0d43b1abf166d12ce); cl2 present
## Check 2 EDGE table (A = old cl2, B = new cl3; all RC 0)
[edgeA] EDGE A rgb8 RC 0 FAULTS 0
[edgeA] EDGE A rgb32i RC 0 FAULTS 0
[edgeA] EDGE A rgba8 RC 0 FAULTS 0
[edgeA] EDGE A rgba32i RC 0 FAULTS 0
[edgeA] EDGE A rgb8s RC 0 FAULTS 1
[edgeA] EDGE A rgb32is RC 0 FAULTS 2
[edgeB] EDGE B rgb8 RC 0 FAULTS 0
[edgeB] EDGE B rgb32i RC 0 FAULTS 0
[edgeB] EDGE B rgba8 RC 0 FAULTS 0
[edgeB] EDGE B rgba32i RC 0 FAULTS 0
[edgeB] EDGE B rgb8s RC 0 FAULTS 0
[edgeB] EDGE B rgb32is RC 0 FAULTS 0
[edgeA2] EDGE A rgb8 RC 0 FAULTS 0
[edgeA2] EDGE A rgb32i RC 0 FAULTS 0
[edgeA2] EDGE A rgba8 RC 0 FAULTS 0
[edgeA2] EDGE A rgba32i RC 0 FAULTS 0
[edgeA2] EDGE A rgb8s RC 0 FAULTS 1
[edgeA2] EDGE A rgb32is RC 0 FAULTS 1
[edgeB2] EDGE B rgb8 RC 0 FAULTS 0
[edgeB2] EDGE B rgb32i RC 0 FAULTS 0
[edgeB2] EDGE B rgba8 RC 0 FAULTS 0
[edgeB2] EDGE B rgba32i RC 0 FAULTS 0
[edgeB2] EDGE B rgb8s RC 0 FAULTS 0
[edgeB2] EDGE B rgb32is RC 0 FAULTS 0

Non-64-of-64 RESULT lines (edgeA only; none in other chunks):
EDGE A rgb32is: RESULT rgb32is rep 0 enqueue 0 finish 0 stored 12 of 64
EDGE A rgb32is: RESULT rgb32is rep 1 enqueue 0 finish 0 stored 0 of 64
EDGE A rgb32is: RESULT rgb32is rep 2 enqueue 0 finish 0 stored 4 of 64

EDGE DMESG lines verbatim:
[edgeA] EDGE A rgb8s DMESG: [   93.796413] panfrost 1800000.gpu: Unhandled Page fault in AS0 at VA 0x000000000A038000
[edgeA] EDGE A rgb8s DMESG: [   93.796431] panfrost 1800000.gpu: fault bo: inside: VA [0xa038000-0xa048000) size 0x10000, fault at start+0x0, mapped, noexec, label "Unused (BO cache)"
[edgeA] EDGE A rgb32is DMESG: [   94.534704] panfrost 1800000.gpu: Unhandled Page fault in AS0 at VA 0x000000000A181000
[edgeA] EDGE A rgb32is DMESG: [   94.534741] panfrost 1800000.gpu: fault bo: below: VA [0xa041000-0xa181000) size 0x140000, fault at end+0x0, mapped, noexec, label "Texture format=r32g32b32_sint extent=25x128x32 array_size=1 mip_count=0 samples=0 modifier=0x0"
[edgeA] EDGE A rgb32is DMESG: [   94.534805] panfrost 1800000.gpu: js fault, js=1, status=JOB_BUS_FAULT, head=0xa010200, tail=0xa010200
[edgeA] EDGE A rgb32is DMESG: [  100.547188] panfrost 1800000.gpu: Unhandled Page fault in AS0 at VA 0x000000000A181000
[edgeA] EDGE A rgb32is DMESG: [  100.547257] panfrost 1800000.gpu: fault bo: below: VA [0xa041000-0xa181000) size 0x140000, fault at end+0x0, mapped, noexec, label "Texture format=r32g32b32_sint extent=25x128x32 array_size=1 mip_count=0 samples=0 modifier=0x0"
[edgeA] EDGE A rgb32is DMESG: [  100.547374] panfrost 1800000.gpu: js fault, js=1, status=JOB_BUS_FAULT, head=0xa021200, tail=0xa021200
[edgeA2] EDGE A rgb8s DMESG: [  162.623944] panfrost 1800000.gpu: Unhandled Page fault in AS0 at VA 0x000000000A038000
[edgeA2] EDGE A rgb8s DMESG: [  162.623965] panfrost 1800000.gpu: fault bo: inside: VA [0xa038000-0xa048000) size 0x10000, fault at start+0x0, mapped, noexec, label "Unused (BO cache)"
[edgeA2] EDGE A rgb32is DMESG: [  163.367031] panfrost 1800000.gpu: Unhandled Page fault in AS0 at VA 0x000000000A171000
[edgeA2] EDGE A rgb32is DMESG: [  163.367048] panfrost 1800000.gpu: fault bo: inside: VA [0xa171000-0xa181000) size 0x10000, fault at start+0x0, mapped, noexec, label "Unused (BO cache)"

## Check 3 RGBCTS (all PASS; RC 0, FAULTS 0, PASSED, no FAILED)
RGBCTS ctsA2 CL_UNORM_INT8 RC 0 t=29s FAULTS 0
RGBCTS ctsA2 CL_SNORM_INT8 RC 0 t=29s FAULTS 0
RGBCTS ctsA CL_UNORM_INT8 RC 0 t=29s FAULTS 0
RGBCTS ctsA CL_SNORM_INT8 RC 0 t=29s FAULTS 0
RGBCTS ctsB2 CL_UNORM_INT8 RC 0 t=28s FAULTS 0
RGBCTS ctsB2 CL_SNORM_INT8 RC 0 t=29s FAULTS 0
RGBCTS ctsB CL_UNORM_INT8 RC 0 t=29s FAULTS 0
RGBCTS ctsB CL_SNORM_INT8 RC 0 t=29s FAULTS 0

## Check 4 s32B: PASS
IMG-RC 0 t=278s
IMG: PASSED 11 of 11 sub-tests.
IMG: PASSED test.; Unhandled Page fault count F = 0

## Check 5 TDIM (all PASS)
[tdim2x]
PROG t=60s run=86 done=86 timedout=5
PROG t=120s run=132 done=131 timedout=53
TDIM 1 quick_2d_explicit_local RC 0 t=155s
TDIM 1 quick_2d_explicit_local: quick_2d_explicit_local...
TDIM 1 quick_2d_explicit_local: quick_2d_explicit_local passed
TDIM 1 quick_2d_explicit_local: PASSED sub-test.
TDIM 1 quick_2d_explicit_local: PASSED test.
PROG t=180s run=188 done=188 timedout=94
PROG t=240s run=262 done=261 timedout=113
PROG t=300s run=292 done=292 timedout=180
TDIM 2 quick_2d_explicit_local RC 0 t=154s
TDIM 2 quick_2d_explicit_local: quick_2d_explicit_local...
TDIM 2 quick_2d_explicit_local: quick_2d_explicit_local passed
TDIM 2 quick_2d_explicit_local: PASSED sub-test.
TDIM 2 quick_2d_explicit_local: PASSED test.
PROG t=360s run=374 done=374 timedout=190
PROG t=421s run=424 done=423 timedout=232
TDIM 3 quick_2d_explicit_local RC 0 t=154s
TDIM 3 quick_2d_explicit_local: quick_2d_explicit_local...
TDIM 3 quick_2d_explicit_local: quick_2d_explicit_local passed
TDIM 3 quick_2d_explicit_local: PASSED sub-test.
TDIM 3 quick_2d_explicit_local: PASSED test.
TDIM-TRACE run=444 done=444 timedout=281
[tdim3e]
PROG t=60s run=92 done=92 timedout=0
PROG t=120s run=124 done=123 timedout=71
PROG t=181s run=136 done=135 timedout=170
PROG t=241s run=146 done=145 timedout=273
PROG t=301s run=156 done=156 timedout=374
PROG t=361s run=168 done=167 timedout=473
PROG t=421s run=178 done=177 timedout=575
PROG t=481s run=190 done=189 timedout=672
PROG t=541s run=200 done=199 timedout=772
PROG t=601s run=210 done=209 timedout=874
PROG t=661s run=220 done=219 timedout=975
PROG t=721s run=232 done=231 timedout=1072
PROG t=781s run=242 done=241 timedout=1173
PROG t=842s run=252 done=251 timedout=1274
TDIM 1 quick_3d_explicit_local RC 0 t=845s
TDIM 1 quick_3d_explicit_local: quick_3d_explicit_local...
TDIM 1 quick_3d_explicit_local: quick_3d_explicit_local passed
TDIM 1 quick_3d_explicit_local: PASSED sub-test.
TDIM 1 quick_3d_explicit_local: PASSED test.
TDIM-TRACE run=252 done=252 timedout=1279
[tdim3i]
PROG t=61s run=92 done=90 timedout=0
TDIM 1 quick_3d_implicit_local RC 0 t=80s
TDIM 1 quick_3d_implicit_local: quick_3d_implicit_local...
TDIM 1 quick_3d_implicit_local: quick_3d_implicit_local passed
TDIM 1 quick_3d_implicit_local: PASSED sub-test.
TDIM 1 quick_3d_implicit_local: PASSED test.
TDIM-TRACE run=116 done=116 timedout=0
dmesg gpu sched timeout / Soft-stop / Hard-stop / resetting lines in dmesg-tdim*.txt: none (0)

## Check 6: all 12 chunks have ROUND-DONE; no CUT-OFF. No Oops/BUG in any dmesg.
State file: edgeA edgeB edgeA2 edgeB2 ctsA ctsB ctsA2 ctsB2 s32B tdim2x tdim3e tdim3i 
