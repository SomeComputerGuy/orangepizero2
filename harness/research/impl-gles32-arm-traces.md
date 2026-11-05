# GLES 3.2 reference traces from Arm libmali g24p0 (status.md item 8, step 1): INTERIM

Status 2026-11-05 ~11:00: host side done. On the board, kbase got through power-up but probe failed on a
runtime-PM check (now fixed). **No traces captured yet**: about 4 h of board-lock contention, then the switch to
the cumulative kernel rule (trace session must run on c1, which is still building).

## kbase version
- Blob: libmali-bifrost-g31-g24p0-gbm (JeffyCN/mirrors 34f62629), `arm_release_ver: g24p0-00eac0`, JM.
  Exports EGL/GLES/GBM/OpenCL; EGL_KHR_platform_gbm, EGL_KHR_surfaceless_context, EGL_KHR_no_config_context.
- Kernel: Rockchip `rockchip-linux/kernel` develop-6.6 @ 1ba51b05 (2025-09-01), drivers/gpu/arm/bifrost
  **g25p0-00eac0**, JM UK 11.47 (the blob checks major 11 and needs minor <= the kernel's; Rockchip ships
  g24p0 user with g25p0 kernel). GPL; sparse clone in kernel-check/dl-kbase/rk66.

## Porting notes (port-7.3.py, idempotent from pristine)
Kbuild `$(src)` abs path; EXTRA_CFLAGS -> KCFLAGS (Kbuild ignores EXTRA_CFLAGS, so MALI_REAL_HW was lost);
Rockchip OPP/system-monitor hooks under CONFIG_ARCH_ROCKCHIP; hrtimer_init -> hrtimer_setup(_on_stack);
del_timer* -> timer_delete*; no_llseek -> noop_llseek; FMODE_UNSIGNED_OFFSET -> fop_flags; void platform
remove; dma_fence_signal void; dma_set_max_seg_size void; dma_fence_ops.fence_value_str removed; vmalloc.h;
__Set/ClearPageMovable stubbed (page migration compiled out). Devfreq off (CONFIG_MALI_BIFROST_DEVFREQ=n: the
devfreq code is entangled with Rockchip; fixed clock is fine for traces).
H616 glue in platform/devicetree runtime init: deassert RST_BUS_GPU, enable clocks + mali-supply before
pm_runtime_set_active (panfrost unbind leaves reset asserted, clocks gated). Usage-count != 0 at probe made
non-fatal (it was the first board failure).
The existing upstream DT node works unchanged (reg, 3 IRQs found by lower-case fallback, core+bus clocks,
prcm_ppu domain, dcdcc, OPP table). Boot-time trial: overlay `sun50i-h616-gpu-kbase.dtso` sets compatible
`arm,mali-midgard` (kbase matches it, panfrost does not), so no blacklist is needed.

## Board run 1 (image kernel P7cdd, 08:23, runtime unbind of panfrost + insmod)
`Kernel DDK version g25p0-00eac0`, `sunxi glue: reset deasserted, 2 clocks, 1 regulators, core clk 306000000 Hz`,
then `Device runtime usage count unexpectedly non zero 1` -> probe -EINVAL. Fixed (warn only), rebuilt;
panfrost rebound, /dev/dri/renderD128 back. Not re-run before the cumulative-kernel switch.

## Runner package (2026-11-05 late): harness/research/kbase-trace/runner/{kbase-traces.sh,HANDOFF.md}, queued as
harness/runner-queue/16-kbase-traces.md. It installs the newest cumulative kernel (c17 at submission; the BTF fix
bd60a159b is in c7+), stages module + blob + tools in /root/armblob, unbinds panfrost, insmods kbase, runs probe and
trace, fetches to harness/research/arm-blob/traces/runner/files/, rebinds panfrost and restores the stock kernel.
`--check` prints the mechanical checks. The manual steps below are superseded by it (kbase-slot.sh stays for DEV use).

## How to run manually (superseded by the runner package above)
1. `kernel-check/kbase-trial/port/build.sh` (now defaults to KDIR=kernel-check/work-cumul/linux-7.3.1, release 7.3.1).
2. `harness/research/kbase-trace/kbase-slot.sh stage|load|info|probe|trace|fetch run1|restore` under the board
   lock. Nothing is installed on the board (/root/armblob prefix, runtime unbind/bind), so a reboot restores panfrost.
3. Host: `kbdecode traces/run1/trace/kbtrace.bin out/` -> index.txt + pandecode v7 per submit.

## Tools (harness/research/kbase-trace, commit a81fc24)
kbtrace.so (LD_PRELOAD: all kbase ioctls, mmap->GPU VA map (SAME_VA cookies vs offsets), JOB_SUBMIT atom arrays,
event reads, changed-page snapshots before each submit and after each event via process_vm_readv so unbacked
grow-on-GPF pages don't SIGBUS, markers); kbdecode (host, links Mesa pandecode from a --shared snapshot clone of
panfrost-gs-tess 15bd751e896 in kernel-check/kbase-trial/mesa-decode, nothing in mesa-work touched);
gles32probe (GBM + surfaceless ES 3.2 context; prints EGL configs, GL strings, all GS/tess limits; cases basic,
gs_pass, gs_amp, gs_inv(invocations=4), tess_tri, tess_gs, tess_quad(fractional_odd), gs_xfb + PRIMITIVES_GENERATED,
gs_layer (gl_Layer, 2-layer array); saves 64x64 readbacks + glGetProgramBinary). Traces go to
harness/research/arm-blob/traces/ (whole arm-blob/ now git-ignored; traces/ was not before).

## Open
- Trace session on c1: GL_VERSION/extensions, traces, first GS/tess lowering observations (compute pre-passes,
  memory layout) are all still TODO. glcts KHR-GLES32 with the blob would need an EGL shim (glcts on the board
  uses EGL_PLATFORM_SURFACELESS_MESA, the blob has only GBM).
- Host note: /tmp (tmpfs 31 G) was 100 % full (other projects' mmdebstrap/vm dirs); my builds use kbase-trial/tmp.
