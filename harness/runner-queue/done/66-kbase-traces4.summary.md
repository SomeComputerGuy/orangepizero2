# Job 66-kbase-traces4 summary
Kernel (trial): #51 SMP PREEMPT Fri Nov 6 20:28:54 UTC 2026 (c48); restored stock #17 7.3.1-edge-sunxi64
Run 2026-11-06 21:50:46 - 21:55:37 UTC. Results: harness/research/arm-blob/traces/runner-j66/. State: load info afbc probe trace unload bind. STALL/ssh rc/UNREACHABLE: none. SPL count 2 (no reset).
Checks FAIL: 9 (no render, all 10 cases 0 lit, v0-v3 all 0/4096 glError 0x505), 11 (39 fault lines in dmesg-probe and dmesg-trace), 17 (SELECTED v3 none-rendered), 18 (40 AFBC render targets in decoded submits). Rest PASS.

## Full --check output
```
PASS kernel: kernel: #51 SMP PREEMPT Fri Nov  6 20:28:54 UTC 2026
PASS BTF fix bd60a159b in the kernel
PASS panfrost unbound
PASS insmod rc 0
PASS no BTF lines in dmesg after insmod
PASS /dev/mali0 present
PASS /sys/kernel/btf/bifrost_kbase present
PASS kbase probed: DMESG: [   84.097206] mali 1800000.gpu: Kernel DDK version g25p0-00eac0 DMESG: [   84.098288] mali 1800000.gpu: sunxi glue: reset deasserted, 2 clocks, 1 regulators, core clk 456000000 Hz 
PASS load: no 'IRQ ... not found' lines
PASS load: no WARNING/Call trace in dmesg-load.txt
PASS step afbc finished
INFO afbc: VARIANT v0 rc 0 faults 2 cfg [] basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO afbc: VARIANT v1 rc 0 faults 2 cfg [GLES_DISABLE_TEXTURE_AFBC=1 GLES_DISABLE_SURFACE_AFBC=1 ] basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO afbc: VARIANT v2 rc 0 faults 2 cfg [GLES_DISABLE_TEXTURE_AFBC=1 GLES_DISABLE_SURFACE_AFBC=1 GLES_DISABLE_CRC=1 ] basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO afbc: VARIANT v3 rc 0 faults 2 cfg [GLES_DISABLE_TEXTURE_AFBC=1 GLES_DISABLE_SURFACE_AFBC=1 GLES_DISABLE_CRC=1 GLES_FORCE_LINEAR_LAYOUT_UNCOMPRESSED_TEXTURE=1 ] basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO afbc BLOB: [   99.584084] (gles32probe) Successfully parsed 0 environment variable(s) from /root/armblob/cfg/v0.config.
INFO afbc BLOB: [   99.584292] (gles32probe) Successfully parsed 0 environment variable(s) from /root/armblob/cfg/v0.config.
INFO afbc BLOB: [   99.585084] (gles32probe) Successfully parsed 0 environment variable(s) from /root/armblob/cfg/v0.config.
INFO afbc BLOB: [   99.834361] (gles32probe) Successfully parsed 2 environment variable(s) from /root/armblob/cfg/v1.config.
INFO afbc BLOB: [   99.834592] (gles32probe) Successfully parsed 2 environment variable(s) from /root/armblob/cfg/v1.config.
INFO afbc BLOB: [   99.835354] (gles32probe) Successfully parsed 2 environment variable(s) from /root/armblob/cfg/v1.config.
INFO afbc BLOB: [  100.083907] (gles32probe) Successfully parsed 3 environment variable(s) from /root/armblob/cfg/v2.config.
INFO afbc BLOB: [  100.084135] (gles32probe) Successfully parsed 3 environment variable(s) from /root/armblob/cfg/v2.config.
FAIL afbc: no variant rendered (SELECTED v3 none-rendered)
INFO probe blob CONFIG v3
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
FAIL dmesg-probe.txt fault/oops lines: 39
DMESG: [  109.971307] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [  109.971432] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [  109.972798] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [  109.972822] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [  110.089990] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
INFO trace blob CONFIG v3
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
FAIL dmesg-trace.txt fault/oops lines: 39
DMESG: [  119.887464] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [  119.887548] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [  119.928975] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [  119.929056] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [  120.162014] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
PASS files/trace/kbtrace.bin 5923257 bytes
PASS decoded: 46 submits, index.txt 826 lines
INFO probe case: basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: gs_pass: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: gs_amp: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: gs_inv: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: tess_tri: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: tess_gs: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: tess_quad: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: gs_xfb: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: gs_layer0: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505
INFO probe case: gs_layer1: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x0
FAIL probe: basic case did not render (basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505)
FAIL trace: basic case did not render (basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505)
PASS stock kernel restored, panfrost renderD128 back
PASS trace memory captured: 46 submit files decode a fragment job
INFO rt: fragment RT format by job status (count status format):      22 0x0 AFBC;     18 0x0 Linear;     10 0x0 Tiled;     18 0x1 Linear;     18 0x20258 AFBC;
FAIL trace: AFBC render targets in the decoded submits: 40
INFO post: 232 POST atom 2 jc 0x1afe38900 exception_status 0x1 first_incomplete 0x0 fault_ptr 0xa92501dd ctrl 0x00010009 next 0x00000001afe39100 (fault_ptr not in a captured region)
INFO post: 232 POST atom 3 jc 0x1afe39900 exception_status 0x1 first_incomplete 0x0 fault_ptr 0xa92501dd ctrl 0x00010013 next 0x00000001afe39240 (fault_ptr not in a captured region)
INFO post: 254 POST atom 2 jc 0x1afe3bf80 exception_status 0x1 first_incomplete 0x0 fault_ptr 0xa92501dd ctrl 0x00010009 next 0x00000001afe3c780 (fault_ptr not in a captured region)
INFO post: 254 POST atom 3 jc 0x1afe3cf80 exception_status 0x1 first_incomplete 0x0 fault_ptr 0xa92501dd ctrl 0x00010013 next 0x00000001afe3c8c0 (fault_ptr not in a captured region)
INFO post: 314 POST atom 2 jc 0x1afe38900 exception_status 0x1 first_incomplete 0x0 fault_ptr 0xa92501dd ctrl 0x00010009 next 0x00000001afe39100 (fault_ptr not in a captured region)
INFO post: 314 POST atom 3 jc 0x1afe39900 exception_status 0x1 first_incomplete 0x0 fault_ptr 0xa92501dd ctrl 0x00010013 next 0x00000001afe39240 (fault_ptr not in a captured region)
INFO post: 333 POST atom 2 jc 0x1afe3c200 exception_status 0x1 first_incomplete 0x0 fault_ptr 0xa92501dd ctrl 0x00010009 next 0x00000001afe3ca00 (fault_ptr not in a captured region)
INFO post: 333 POST atom 3 jc 0x1afe3d200 exception_status 0x1 first_incomplete 0x0 fault_ptr 0xa92501dd ctrl 0x00010013 next 0x00000001afe3cb40 (fault_ptr not in a captured region)
INFO jit: JIT_ALLOC id 1 bin 1 max_alloc 0 flags 0x0 usage 1 gpu_alloc_addr 0x1afe38580 va_pages 0x5000 commit_pages 0x40 extension 0x20 heap_info 0x0
INFO jit: JIT_ALLOC id 5 bin 3 max_alloc 0 flags 0x0 usage 1 gpu_alloc_addr 0x1afe3bc00 va_pages 0x800 commit_pages 0x40 extension 0x20 heap_info 0x0
INFO jit: JIT_ALLOC id 6 bin 2 max_alloc 0 flags 0x0 usage 2 gpu_alloc_addr 0x1afe3c680 va_pages 0x800 commit_pages 0x1 extension 0x4 heap_info 0x0
INFO jit: JIT_ALLOC id 2 bin 1 max_alloc 0 flags 0x0 usage 1 gpu_alloc_addr 0x1afe38580 va_pages 0x5000 commit_pages 0x40 extension 0x20 heap_info 0x0
INFO jitaddr: 229 JITADDR id 1 *0x1afe38580 = 0x1b0000000
INFO jitaddr: 251 JITADDR id 5 *0x1afe3bc00 = 0x1b5000000
INFO jitaddr: 251 JITADDR id 6 *0x1afe3c680 = 0x1b5800000
INFO jitaddr: 311 JITADDR id 2 *0x1afe38580 = 0x1b0000000
INFO jitaddr: 330 JITADDR id 3 *0x1afe3be80 = 0x1b0000000
INFO jitaddr: 330 JITADDR id 4 *0x1afe3c900 = 0x1b6000000
INFO diag: DMESG: [  109.971262] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe39240 tail 0x1afe39240
INFO diag: DMESG: [  109.972763] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe3c8c0 tail 0x1afe3c8c0
INFO diag: DMESG: [  110.089957] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe39240 tail 0x1afe39240
INFO diag: DMESG: [  110.091406] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe3cb40 tail 0x1afe3cb40
INFO diag: DMESG: [  119.887441] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe39240 tail 0x1afe39240
INFO diag: DMESG: [  119.928938] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe3c8c0 tail 0x1afe3c8c0
INFO diag: DMESG: [  120.161979] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe39240 tail 0x1afe39240
INFO diag: DMESG: [  120.371067] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe3cb40 tail 0x1afe3cb40
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
INFO unload DMESG: [  135.705150] mali 1800000.gpu: kbase_device_runtime_disable: Device runtime usage count unexpectedly non zero 1
INFO unload DMESG: [  135.705231] mali 1800000.gpu: sunxi glue: reset asserted, clocks + supply off, runtime PM suspended (usage count 1)
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
INFO bind DMESG: [  148.379755] panfrost 1800000.gpu: clock rate = 456000000
INFO bind DMESG: [  148.379810] panfrost 1800000.gpu: bus_clock rate = 200000000
INFO bind DMESG: [  148.382112] panfrost 1800000.gpu: mali-g31 id 0x7093 major 0x0 minor 0x0 status 0x0
INFO bind DMESG: [  148.382161] panfrost 1800000.gpu: features: 00000000,000027f7, issues: 00000000,00000400
INFO bind DMESG: [  148.382176] panfrost 1800000.gpu: Features: L2:0x07100206 Shader:0x00000000 Tiler:0x00000209 Mem:0x1 MMU:0x00002821 AS:0xff JS:0x7
INFO bind DMESG: [  148.382196] panfrost 1800000.gpu: shader_present=0x1 l2_present=0x1
INFO bind DMESG: [  148.384412] [drm] Initialized panfrost 1.6.0 for 1800000.gpu on minor 1
INFO serial: U-Boot SPL count 2 (expected 2: trial-kernel boot + restore reboot; more = a reset)
INFO serial [21:51:54.990] ]3008;end=e453522673414eeab962c2430d5f349e\systemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument
INFO serial [21:51:55.994] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [21:51:57.497] WDT:   Not starting watchdog@30090a0
INFO serial [21:54:58.805] ]3008;end=31c531f971dc414389e4f0ab77bc9e20\systemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument
INFO serial [21:54:58.805] [0;39msystemd-shutdown[1]: Using hardware watchdog /dev/watchdog0: 'sunxi-wdt', version 0.[0m
INFO serial [21:54:58.805] [0;31msystemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument[0m
INFO serial [21:54:59.306] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [21:55:01.314] WDT:   Not starting watchdog@30090a0
state: load info afbc probe trace unload bind 
```
