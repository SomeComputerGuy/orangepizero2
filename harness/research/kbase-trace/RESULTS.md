# kbase GLES 3.2 reference traces: state (status.md work list item 8)

Background, tools, port notes: ../impl-gles32-arm-traces.md.

## Current state
Updated 2026-11-06 23:30 (fix agent after runner job 66).
- **Job 66: the blob config cannot turn AFBC off** (parsed, still AFBC RTs, 0 lit pixels). Host analysis (below): the
  GLES_DISABLE_*_AFBC options are compiled out of this release blob and no kbase GPU property gates AFBC, but the blob
  uses **no AFBC for float colour buffers** (RGBA16F/RGBA32F -> U-tiled RTs, no AFBC descriptor anywhere in the trace).
- Runner job **67-kbase-traces5** queued (harness/runner-queue/67-kbase-traces5.md; package runner/kbase-traces.sh v5 +
  runner/HANDOFF.md, checks 1-20). Step `afbc` replaced by `fb`: basic case with gles32probe PROBE_FB=tex8 (control),
  rgba16f, rgba32f; probe + trace with the first float mode that renders. Kernel c48 (b82264f81), bifrost_kbase.ko v4
  (md5 aa7e170386c6672fe001d95daff25f30), unchanged. Results: harness/research/arm-blob/traces/runner-j67/.
- What a float framebuffer distorts in the traces: only the fragment output side (RT format RAW64/128 U-tiled instead of
  RGBA8 AFBC, the blend/conversion of the colour output, no AFBC-decompress blit before glReadPixels). Vertex/tiler/
  compute jobs, the GS/tess lowering and the shader programs other than the colour write are the same; and panfrost
  on this GPU never uses AFBC either. The blob trace is not rewritten in any way (no descriptor fixup needed).
- Next (fresh agent after job 67): if the float mode renders, item 8 step 2 (GS/tess observations from the trace);
  if it still faults, the fault is not AFBC-only: decode files/trace/decoded/submit-*-post.txt (fault_ptr) again.

## Job 66 (c48, 2026-11-06 21:50) findings + host analysis (2026-11-06 22:00-23:30)
1. Job 66: the blob parsed the config files (`Successfully parsed 2/3 environment variable(s)`), but every variant
   (v0-v3) gave 0/4096 lit pixels, glError 0x505, 2 DATA_INVALID faults, and the trace still holds 40 AFBC RTs
   (18 of them 0x20258 after the run). Load/unload clean (checks 16/19 PASS), SPL count 2.
2. **Why the options do nothing** (libmali g24p0, md5 dd143e98..., static): the option registry is a table of 180
   entries at .data 0x3585d88 (stride 0x30: name, type, default(), enabled(), parse(ctx, entry, slot), index). The
   init loop (0x1a905f4..0x1a90790) calls enabled(); if it returns 0 the value is parsed into a scratch buffer and the
   slot gets the type's zero value; if 1, default() then parse() into the slot. GLES_DISABLE_SURFACE_AFBC (index 140)
   and GLES_DISABLE_TEXTURE_AFBC (141), like all 48 GLES_* bool options, have enabled() = `mov w0,#0; ret` and the
   presence-only parse stub 0x1a90bc0 (it only checks the key exists; options that work have real parsers that call
   0x1a99760). Forcing the slot value through the registry (blobopt.c: enabled() -> 1, parse() writes 1) stores the 1
   but the RTs stay AFBC: the readers of these options are compiled out too. Dead end, documented; blobopt.c kept as
   the record (not shipped).
3. **Host simulation** (new, kbase-trace/hostsim/): kbfake.so fakes /dev/mali0 (UK 11.45, gpuprops from job 66's
   gpuprops.bin, SAME_VA/EXEC allocations, JIT writes, every atom DONE, DRV_TERMINATED after POST_TERM) and runs the real
   blob + gles32probe under qemu-aarch64 (no GPU, no board), stacked under kbtrace.so so kbdecode decodes what the blob
   would submit. ~5 s per run. It reproduces the board trace exactly (same GPU VAs, FBD 0x1afe385c0 / RT 0x1afe38680,
   20 AFBC + 18 linear + 11 U-tiled RTs). `hostsim/sim-rt.sh <dir> [KBFAKE_SET]` prints the RT formats.
