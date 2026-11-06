# 18-panfrost-softstop: FAIL (stress chunk no ROUND-DONE with 2 VK timeouts; intops Timeout; tdim Timeout; math-a FAILED 34 of 54; math-b ERROR; img3d NOT FINISHED; dmesg intops 39 hits). No Oops.
Start 2026-11-06 02:24:27 UTC, end 03:39:59 UTC (this run; older 2026-11-05 lines for job 08 remain earlier in runner.log).
Kernel: c25 (Image md5 de8e87b28a1cb43b3b96d83c69f3577e): kernel: #24 SMP PREEMPT Fri Nov  6 01:50:06 UTC 2026; "kernel fix: present (panfrost.ko md5 4d6f7d6d31322bc6b3f86e9fe10a7934)". runner.log: "job timeout-fix end: 6 of 7 chunks done"; restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64. state file: intops tdim math-a math-b reg img3d (stress absent).
No OOPS file, no BLOCKED.
Per check:
1 PASS.
2 stress: FAIL. chunk-stress.txt has no ROUND-DONE ("chunk stress ended without ROUND-DONE", 02:26:21-02:41:07). INTOPS 1 and 2 "PASSED 2 of 2 tests." (t=76s, t=22s); TDIM "PASSED test." (t=156s; the check expects "PASSED 1 of 1 tests." text, actual line differs); "Incomplete job" count 0; VK lines: 11 present (14 expected), 9 with rc=0 Pass, 2 rc=124 t=200s result=[] (listed below).
3 intops: FAIL: Integer Ops,Timeout,timeout,,800,integer_ops/test_integer_ops integer_* quick_*
4 tdim: FAIL: Thread Dimensions,Timeout,timeout,,800,thread_dimensions/test_thread_dimensions quick*
5 math-a: FAILED 34 of 54 tests; 0xffffdead count 3 -> FAIL (stale-buffer marker present). Failing: asin asinh asinpi atan atanh atanpi atan2 atan2pi ceil cos cospi exp exp2 exp10 expm1 fabs fdim fmax fmin fmod hypot isequal isgreaterequal isinf isless islessequal islessgreater ldexp lgamma log log10 divide assignment erfc. First ERROR lines are in chunk-math-a.txt; one with marker: ERROR: atan28: -nan ulp error at {-0x1.1b4b9ep+61 (0xde0da5cf), 0x1.3393a4p-1 (0x3f19c9d2)}: *-0x1.921fb6p+0 vs. -nan (0xffffdead) at index: 0
  math-b: no PASSED/FAILED line; 0xffffdead count 0; only ERROR line: "ERROR: The argument 'recip' did not match any test names." CHUNK-RC 1 (suite did not run).
6 reg: PASS, all 19 rows Pass (rows in files/reg/binaries.csv; Workgroups and Subgroups rows have empty detail).
7 img3d: NOT FINISHED (data): Images (Kernel 3D int),Timeout,timeout,,800,images/kernel_read_write/test_image_streams CL_FILTER_NEAREST int 3D ; chunk has ROUND-DONE.
8 dmesg: dmesg-intops.txt 39 hits, all "Soft-stop failed" (FAIL); others 0. Examples: DMESG: [  931.104542] panfrost 1800000.gpu: Soft-stop failed / [  931.708701] / [  932.316573] (roughly every 0.6 s through 954.2 s); full list in dmesg-intops.txt.
9 CHUNK-RC: intops 0, tdim 0, reg 0, img3d 0, math-a 1, math-b 1 (all with ROUND-DONE); stress without ROUND-DONE.
Stress VK lines rc=124 (copied):
VK 1 dEQP-VK.spirv_assembly.type.vec4.i8.bit_field_insert_offset16_count64_frag rc=124 t=200s result=[] msg=[]
VK 1 dEQP-VK.spirv_assembly.type.vec4.u64.bit_field_insert_offset8_count64_frag rc=124 t=200s result=[] msg=[]
Results: harness/research/opencl-fixes/logs/runner-timeout-fix/
