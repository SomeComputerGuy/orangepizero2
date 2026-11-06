# Job 64-kbase-traces2 summary

Kernel under test: #51 SMP PREEMPT Fri Nov 6 20:28:54 UTC 2026 (c48). Start 2026-11-06 21:07:37, end 21:12:31. Stock kernel restored: #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026.
Results: harness/research/arm-blob/traces/runner-j64 (git-ignored)

## Checks (--check output, full)
```
PASS kernel: kernel: #51 SMP PREEMPT Fri Nov  6 20:28:54 UTC 2026
PASS BTF fix bd60a159b in the kernel
PASS panfrost unbound
PASS insmod rc 0
PASS no BTF lines in dmesg after insmod
PASS /dev/mali0 present
PASS /sys/kernel/btf/bifrost_kbase present
PASS kbase probed: DMESG: [   71.336562] mali 1800000.gpu: Kernel DDK version g25p0-00eac0 DMESG: [   71.337648] mali 1800000.gpu: sunxi glue: reset deasserted, 2 clocks, 1 regulators, core clk 456000000 Hz 
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
DMESG: [   86.954504] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   86.955905] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.072086] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.073939] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.157398] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.159110] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.234618] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.236133] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.328145] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.328242] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.329902] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.330032] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.504371] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.504517] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.506450] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.506510] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.621300] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.621345] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.622734] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.622802] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.773308] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.773452] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.775734] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.775783] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.775859] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 1
DMESG: [   87.937998] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.938043] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.938074] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.939215] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   87.939258] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   87.939287] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
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
DMESG: [   97.150720] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.150772] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.155247] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.155295] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.257500] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.257600] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.265808] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.265903] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.359798] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.359896] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.367582] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.367627] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.453930] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.454026] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.461921] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.462014] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.564049] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.564147] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.572492] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.572599] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.711060] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.711157] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.719364] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.719455] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.823244] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.823293] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.831304] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.831350] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.947916] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.948010] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.956491] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.956594] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.956654] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 1
DMESG: [   98.099317] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   98.099430] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   98.099474] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   98.107583] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   98.107628] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   98.107657] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
PASS files/trace/kbtrace.bin 42537 bytes
PASS decoded: 28 submits, index.txt 649 lines
FAIL probe: basic case did not render (basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505)
FAIL trace: basic case did not render (basic: lit pixels 0/4096, hash 00000000, px(16,16)=000000 px(48,40)=000000, glError 0x505)
PASS stock kernel restored, panfrost renderD128 back
INFO unload: RMMOD-RC 0 (no STEP-DONE: board hung or reset)
INFO unload DMESG: [  107.780682] mali 1800000.gpu: kbase_device_runtime_disable: Device runtime usage count unexpectedly non zero 1
INFO serial [21:08:46.429] ]3008;end=c6c14f88d6be4d548f2c51e6027329e3\systemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument
INFO serial [21:08:47.433] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [21:08:48.937] WDT:   Not starting watchdog@30090a0
INFO serial [21:10:56.062] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [21:10:58.071] WDT:   Not starting watchdog@30090a0
INFO serial [21:11:48.144] ]3008;end=ceb2612696f14f3fa91f2d41398f0dd1\systemd-shutdown[1]: Failed to set watchdog hardware timeout to 2min: Invalid argument
INFO serial [21:11:49.147] U-Boot SPL 2026.10_armbian-2026.10-S5508-P574f-Hf8df-V1b9e-Bcd80-R448a (Nov 04 2026 - 04:58:08 +0000)
INFO serial [21:11:50.649] WDT:   Not starting watchdog@30090a0
state: load info probe trace unload 
```

Key: checks 1-8,10,12 PASS; check 9 FAIL (0/4096 lit pixels all cases, glError 0x505 except gs_layer1 0x0); check 11 FAIL (31 probe / 39 trace DATA_INVALID_FAULT lines, slot 0/1). KCTX-SAMPLES 3; kctx lines atoms 3, jitstats 12, mem_allocs 72, mem_zones 3. kbtrace.bin 42537 bytes, 28 submits. Unload: RMMOD-RC 0, no STEP-DONE (board reset, ssh rc 255 at 21:11:30), recovered, restore ok. runner.log STALL/UNREACHABLE: none; 'ssh rc 255' on step unload.
state: load info probe trace unload