4. GPU properties: every gpuprops key 2..85 set to 0 (one run each), keys 30 (CORE_FEATURES), 85 (RAW_GPU_FEATURES) also
   0xffffffff, texture features all-0/all-1, unknown keys 86/87 added: **no change** (same 20 AFBC RTs). Only the
   product id matters (any other id: `mali_device_info_init` fails, this is a G31-only build). kbase's uAPI has no AFBC
   property to report (AFBC_FEATURES is in the regmap only), so there is no truthful property to export that the blob
   would read. The blob reads no sysfs/debugfs besides dma_buf_* moduleprops and large_page_conf (strace).
5. Framebuffer formats (gles32probe PROBE_FB, new): tex8, teximage8 (glTexImage2D), rbo8 (renderbuffer), rgb10a2, srgb8,
   rgb565 -> AFBC RT (20 AFBC). **rgba16f and rgba32f -> 22 U-tiled RTs, 0 AFBC descriptors, 18 submits** (tex8: 28; the
   10 extra are the AFBC pre-frame/decompress blits before each readback). Writeback format RAW64 for RGBA16F.
6. Fallback not needed: a kbtrace fixup (AFBC RT -> linear before JOB_SUBMIT) would also have to rewrite the texture
   descriptors and the blob's AFBC readback blits (invasive, distorts the fragment side); the float framebuffer gets
   the blob's own non-AFBC path instead.

## Job 65 (c48, 2026-11-06 21:33) findings
1. Memory captured (46 submits decode). The POST lines' `exception_status 0x1 / fault_ptr 0x872aec5d` are a red
   herring: those are the headers of jobs that completed (0x1 = DONE); 0x872aec5d is the same stale word in every DONE
   header (the GPU leaves the fault-pointer field undefined on success). The faulting job is the SECOND fragment job of
   each chain (the one at JS_HEAD in the `sunxi diag` line, e.g. 0x1afe39240, reached via `Next` of the atom's first
   fragment job). Its header after the fault: exception_status **0x20258** (DATA_INVALID 0x58), fault pointer
   **0x1afe38680** = FBD 0x1afe385c0 + 0xc0 = the **colour render target descriptor** (v7 FBD: 0x80 parameters + 0x40
   ZS/CRC extension, then the RTs).
2. That RT is `AFBC RGB Color Render Target 0` (Writeback Block Format AFBC, header 0x1afe62000, body 0x1afe62100).
   Over all submit-*-post.txt files, fragment jobs by status and RT format: **18x 0x20258 AFBC, 18x 0x1 (DONE) Linear,
   2x 0x0 (not run) AFBC**: every AFBC RT faults, every linear RT completes. The first fragment job of each chain (1x2
   pre-frame with a linear, write-less RT) is DONE. Tiler context/heap are fine: heap descriptor at 0x1afe38540 holds
   base 0x1b0000000 .. top 0x1b5000000, which is exactly the JIT region the kernel wrote (JITADDR id 1/2 = 0x1b0000000),
   so the JIT/tiler hypothesis is ruled out.
