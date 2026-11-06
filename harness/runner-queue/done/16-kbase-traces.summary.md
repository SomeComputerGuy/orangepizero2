# 16-kbase-traces: FAIL (trace step TRACE-RC 139; probe step PASS except dmesg) and STALLED in the restore phase
Start 2026-11-05 23:42:36 UTC, end 2026-11-06 01:17:03 UTC. Kernel: c20 (821dfb5bd), 
STALLED: runner.log did not advance from 2026-11-05 23:46:14 (fetched files/trace: 1 files) to 2026-11-06 01:16:16 (restore: dri after rebind), about 90 min, i.e. above the 20 min limit; the script then finished by itself (exit 0) and restored the stock kernel. Script watchdog did not cut this gap.
Check output (--check), verbatim:
```
PASS kernel: kernel: #19 SMP PREEMPT Thu Nov  5 23:14:46 UTC 2026
PASS BTF fix bd60a159b in the kernel
PASS panfrost unbound
PASS insmod rc 0
PASS no BTF lines in dmesg after insmod
PASS /dev/mali0 present
PASS /sys/kernel/btf/bifrost_kbase present
PASS kbase probed: DMESG: [   70.167554] mali 1800000.gpu: Kernel DDK version g25p0-00eac0 DMESG: [   70.168622] mali 1800000.gpu: sunxi glue: reset deasserted, 2 clocks, 1 regulators, core clk 456000000 Hz 
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
DMESG: [   96.908680] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   96.910406] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.006771] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.008658] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.091759] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.092842] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.168160] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.169808] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.261359] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.261460] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.263356] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.263468] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.390573] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.390677] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.391930] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.391973] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.485338] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.485384] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.487223] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.487340] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.593391] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.593488] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.595739] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.595854] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.595950] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 1
DMESG: [   97.728588] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.728699] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.728747] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.730553] mali 1800000.gpu: error detected from slot 0, job status 0x00000058 (DATA_INVALID_FAULT)
DMESG: [   97.730678] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
DMESG: [   97.730747] mali 1800000.gpu: t6xx: GPU fault 0x58 from job slot 0
PASS step trace finished
FAIL gles32probe (trace) rc: TRACE-RC 139
FAIL files/trace/info.txt missing or incomplete
FAIL files/trace/basic.rgba missing or empty
FAIL files/trace/gs_pass.rgba missing or empty
FAIL files/trace/gs_amp.rgba missing or empty
FAIL files/trace/gs_inv.rgba missing or empty
FAIL files/trace/tess_tri.rgba missing or empty
FAIL files/trace/tess_gs.rgba missing or empty
FAIL files/trace/tess_quad.rgba missing or empty
FAIL files/trace/gs_xfb.rgba missing or empty
FAIL files/trace/gs_layer0.rgba missing or empty
FAIL files/trace/gs_layer1.rgba missing or empty
FAIL files/trace/basic.progbin missing or empty
FAIL files/trace/gs_pass.progbin missing or empty
FAIL files/trace/gs_amp.progbin missing or empty
FAIL files/trace/gs_inv.progbin missing or empty
FAIL files/trace/tess_tri.progbin missing or empty
FAIL files/trace/tess_gs.progbin missing or empty
FAIL files/trace/tess_quad.progbin missing or empty
FAIL files/trace/gs_xfb.progbin missing or empty
FAIL files/trace/gs_layer.progbin missing or empty
PASS dmesg-trace.txt: no fault/oops lines
FAIL files/trace/kbtrace.bin missing or empty
FAIL files/trace/decoded/index.txt missing (kbdecode)
FAIL stock kernel not restored or no renderD128: 
state: load info probe trace 
```
Last 5 lines files/probe/info.txt not needed (probe rc 0). Trace: TRACE-RC 139 (segfault of the blob under kbtrace), files/trace/info.txt empty, no kbtrace.bin, no decoded/, 0 submit files.
Check 11 line shows FAIL although runner.log 'restored:' line reads: 2026-11-06 01:17:03 restored: 7.3.1-edge-sunxi64 #17 SMP PREEMPT Fri Oct 30 12:09:52 UTC 2026 vmlinuz-7.3.1-edge-sunxi64 by-path card0 card1 renderD128 (the script was run to completion before --check; reported as printed).
Results: harness/research/arm-blob/traces/runner/ (git-ignored).
