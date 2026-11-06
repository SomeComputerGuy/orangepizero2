# Summary job 67-kbase-traces5 (TEST)
Kernel (uname -v): #51 SMP PREEMPT Fri Nov 6 20:28:54 UTC 2026 (c48 trial); stock restored. Run ~22:0x-22:30 on 2026-11-06. Exit 0.
Results: harness/research/arm-blob/traces/runner-j67 (git-ignored)
State: load info fb probe trace unload bind. runner.log STALL/ssh rc/UNREACHABLE: none (grep found none).
SPL count 2 (no reset). Output of --check follows (all PASS, no FAIL):
```
PASS kernel: kernel: #51 SMP PREEMPT Fri Nov  6 20:28:54 UTC 2026
PASS BTF fix bd60a159b in the kernel
PASS panfrost unbound
PASS insmod rc 0
PASS no BTF lines in dmesg after insmod
PASS /dev/mali0 present
PASS /sys/kernel/btf/bifrost_kbase present
PASS kbase probed: DMESG: [   75.426922] mali 1800000.gpu: Kernel DDK version g25p0-00eac0 DMESG: [   75.428021] mali 1800000.gpu: sunxi glue: reset deasserted, 2 clocks, 1 regulators, core clk 456000000 Hz 
PASS load: no 'IRQ ... not found' lines
PASS load: no WARNING/Call trace in dmesg-load.txt
PASS step fb finished
INFO fb: FBMODE tex8 rc 0 faults 2 [fb mode tex8, status 0x8cd5] basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO fb: FBMODE rgba16f rc 0 faults 0 [fb mode rgba16f, status 0x8cd5] basic: lit pixels 1352/4096, hash d9ef01c0, px(16,16)=b41932 px(48,40)=000000, glError 0x0
INFO fb: FBMODE rgba32f rc 0 faults 0 [fb mode rgba32f, status 0x8cd5] basic: lit pixels 1352/4096, hash d9ef01c0, px(16,16)=b41932 px(48,40)=000000, glError 0x0
PASS fb: SELECTED rgba16f renders
PASS fb: 2 float mode(s) without DATA_INVALID faults
INFO probe FBMODE rgba16f
PASS probe ran with a float framebuffer (fb mode rgba16f, status 0x8cd5)
PASS step probe finished
PASS gles32probe (probe) rc 0
PASS files/probe/info.txt complete
PASS files/probe/basic.rgba
PASS files/probe/gs_pass.rgba
PASS files/probe/gs_amp.rgba
PASS files/probe/gs_inv.rgba
PASS files/probe/tess_tri.rgba
PASS files/probe/tess_gs.rgba
PASS files/probe/tess_quad.rgba
PASS files/probe/gs_xfb.rgba
PASS files/probe/gs_layer0.rgba
PASS files/probe/gs_layer1.rgba
PASS files/probe/basic.progbin
PASS files/probe/gs_pass.progbin
PASS files/probe/gs_amp.progbin
PASS files/probe/gs_inv.progbin
PASS files/probe/tess_tri.progbin
PASS files/probe/tess_gs.progbin
PASS files/probe/tess_quad.progbin
PASS files/probe/gs_xfb.progbin
PASS files/probe/gs_layer.progbin
PASS dmesg-probe.txt: no fault/oops lines
INFO trace FBMODE rgba16f
PASS trace ran with a float framebuffer (fb mode rgba16f, status 0x8cd5)
PASS step trace finished
PASS gles32probe (trace) rc 0
PASS files/trace/info.txt complete
PASS files/trace/basic.rgba
PASS files/trace/gs_pass.rgba
PASS files/trace/gs_amp.rgba
PASS files/trace/gs_inv.rgba
PASS files/trace/tess_tri.rgba
PASS files/trace/tess_gs.rgba
PASS files/trace/tess_quad.rgba
PASS files/trace/gs_xfb.rgba
PASS files/trace/gs_layer0.rgba
PASS files/trace/gs_layer1.rgba
PASS files/trace/basic.progbin
PASS files/trace/gs_pass.progbin
PASS files/trace/gs_amp.progbin
PASS files/trace/gs_inv.progbin
PASS files/trace/tess_tri.progbin
PASS files/trace/tess_gs.progbin
PASS files/trace/tess_quad.progbin
PASS files/trace/gs_xfb.progbin
PASS files/trace/gs_layer.progbin
PASS dmesg-trace.txt: no fault/oops lines
PASS files/trace/kbtrace.bin 6085825 bytes
PASS decoded: 18 submits, index.txt 709 lines
INFO probe case: basic: lit pixels 1352/4096, hash d9ef01c0, px(16,16)=b41932 px(48,40)=000000, glError 0x0
INFO probe case: gs_pass: lit pixels 1058/4096, hash 77ea2120, px(16,16)=2ac015 px(48,40)=000000, glError 0x0
INFO probe case: gs_amp: lit pixels 360/4096, hash e4d2c8aa, px(16,16)=000000 px(48,40)=ff8040, glError 0x0
INFO probe case: gs_inv: lit pixels 800/4096, hash e819c560, px(16,16)=0e1121 px(48,40)=687522, glError 0x0
INFO probe case: tess_tri: lit pixels 1152/4096, hash a0abac3a, px(16,16)=ba172e px(48,40)=000000, glError 0x0
INFO probe case: tess_gs: lit pixels 802/4096, hash a29579da, px(16,16)=000000 px(48,40)=000000, glError 0x0
INFO probe case: tess_quad: lit pixels 2028/4096, hash 1371e7fa, px(16,16)=b61732 px(48,40)=1442aa, glError 0x0
INFO probe case: gs_xfb: lit pixels 592/4096, hash ecaf0021, px(16,16)=000000 px(48,40)=000000, glError 0x0
INFO probe case: gs_layer0: lit pixels 1352/4096, hash d9ef01c0, px(16,16)=b41932 px(48,40)=000000, glError 0x0
INFO probe case: gs_layer1: lit pixels 1352/4096, hash e21e86e0, px(16,16)=3219b4 px(48,40)=000000, glError 0x0
PASS probe: basic case rendered (basic: lit pixels 1352/4096, hash d9ef01c0, px(16,16)=b41932 px(48,40)=000000, glError 0x0)
PASS trace: basic case rendered (basic: lit pixels 1352/4096, hash d9ef01c0, px(16,16)=b41932 px(48,40)=000000, glError 0x0)
PASS stock kernel restored, panfrost renderD128 back
PASS trace memory captured: 18 submit files decode a fragment job
INFO rt: fragment RT format by job status (count status format):      20 0x0 Tiled;
PASS trace: no AFBC render target in the decoded submits
INFO jit: JIT_ALLOC id 1 bin 1 max_alloc 0 flags 0x0 usage 1 gpu_alloc_addr 0x1afe39580 va_pages 0x5000 commit_pages 0x40 extension 0x20 heap_info 0x0
INFO jit: JIT_ALLOC id 5 bin 3 max_alloc 0 flags 0x0 usage 1 gpu_alloc_addr 0x1afe3cc00 va_pages 0x800 commit_pages 0x40 extension 0x20 heap_info 0x0
INFO jit: JIT_ALLOC id 6 bin 2 max_alloc 0 flags 0x0 usage 2 gpu_alloc_addr 0x1afe3d080 va_pages 0x800 commit_pages 0x1 extension 0x4 heap_info 0x0
INFO jit: JIT_ALLOC id 2 bin 1 max_alloc 0 flags 0x0 usage 1 gpu_alloc_addr 0x1afe39580 va_pages 0x5000 commit_pages 0x40 extension 0x20 heap_info 0x0
INFO jitaddr: 227 JITADDR id 1 *0x1afe39580 = 0x1b0000000
INFO jitaddr: 250 JITADDR id 5 *0x1afe3cc00 = 0x1b5000000
INFO jitaddr: 250 JITADDR id 6 *0x1afe3d080 = 0x1b5800000
INFO jitaddr: 293 JITADDR id 2 *0x1afe39580 = 0x1b0000000
INFO jitaddr: 314 JITADDR id 3 *0x1afe3ce80 = 0x1b0000000
INFO jitaddr: 314 JITADDR id 4 *0x1afe3d300 = 0x1b6000000
PASS unload: rmmod rc 0, step finished
PASS unload: glue term ran (sunxi glue: reset asserted, clocks + supply off, runtime PM suspended (usage count 1))
INFO unload BEFORE-RMMOD
INFO unload PM: status=active usage= driver=mali
INFO unload GENPD: GPU                             on                              0
INFO unload GENPD:     1800000.gpu                     active                      0           SW
INFO unload CLK:     pll-gpu                          1       1        0        456000000   0          0     50000      Y      deviceless                      no_connection_id         
INFO unload CLK:        gpu0                          1       2        0        456000000   0          0     50000      Y         1800000.gpu                     no_connection_id         
INFO unload CLK:                                                                                                                  gpu@1800000                     no_connection_id         
INFO unload CLK:           bus-gpu                    1       2        0        200000000   0          0     50000      Y            gpu@1800000                     no_connection_id         
INFO unload CLK:           gpu1                       1       1        0        400000000   0          0     50000      Y            deviceless                      no_connection_id         
INFO unload AFTER-RMMOD
INFO unload PM: status=unsupported usage= driver=
INFO unload GENPD: GPU                             off-0                           0
INFO unload CLK:     pll-gpu                          0       0        0        456000000   0          0     50000      N      deviceless                      no_connection_id         
INFO unload CLK:        gpu0                          0       0        0        456000000   0          0     50000      N         deviceless                      no_connection_id         
INFO unload CLK:           bus-gpu                    0       0        0        200000000   0          0     50000      N            deviceless                      no_connection_id         
INFO unload CLK:           gpu1                       1       1        0        400000000   0          0     50000      Y            deviceless                      no_connection_id         
PASS unload: no WARNING/unbalanced lines (kbase.ko v4)
INFO unload DMESG: [  128.060268] mali 1800000.gpu: kbase_device_runtime_disable: Device runtime usage count unexpectedly non zero 1
INFO unload DMESG: [  128.060350] mali 1800000.gpu: sunxi glue: reset asserted, clocks + supply off, runtime PM suspended (usage count 1)
PASS bind: panfrost rebound, renderD128 present, step finished
INFO bind BEFORE-BIND
INFO bind PM: status=unsupported usage= driver=
INFO bind GENPD: GPU                             off-0                           0
INFO bind CLK:     pll-gpu                          0       0        0        456000000   0          0     50000      N      deviceless                      no_connection_id         
INFO bind CLK:        gpu0                          0       0        0        456000000   0          0     50000      N         deviceless                      no_connection_id         
INFO bind CLK:           bus-gpu                    0       0        0        200000000   0          0     50000      N            deviceless                      no_connection_id         
INFO bind CLK:           gpu1                       1       1        0        400000000   0          0     50000      Y            deviceless                      no_connection_id         
INFO bind AFTER-BIND
INFO bind PM: status=active usage= driver=panfrost
INFO bind GENPD: GPU                             on                              0
INFO bind GENPD:     1800000.gpu                     active                      0           SW
INFO bind CLK:     pll-gpu                          1       1        0        306000000   0          0     50000      Y      deviceless                      no_connection_id         
INFO bind CLK:        gpu0                          1       1        0        306000000   0          0     50000      Y         1800000.gpu                     no_connection_id         
INFO bind CLK:                                                                                                                  1800000.gpu                     no_connection_id         
INFO bind CLK:           bus-gpu                    1       1        0        200000000   0          0     50000      Y            1800000.gpu                     bus                      
INFO bind CLK:           gpu1                       1       1        0        400000000   0          0     50000      Y            deviceless                      no_connection_id         
INFO bind DMESG: [  141.150117] panfrost 1800000.gpu: clock rate = 456000000
INFO bind DMESG: [  141.150172] panfrost 1800000.gpu: bus_clock rate = 200000000
INFO bind DMESG: [  141.152288] panfrost 1800000.gpu: mali-g31 id 0x7093 major 0x0 minor 0x0 status 0x0
INFO bind DMESG: [  141.152336] panfrost 1800000.gpu: features: 00000000,000027f7, issues: 00000000,00000400
INFO bind DMESG: [  141.152352] panfrost 1800000.gpu: Features: L2:0x07100206 Shader:0x00000000 Tiler:0x00000209 Mem:0x1 MMU:0x00002821 AS:0xff JS:0x7
INFO bind DMESG: [  141.152372] panfrost 1800000.gpu: shader_present=0x1 l2_present=0x1
INFO bind DMESG: [  141.156763] [drm] Initialized panfrost 1.6.0 for 1800000.gpu on minor 1
INFO serial: U-Boot SPL count 2 (expected 2: trial-kernel boot + restore reboot; more = a reset)
INFO serial [22:26:30.434] ]3008;end=5588c268c41844d2b9d4ce9060edeae7\systemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument
INFO serial [22:26:30.935] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [22:26:32.944] WDT:   Not starting watchdog@30090a0
INFO serial [22:29:23.393] ]3008;end=693145a4f2424ef89d8a5da34342bb3d\systemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument
INFO serial [22:29:23.393] [0;39msystemd-shutdown[1]: Using hardware watchdog /dev/watchdog0: 'sunxi-wdt', version 0.[0m
INFO serial [22:29:23.393] [0;31msystemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument[0m
INFO serial [22:29:24.399] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [22:29:25.903] WDT:   Not starting watchdog@30090a0
state: load info fb probe trace unload bind 
```
probe KCTX-SAMPLES 3; kctx lines: atoms 3, jitstats 12, mem_allocs 69, mem_zones 3. kbtrace.bin 6085825 bytes, 18 submits.
Missing files: none. dmesg abnormal: only 'kbase_device_runtime_disable: Device runtime usage count unexpectedly non zero 1' at unload.