3. Why: this H616 G31 reports AFBC_FEATURES 0x10001 (job 51: AFBC not implemented; Mesa's pan_query_afbc() is false and
   panfrost never uses AFBC here). kbase (this g25p0) exports no AFBC property to user space (KBASE_GPUPROP_* has no AFBC
   entry; GPU_CONTROL__AFBC_FEATURES is only in the regmap), and the blob decides AFBC from the product ID (G31 =
   AFBC-capable in Arm's tables). So the GPU rejects the AFBC RT with DATA_INVALID and the blob reports
   GL_OUT_OF_MEMORY. No kernel/glue fix can change the blob's choice; the fix is the blob's own config.
4. Blob config mechanism (host analysis of libmali g24p0: strings, objdump, and gles32probe under qemu-aarch64 with a
   getenv/fopen hook, /tmp only): options are NOT read from the environment; the blob reads key=value files named by
   `MALI_PLATFORM_CONFIG` (default ./mali_platform.config) and `MALI_DEBUG_CONFIG` (default ./mali_debug.config) into
   one table ("Successfully parsed N environment variable(s) from <file>" on stderr), stripping an optional `MALI_`
   key prefix (strncmp(name, "MALI_", 5) in both the parser and the lookup). Relevant bool options (type 1, default
   0): GLES_DISABLE_TEXTURE_AFBC, GLES_DISABLE_SURFACE_AFBC, GLES_DISABLE_CRC, GLES_FORCE_LINEAR_LAYOUT_UNCOMPRESSED_TEXTURE.
   The probe renders to a texture FBO, so TEXTURE_AFBC is the one that matters. Not yet board-verified that a release
   blob honours them (the option table carries a per-option flag that is 0 for these and 1 for e.g.
   CMAR_OPTIMIZE_FOR_LATENCY; meaning unknown, possibly "platform-config allowed"): job 66 tries them via both files.
   For the traces this matches panfrost on this GPU (no AFBC either), so the GS/tess reference is not distorted.
5. Load/unload noise (fixed in kbase.ko v4, port-7.3-v4.py, run by port-7.3.py at its end): `-ENXIO IRQ JOB/MMU/GPU not
   found` = the upper-case name lookup with platform_get_irq_byname() logging before the lower-case fallback (DT uses
   job/mmu/gpu) -> _optional variant; `__alloc_workqueue` WARNING = mali_mmu%u (also Mali reset, kbase_event,
   job_fault_resume) with neither WQ_PERCPU nor WQ_UNBOUND -> WQ_PERCPU (the old default); unload `_regulator_disable`
   "unbalanced disables" + WARN_ON at mali_kbase_runtime_pm.c:75 = the glue enabled the supply only if
   regulator_is_enabled() was false (it is already on: shared/boot-on), but disabled it whenever it was on -> per-consumer
   bitmask of what kbase itself enabled (regulators and clocks). Remaining, harmless: `usage count unexpectedly non zero
   1` (panfrost_remove's leaked runtime-PM get) and the WQ_NAME_LEN truncation notice.

## Job 66 design (what it decides)
- New step `afbc` (after info): basic case under /root/armblob/cfg/v0..v3.config (v0 empty control; v1 TEXTURE+SURFACE
  AFBC off; v2 + CRC off; v3 + forced linear textures), each with MALI_PLATFORM_CONFIG and MALI_DEBUG_CONFIG set;
  `VARIANT vN rc .. faults .. cfg [..] basic: lit pixels ..` lines + BLOB stderr lines (shows the "parsed" message).
  SELECTED = first of v1..v3 that renders (v3 if none); probe and trace run under it (CONFIG line in their step files).
- Checks 16-19: no IRQ/WARNING lines at load, a variant renders, no AFBC RT in the decoded trace, no WARNING at unload.
- If no variant renders: the VARIANT/BLOB lines and the trace's `INFO rt:` line tell whether the blob ignored the
  config (still AFBC RTs) or something else faults (linear RTs faulting); next step then = find the gate on these
  options in the blob (the per-option flag, MALI_CDBG_PERMISSIONS) or an AFBC-capability input it does read.

## Job 64 (c48, 2026-11-06 21:07) findings
1. Load/probe/trace all ran (TRACE-RC 0 now); every case again 0/4096 lit pixels, glError 0x505 (gs_layer1 0x0: the
   error was already read by gs_layer0); 31 (probe) / 39 (trace) fault lines: `job status 0x58 (DATA_INVALID_FAULT)` on
   slot 0, plus `t6xx: GPU fault 0x58 from job slot 1` once per run (an atom inheriting the failure, not a vertex fault).
2. **The trace held no memory: tracer bug.** kbtrace.bin has 0 KBT_MEM records (parsed: 145 ioctls, 73 mmaps, 74
   snapshots, 0 MEM), so every decoded job header was zero ("Type: Not started"). Cause: safe_read() used
   process_vm_readv(), which pins pages through GUP, and GUP refuses VM_IO|VM_PFNMAP vmas (mm/gup.c check_vma_flags;
   kbase_cpu_mmap sets VM_IO + VM_PFNMAP, mali_kbase_mem_linux.c:2538/2565) -> EFAULT for every page. Fix (kbtrace.c v3):
   copy through a pipe (write(2) = copy_from_user, a normal user access that faults kbase pages in and returns EFAULT,
   no signal, on pages kbase cannot back). Also records the JIT soft-job payloads (KBT_SOFT). kbdecode v3: for each
   submit with a non-DONE event, POST lines (job header after the fault: exception_status, first_incomplete, fault_ptr,
   64 bytes at fault_ptr) + submit-NNNN-post.txt (pandecode from the after-fault memory); JIT_ALLOC/JIT_FREE lines and
   JITADDR (value the kernel wrote at gpu_alloc_addr). kbtrace-selftest.sh v3 PASS (memory + KBT_SOFT + beyond-EOF
   pages without SIGBUS); aarch64 kbtrace.so run under qemu-aarch64: trace written with the memory.
3. What the data does show (narrows the search):
   - Vertex/tiler jobs execute correctly: gs_xfb transform feedback holds the exact expected positions
     (xfb[0]=(-0.6,-0.4,0,1), xfb[3]=(-0.2,-0.4)), every 0x4e (vertex/tiler) atom ends DONE. So CPU->GPU descriptor
     coherency, shader upload (EXEC_VA), MMU/page tables, IRQs and the JM slot setup work. Only the fragment atom
     (core_req 0x1, slot 0) fails, already for the clear-only frame (submit #0, before any draw).
   - No MMU faults, no MEM_SYNC ioctl (the blob does its own cache maintenance), all 73 MEM_ALLOCs succeed;
     JIT: MEM_JIT_INIT va 0x40000 pages, 255 allocs; 4 live JIT regions in CUSTOM_VA (0x1b0000000.., one 0x17000 pages
     with 5 committed = probably the tiler heap), mem_jit_phys 130 pages. The JIT soft atoms (0x209) report DONE.
   - gpu props the blob reads are sane for a G31 r0p0 (decoded gpuprops.bin): product 0x7093, MMU_FEATURES 0x2821
     (33-bit VA: SAME_VA ends at 0x200000000 before JIT/EXEC carve-outs), shader/tiler/L2 present 0x1, L2 0x07100206,
     TILER_FEATURES 0x209, JS0 0x20e (fragment), JS1 0x4fe, COHERENCY_MODE 0x1f (= COHERENCY_NONE, no dma-coherent),
     TLS_ALLOC 0x200, GPU_FREQ_KHZ_MAX 5000 (default, no OPP table: cosmetic).
   - GL_OUT_OF_MEMORY is most likely the blob's report of the failed fragment atom (the error appears per frame with
     the 0x58 event; no allocation fails).
   Best-supported hypothesis (unverified, data in job 65): the fragment job reads a descriptor that is invalid only
   for the fragment path: the tiler context / tiler heap pointer patched by the kernel's JIT write (written via
   kbase_vmap_prot + sync after the submit-time snapshot), the FBD itself, or the sample-position/TLS pointers. The
   post-fault job header (fault_ptr) and the JITADDR lines decide between these.
4. **Unload reset (cause identified, fix in job 65).** panfrost_remove() leaves the GPU with RST_BUS_GPU asserted,
   clocks + supply off and runtime PM suspended, and leaks one runtime-PM usage count (pm_runtime_get_sync() without
   a put, drivers/gpu/drm/panfrost/panfrost_drv.c:1029): that is the "usage count unexpectedly non zero 1" kbase sees
   at probe and again at term (harmless). kbase's sunxi glue term only did pm_runtime_disable(): RST_BUS_GPU stayed
   deasserted (and clocks prepared) while genpd cut the GPU power domain (prcm_ppu GPU, PD_FLAG_DETACH_POWER_OFF at
   the devres release), so the next panfrost bind powered the GPU domain up without a reset pulse; both job 16 and
   job 64 hard-hung there (job 64: unload 21:10:38, RMMOD-RC 0, BIND-START echoed, silent reset 21:10:56 = watchdog).
   Fix (port-7.3.py v3, applied to kernel-check/kbase-trial/src): the glue keeps the reset control from
   runtime_init and, in kbase_device_runtime_disable() (called after the IRQs are released, kbase_device_early_term),
   asserts the reset, turns clocks + supply off and sets runtime PM suspended, logging `sunxi glue: reset asserted,
   clocks + supply off, runtime PM suspended (usage count N)`. Not yet board-verified.
   Also new in v3 (diagnostic): `sunxi diag: slot N status 0x.. head 0x.. tail 0x..` (rate limited) per job fault
   (backend/gpu/mali_kbase_jm_hw.c).

## Job 65 design (what it decides)
- Check 13: memory captured (fragment jobs decode). Then from files/trace/decoded: POST lines = the fragment job's
  exception_status/fault_ptr after the fault; submit-0000-post.txt = full pandecode of the clear-only frame's FBD,
  tiler context (polygon list, heap start/end) and render targets after the fault; JIT_ALLOC + JITADDR = whether the
  kernel's JIT address landed where the tiler context expects it (JITADDR value 0 or not equal to a CUSTOM_VA region
  start = kernel JIT write/sync bug; a correct value = look at the FBD fields the fault_ptr points at).
