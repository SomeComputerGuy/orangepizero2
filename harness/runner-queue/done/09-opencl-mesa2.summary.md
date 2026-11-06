# 09-opencl-mesa2 summary
Verdict: FAIL (2 failing areas; 12 of 14 chunks clean). Kernel: stock '#17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026'. 14/14 chunks ran, 2026-11-06 12:05 to 13:38:37. No kernel install.
Check 1 PASS: 2026-11-06 12:05:58 fork: dc7266d584b (contains a0a4534b14d), lib d7f49a679bacb7f7632a1d719ce48ef6 | kernel: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 | 2026-11-06 12:06:24 deployed cl2 ok (libRusticlOpenCL md5 65426c07af5f2a0de70925cfe97f3e0d)
Check 2 sl: FAIL.
- Images (Samplerless int),Pass,0,PASSED 6 of 6 tests.
- Images (Samplerless uint),Pass,0,PASSED 6 of 6 tests.
- Images (Samplerless float),Fail,1,FAILED 1 of 6 tests.  (log: ' Sampler-less reads differ from reads with sampler.' / 'FAILED: [CL_A    CL_UNORM_INT8            1] - CL_FILTER_NEAREST - CL_ADDRESS_NONE - UNNORMALIZED' / '1Dbuffer FAILED' / 'FAILED 1 of 235 sub-tests.')
- dmesg-sl: DMESG: [  181.788808] panfrost 1800000.gpu: js fault, js=1, status=INSTR_INVALID_ENC, head=0xa010240, tail=0xa010240
Check 3 basic: PASS. basic-a PASSED 36 of 36; basic-b PASSED 31 of 31; basic-c PASSED 9 of 9; basic-d PASSED 28 of 28. enqueue_map_image passed count in basic-b = 1.
Check 4 f2d:
- f2d-r2d: PASS (PASSED 328 of 328 sub-tests / PASSED test, CHUNK-RC 0)
- f2d-r2da: FAIL / NOT FINISHED, CHUNK-RC 124 (chunk cut at 870 s), last line '[CL_INTENSITY CL_HALF_FLOAT            1] - CL_FILTER_NEAREST - CL_ADDRESS_CLAMP_TO_EDGE - NORMALI...'. FAILED lines:
  FAILED: [CL_RGB  CL_SNORM_INT8            3] - CL_FILTER_NEAREST - CL_ADDRESS_CLAMP_TO_EDGE - UNNORMALIZED
  FAILED: [CL_RGB  CL_SNORM_INT8            3] - CL_FILTER_NEAREST - CL_ADDRESS_CLAMP - UNNORMALIZED
  FAILED: [CL_RGB  CL_UNORM_INT8            3] - CL_FILTER_NEAREST - CL_ADDRESS_CLAMP_TO_EDGE - UNNORMALIZED
  FAILED: [CL_RGB  CL_UNORM_INT8            3] - CL_FILTER_NEAREST - CL_ADDRESS_CLAMP - UNNORMALIZED
- f2d-w: PASS (PASSED 2 of 2); f2d-rw: PASS (PASSED 2 of 2)
Check 5 imgA-D: PASS, all 11 listed suites Pass (rows in files/imgD/binaries.csv).
Check 6 reg: PASS, all 17 suites Pass (files/reg/binaries.csv).
Check 7 dmesg: hits only in sl (above) and f2d-r2da -> FAIL for those; the others 0. Verbatim f2d-r2da lines (gpu sched timeout count 2):
DMESG: [ 2124.517872] panfrost 1800000.gpu: Unhandled Page fault in AS0 at VA 0x000000000A016000
DMESG: [ 2124.517990] panfrost 1800000.gpu: js fault, js=1, status=JOB_BUS_FAULT, head=0xa1bf200, tail=0xa1bf200
DMESG: [ 2125.129590] panfrost 1800000.gpu: gpu sched timeout, js=1, config=0x7b00, status=0x8, head=0xa1bf200, tail=0xa1bf200, sched_job=00000000ef02971c
DMESG: [ 2125.221349] panfrost 1800000.gpu: Unhandled Page fault in AS0 at VA 0x000000000A016000
DMESG: [ 2125.221431] panfrost 1800000.gpu: js fault, js=1, status=JOB_BUS_FAULT, head=0xa1bf200, tail=0xa1bf200
DMESG: [ 2125.833627] panfrost 1800000.gpu: gpu sched timeout, js=1, config=0x7b00, status=0x8, head=0xa1bf200, tail=0xa1bf200, sched_job=00000000c3c3f281
sched timeout counts: all other chunks 0.
Check 8: all chunks ROUND-DONE except f2d-r2da (CHUNK-RC 124 after the fault; not rerun).
State: sl basic-a basic-b basic-c basic-d f2d-r2d f2d-r2da f2d-w f2d-rw imgA imgB imgC imgD reg
Files: harness/research/opencl-fixes/logs/runner-mesa2/
