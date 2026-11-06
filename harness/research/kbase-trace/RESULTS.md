# kbase GLES 3.2 reference traces: state (status.md work list item 8)

Updated 2026-11-06 22:00 (fix agent after runner job 64). Background, tools, port notes: ../impl-gles32-arm-traces.md.

## Current state
- Runner job **65-kbase-traces3** queued (harness/runner-queue/65-kbase-traces3.md; package runner/kbase-traces.sh v3 +
  runner/HANDOFF.md, checks 1-15). Kernel c48 (b82264f81, unchanged); bifrost_kbase.ko **v3** rebuilt for c48
  (md5 16dd6b84d7c75dd958fcd2fc2adb77da, kernel-check/kbase-trial/build-c48-v3.log, tag refreshed). Results will land in
  harness/research/arm-blob/traces/runner-j65/ (git-ignored). Job 64 results stay in .../runner-j64/.
- Rendering (OOM + DATA_INVALID) is NOT fixed yet: job 64's trace held no GPU memory, so there was nothing to decode.
  Job 65 gathers exactly the missing data (see "Job 65 design"). Unload reset: fix under test in job 65.

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
Wait for job 65's summary. Then (fresh agent): if check 13 PASS, start from files/trace/decoded/index.txt POST/JITADDR
lines and submit-0000-post.txt (clear-only frame) in runner-j65; fix the cause (kernel JIT write/sync, or whatever field
fault_ptr points at) in port-7.3.py and queue the next run. If 14/15 PASS, the unload is fixed (mark it in this file and
status.md item 8); if not, the PM/GENPD/CLK lines + serial.txt show where. Item 8 step 2 (GS/tess observations) only
once the blob renders.