- Checks 14/15: unload + panfrost rebind without a reset (the glue term fix). PM/GENPD/CLK lines before/after give
  the state if it still hangs.

## Rebuild notes
- Module: `bash kernel-check/kbase-trial/port/build.sh` (under kernel-check/.locks/kernel-build.lock), then
  `echo "c48 <Image md5>" > .../bifrost_kbase.ko.tag`. Port script changes go to kbase-port/port-7.3.py (tracked) and
  kernel-check/kbase-trial/port/; apply only the new block to the already-ported src (the old reps are not idempotent).
  v4+: new blocks go in their own file (kbase-port/port-7.3-v4.py, run alone: `python3 -I port-7.3-v4.py
  kernel-check/kbase-trial/src/drivers/gpu/arm/bifrost`); port-7.3.py exec()s it at its end for a fresh tree.
- kbtrace.so: `aarch64-linux-gnu-gcc -O2 -Wall -shared -fPIC -o kbtrace.so kbtrace.c -ldl -lpthread`.
- kbdecode (host): B=kernel-check/kbase-trial/mesa-decode/build G=$B/src/panfrost/genxml;
  `gcc -O2 -Wall -I. -o kbdecode kbdecode.c -Wl,--start-group $G/libpanfrost_decode.a $G/libpandecode-arch-v*.a
  $B/src/panfrost/lib/libpanfrost_lib.a $B/src/panfrost/lib/libpan-arch-v*.a $B/src/compiler/libcompiler.a
  $B/src/util/libmesa_util.a $B/src/util/libmesa_util_simd.a -Wl,--end-group -lm -lpthread -lz -lzstd -lstdc++`
  (build in an empty temp dir, copy the binary here; it is git-ignored/untracked like kbtrace.so).

