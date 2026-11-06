# 28-panfrost-softstop2: FAIL overall (stress/vk/vklong/intops/reg PASS; tdim PACKAGE-BUG; math-a/b MESA-RACE; img3d NOT FINISHED with a GPU page fault)
Kernel: `kernel: #25 SMP PREEMPT Fri Nov  6 04:18:02 UTC 2026` (c27); "kernel fix: present (panfrost.ko md5 72221f173987f7e1bcc8cd1322bb80ac)". Start 05:20:03 chunks, end 06:14:42. Exit 0, 9 of 9 chunks, every chunk ends ROUND-DONE, no OOPS, no LEFTOVER/CUT-OFF/TRACE-OFF lines.
State: stress vk vklong intops tdim math-a math-b reg img3d
## Check 2 dmesg bad-pattern count and TRACE TIMEDOUT per chunk
stress 0 / TIMEDOUT 101; vk 0 / 10; vklong 0 / 2; intops 0 / 3; tdim 0 / 0; math-a 0 / 0; math-b 0 / 0; reg 0 / 0; img3d 2 (FAIL) / 0.
img3d lines:
- [ 2471.234574] panfrost 1800000.gpu: Unhandled Page fault in AS0 at VA 0x000000000B2F8000
- [ 2471.234656] panfrost 1800000.gpu: js fault, js=1, status=JOB_BUS_FAULT, head=0xa09f200, tail=0xa09f200
## Check 3 stress: PASS. INTOPS 1: PASSED 2 of 2 tests. t=28s; INTOPS 2: PASSED 2 of 2 tests. t=22s; TDIM: PASSED test. t=154s
## Check 4 vk: PASS (10 lines rc=0, Pass): case1 i8.clamp_frag t=6s/4s; u32.bit_field_insert_offset16_count16 t=4s/4s; i16 offset8_count16 4s/4s; u16 offset8_count16 4s/4s; i64.bit_field_u_extract_offset8_count16 4s/4s (run1/run2)
## Check 5 vklong: PASS. i8.bit_field_insert_offset16_count64_frag rc=0 t=4s Pass; u64.bit_field_insert_offset8_count64_frag rc=0 t=5s Pass. TIMEDOUT 2, dmesg count 0
## Check 6 intops: PASS: Integer Ops,Pass,0,PASSED 59 of 59 tests.,669,integer_ops/test_integer_ops integer_* quick_*
## Check 7 tdim: PACKAGE-BUG: "TDIM: ERROR: The argument 'quick_2d' did not match any test names." and "TDIM-RC 1" (quick_2d/quick_3d not passed)
## Check 8 math
- math-a: FAILED 32 of 54 tests. S=9 stale-buffer lines, T=0 -> MESA-RACE. Failing: acosh asin asinh asinpi atan atanpi atan2 atan2pi cbrt cos cospi exp exp2 exp10 expm1 fabs floor hypot isequal isfinite isgreater isgreaterequal isinf islessequal isordered isunordered ldexp lgamma log log10 add erf
- math-b: FAILED 19 of 34 tests. S=7, T=0 -> MESA-RACE. Failing: log2 maxmag minmag pow pown powr remainder rootn signbit sin sinh sinpi tan tanh tanpi tgamma half_recip subtract not
- First ERROR lines math-a: acosh nan ulp error at 0x1p-7; asin -4503599627370496.000000 ulp error at -0x1p-79; asinh 1099494850560.000000 ulp error at 0x1p-123; asinpi nan ulp error at 0x1p-11; atan -1093821333504.000000 at -0x1p-19; atanpi2 -nan ulp error at -0x1p+101; atan28 79.367012, -582.797791, -268.416260, -608.198425 ulp errors.
- First ERROR lines math-b: log2 4194304.000000 at 0x1p+33; log2 8388608.000000 at 0x1p-19; maxmag2 1115.962036; ThreadPool_Do: TestHalf failed (x3); minmag3 1639.785156; pow2 -nan ... (0xffffdead) at index: 106504; pow4 nan; pown3 -1273856.000000.
## Check 9 reg: PASS, all 19 suites Pass (Workgroups and Subgroups Pass with empty result text)
## Check 10 img3d: NOT FINISHED: Images (Kernel 3D int),Timeout,timeout,,800,images/kernel_read_write/test_image_streams CL_FILTER_NEAREST int 3D; TIMEDOUT 0; plus the Page fault / js fault lines above (check 2 FAIL)
Results: harness/research/opencl-fixes/logs/runner-softstop2/ (runner.log, chunk-*.txt, dmesg-*.txt, trace-*.txt, files/)
