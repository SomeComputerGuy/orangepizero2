# Job 65-kbase-traces3 summary
Start 2026-11-06 21:33 UTC, end 21:38 UTC. Board restored on stock kernel: vmlinuz-7.3.1-edge-sunxi64 #17 (renderD128 present).
Trial kernel: #51 SMP PREEMPT Fri Nov 6 20:28:54 UTC 2026 (c48).

## Checks (kbase-traces.sh --check, verbatim)
PASS kernel: kernel: #51 SMP PREEMPT Fri Nov  6 20:28:54 UTC 2026
PASS BTF fix bd60a159b in the kernel
PASS panfrost unbound
PASS insmod rc 0
PASS no BTF lines in dmesg after insmod
PASS /dev/mali0 present
PASS /sys/kernel/btf/bifrost_kbase present
PASS kbase probed: DMESG: [   70.569487] mali 1800000.gpu: Kernel DDK version g25p0-00eac0 DMESG: [   70.570609] mali 1800000.gpu: sunxi glue: reset deasserted, 2 clocks, 1 regulators, core clk 456000000 Hz 
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
FAIL dmesg-probe.txt fault/oops lines: 31
DMESG: [   86.213417] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   86.214938] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   86.330426] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   86.332364] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   86.416437] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
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
DMESG: [   96.438441] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   96.438469] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   96.479809] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   96.479888] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   96.713155] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
PASS files/trace/kbtrace.bin 5919025 bytes
PASS decoded: 46 submits, index.txt 824 lines
FAIL probe: basic case did not render (basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505)
FAIL trace: basic case did not render (basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505)
PASS stock kernel restored, panfrost renderD128 back
PASS trace memory captured: 46 submit files decode a fragment job
INFO post: 232 POST atom 2 jc 0x1afe38900 exception_status 0x1 first_incomplete 0x0 fault_ptr 0x872aec5d ctrl 0x00010009 next 0x00000001afe39100 (fault_ptr not in a captured region)
INFO post: 232 POST atom 3 jc 0x1afe39900 exception_status 0x1 first_incomplete 0x0 fault_ptr 0x872aec5d ctrl 0x00010013 next 0x00000001afe39240 (fault_ptr not in a captured region)
INFO post: 254 POST atom 2 jc 0x1afe3bf80 exception_status 0x1 first_incomplete 0x0 fault_ptr 0x872aec5d ctrl 0x00010009 next 0x00000001afe3c780 (fault_ptr not in a captured region)
INFO post: 254 POST atom 3 jc 0x1afe3cf80 exception_status 0x1 first_incomplete 0x0 fault_ptr 0x872aec5d ctrl 0x00010013 next 0x00000001afe3c8c0 (fault_ptr not in a captured region)
INFO post: 314 POST atom 2 jc 0x1afe38900 exception_status 0x1 first_incomplete 0x0 fault_ptr 0x872aec5d ctrl 0x00010009 next 0x00000001afe39100 (fault_ptr not in a captured region)
INFO post: 314 POST atom 3 jc 0x1afe39900 exception_status 0x1 first_incomplete 0x0 fault_ptr 0x872aec5d ctrl 0x00010013 next 0x00000001afe39240 (fault_ptr not in a captured region)
INFO post: 333 POST atom 2 jc 0x1afe3c200 exception_status 0x1 first_incomplete 0x0 fault_ptr 0x872aec5d ctrl 0x00010009 next 0x00000001afe3ca00 (fault_ptr not in a captured region)
INFO post: 333 POST atom 3 jc 0x1afe3d200 exception_status 0x1 first_incomplete 0x0 fault_ptr 0x872aec5d ctrl 0x00010013 next 0x00000001afe3cb40 (fault_ptr not in a captured region)
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
INFO diag: DMESG: [   86.213379] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe39240 tail 0x1afe39240
INFO diag: DMESG: [   86.214902] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe3c8c0 tail 0x1afe3c8c0
INFO diag: DMESG: [   86.330391] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe39240 tail 0x1afe39240
INFO diag: DMESG: [   86.332328] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe3cb40 tail 0x1afe3cb40
INFO diag: DMESG: [   96.438421] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe39240 tail 0x1afe39240
INFO diag: DMESG: [   96.479771] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe3c8c0 tail 0x1afe3c8c0
INFO diag: DMESG: [   96.713120] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe39240 tail 0x1afe39240
INFO diag: DMESG: [   96.921781] mali 1800000.gpu: sunxi diag: slot 0 status 0x58 head 0x1afe3cb40 tail 0x1afe3cb40
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
INFO unload DMESG: [  112.711355] mali 1800000.gpu: kbase_device_runtime_disable: Device runtime usage count unexpectedly non zero 1
INFO unload DMESG: [  112.711502] WARNING: drivers/regulator/core.c:3262 at _regulator_disable+0x10c/0x258, CPU#3: rmmod/7671
INFO unload DMESG: [  112.734821] Modules linked in: bifrost_kbase(O-) bnep hci_uart btqca btrtl btbcm btintel bluetooth ecdh_generic ecc sprdwl_ng cfg80211 sunrpc snd_soc_hdmi_codec sun50i_h6_prcm_ppu dw_hdmi_cec dw_hdmi_i2s_audio sunxi musb_hdrc phy_generic dwmac_sun8i panfrost sun8i_ce gpu_sched sun50i_di300 sun50i_g2d crypto_engine drm_shmem_helper display_connector zram 842_decompress 842_com
INFO unload DMESG: [  112.860929] Call trace:
INFO unload DMESG: [  112.942668] WARNING: platform/devicetree/mali_kbase_runtime_pm.c:75 at disable_gpu_power_control+0xc0/0xe0 [bifrost_kbase], CPU#3: rmmod/7671
INFO unload DMESG: [  112.957545] Modules linked in: bifrost_kbase(O-) bnep hci_uart btqca btrtl btbcm btintel bluetooth ecdh_generic ecc sprdwl_ng cfg80211 sunrpc snd_soc_hdmi_codec sun50i_h6_prcm_ppu dw_hdmi_cec dw_hdmi_i2s_audio sunxi musb_hdrc phy_generic dwmac_sun8i panfrost sun8i_ce gpu_sched sun50i_di300 sun50i_g2d crypto_engine drm_shmem_helper display_connector zram 842_decompress 842_com
INFO unload DMESG: [  113.087438] Call trace:
INFO unload DMESG: [  113.163424] mali 1800000.gpu: sunxi glue: reset asserted, clocks + supply off, runtime PM suspended (usage count 1)
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
INFO bind DMESG: [  125.716579] panfrost 1800000.gpu: clock rate = 456000000
INFO bind DMESG: [  125.716632] panfrost 1800000.gpu: bus_clock rate = 200000000
INFO bind DMESG: [  125.718592] panfrost 1800000.gpu: mali-g31 id 0x7093 major 0x0 minor 0x0 status 0x0
INFO bind DMESG: [  125.718638] panfrost 1800000.gpu: features: 00000000,000027f7, issues: 00000000,00000400
INFO bind DMESG: [  125.718653] panfrost 1800000.gpu: Features: L2:0x07100206 Shader:0x00000000 Tiler:0x00000209 Mem:0x1 MMU:0x00002821 AS:0xff JS:0x7
INFO bind DMESG: [  125.718672] panfrost 1800000.gpu: shader_present=0x1 l2_present=0x1
INFO bind DMESG: [  125.721170] [drm] Initialized panfrost 1.6.0 for 1800000.gpu on minor 1
INFO serial: U-Boot SPL count 2 (expected 2: trial-kernel boot + restore reboot; more = a reset)
INFO serial [21:34:47.695] ]3008;end=0e3d7d8f0ad94cb385b36c8d26e18584\systemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument
INFO serial [21:34:48.697] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [21:34:50.203] WDT:   Not starting watchdog@30090a0
INFO serial [21:36:48.704] WARNING: drivers/regulator/core.c:3262 at _regulator_disable+0x10c/0x258, CPU#3: rmmod/7671
INFO serial [21:36:48.704] Call trace:
INFO serial [21:36:49.205] WARNING: platform/devicetree/mali_kbase_runtime_pm.c:75 at disable_gpu_power_control+0xc0/0xe0 [bifrost_kbase], CPU#3: rmmod/7671
INFO serial [21:36:49.205] Call trace:
INFO serial [21:37:26.375] ]3008;end=3aa370a187c24e598ec49ce7ae8d62ac\systemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument
INFO serial [21:37:26.375] [0;39msystemd-shutdown[1]: Using hardware watchdog /dev/watchdog0: 'sunxi-wdt', version 0.[0m
INFO serial [21:37:26.375] [0;31msystemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument[0m
INFO serial [21:37:26.876] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [21:37:28.883] WDT:   Not starting watchdog@30090a0
state: load info probe trace unload bind 

## Misc
state: load info probe trace unload bind 
STALL/ssh rc/UNREACHABLE: none
Results: harness/research/arm-blob/traces/runner-j65 (git-ignored)
dmesg fault/WARN lines: dmesg-probe 31, dmesg-trace 39 (DATA_INVALID_FAULT), dmesg-unload 4 (regulator + runtime_pm WARNING/Call trace), dmesg-load: IRQ JOB/MMU/GPU not found, workqueue WARNING
kctx lines: atoms 3, jitstats 12, mem_allocs 72, mem_zones 3; KCTX-SAMPLES 3; kbtrace.bin 5919025 bytes, 46 submits