## Job 16 (c20, 2026-11-05 23:42) findings
1. kbase load PASS (BTF ok, /dev/mali0, DDK g25p0, sunxi glue 456 MHz); probe rc 0 with all 19 files.
2. **Trace segfault (TRACE-RC 139) = kbtrace.c bug.** is_mali() recorded KBT_OPEN through rec() before init() had
   opened the trace file (out == NULL): ioctl()/mmap() called init() only after the is_mali() check, so the blob's
   first ioctl on /dev/mali0 crashed in fwrite(NULL). Signature matches: no kbtrace.bin, empty info.txt. Reproduced on
   the host with the old source (path-patched: rc 139, no trace file). Fix: is_mali() runs init() under the lock
   before the first record; plus calloc-failure guards in snapshot() and no reads past a non-page-multiple region.
   Host self-test kbtrace-selftest.sh (native build, fake device via KBTRACE_DEV): PASS on the fix, FAIL on the old
   code; aarch64 kbtrace.so rebuilt (`aarch64-linux-gnu-gcc -O2 -Wall -shared -fPIC -o kbtrace.so kbtrace.c -ldl
   -lpthread`, needs GLIBC_2.38 as before) and checked under qemu-aarch64 (trace written).
3. **Every probe case rendered nothing**: `lit pixels 0/4096, glError 0x505` (GL_OUT_OF_MEMORY) for all 10 cases,
   31 dmesg lines `job status 0x58 (DATA_INVALID_FAULT)` on slot 0 (fragment), one on slot 1; no MMU faults. Not yet
   explained. Ruled out statically: DT coherency (kbase default COHERENCY_NONE, no dma-coherent), IOMMU (GPU has none).
   Hypotheses for the analysis agent: tiler heap / JIT allocation too small or failing (the blob reports tiler OOM as
   GL_OUT_OF_MEMORY and the fragment job then reads an invalid polygon list), or CPU-cached descriptor memory not
   cleaned for the GPU (port of the kbase sync path to 7.3). Job 64 adds per-context debugfs sampling during the probe
   (files/probe/kctx/: mem_jit_count/phys/vm/used, atoms, mem_allocs, mem_zones, the blob's mem_profile) and the trace
   gives the JIT_ALLOC atoms and the fragment job's FBD through kbdecode.
4. **Board reset in the restore**: serial.log shows a silent reset (U-Boot SPL 23:46:29, ext4 journal recovery) ~15 s
   after the restore's `rmmod bifrost_kbase; echo 1800000.gpu > panfrost/bind` started (23:46:14): a hard hang caught
   by the hardware watchdog (no console output at the default loglevel). It came back on the trial Image, the vdec
   fallback rebooted it to stock at 23:52. The ssh of that call had no keepalive (ssh.sh got ServerAlive only at
   06:54 on 11-06) and the call ran outside the step watchdog, so it sat until 01:16. Likely cause (unverified): kbase
   remove touching GPU registers while runtime-suspended (clocks off, prcm_ppu domain off: the glue's runtime_init
   enables clocks/reset but term only disables runtime PM). Job 64 runs it as a separate diagnostic `unload` step with
   loglevel 8 and keeps the serial.log slice (serial.txt); the restore itself is a plain reboot.
5. Check 11 printed FAIL although the stock kernel was back: the check grepped `^restored: ` but runner.log lines start
   with a timestamp. Fixed (` restored: `); on job 16's files it now PASSes.

## Harness ssh (part A, done)
- harness/ssh-opts.sh (sourced by ssh.sh and all 32 packages that had their own `K=(...)` option array, plus
  board-queue.sh, analysis/gpu/oclfix/{run-batch,run-chunk,deploy}.sh, ffmpeg/avs-board-test.sh, and the untracked
  mesa-work/tools/deploy.sh): IdentitiesOnly, BatchMode, ConnectTimeout 8, ServerAlive 15 s x 8, harness/known_hosts
  with StrictHostKeyChecking=accept-new (was `no`: a changed key was accepted silently), scp() wrapper with an overall
  timeout (SCP_TIMEOUT, default 900 s), kill_pid (TERM, KILL after 5 s) used by every stall watchdog on its own ssh PID.
  harness/ssh.sh takes SSH_TIMEOUT=<s> for one-shot commands.
- Plain `ssh root@10.56.0.107` vs harness: plain ssh used ~/.ssh/known_hosts, whose three 10.56.0.107 keys dated from
  before the 2026-11-04 reflash (Armbian regenerates host keys on the first boot; reflash.sh step 9 resets only
  harness/known_hosts, which holds the current ed25519 key; harness ssh also never checked strictly). No runner log
  ever showed a changed-key warning, so the harness entry is the current key. Replaced only the 10.56.0.107 lines in
  ~/.ssh/known_hosts with the harness entry (other hosts untouched; old file kept as ~/.ssh/known_hosts.old).
  AGENT-RULES.md / RUNNER.md: "Host key verification failed" = BLOCKED, no known_hosts edits by runners.

## Next step
Wait for job 66's summary. Then (fresh agent): if check 17 PASS and probe/trace render, item 8 step 2 (GS/tess
observations from files/trace/decoded under the selected config) and record the selected variant here; if checks 16/19
PASS, the load/unload noise is gone. If no variant renders, see "Job 66 design" last point.
