# OpenCL (rusticl) + GLES fixes on panfrost, Mali-G31 (status.md item 3)

Agent: opencl-fixes. Date: 2026-11-05. Board: Orange Pi Zero2 (H616, Mali-G31 MP1, Bifrost v7.0, 4-wide warps).
Baseline: image 8546e5fc1, Ubuntu mesa 26.2.4-1ubuntu1, results in `harness/analysis/gpu/cts-8546e5fc1-server/`:
OpenCL-CTS Mesa profile **3136 subtests passed, 78 failed**, 2 binaries crashed (Relationals, Integer Ops),
3 timed out (Images Kernel 3D int/uint/float at 5000 s); GLES 3.1 mustpass gles31-main 1 Fail + 2 OOM,
gles31-khr-main 1 Fail (`mixedSequence`).

## Branches and commits

**Mesa** `panfrost-opencl-fixes` in `mesa-work/mesa-cl` (worktree of the Mesa clone), based on tag `mesa-26.2.4`
(= what Ubuntu ships, 96cb4312103). Local branch only; nothing pushed upstream.

| commit | what | origin |
|---|---|---|
| 2df1ec10089 | pan/bi: set branch reconvergence at loop exit points | cherry-pick -x of main 8b03ae787f4 |
| 6358a76bc19 | pan/bi: keep SEG_ADD.i64 src[1] out of the low destination register | ours (Generated-by: LLM) |
| 55fb9c9c4d3 | panfrost: use 4-wide subgroups on Bifrost v7.0 (Mali-G31, Mali-G51) | ours (Generated-by: LLM) |
| a2120a29e03 | pan/bi/nir: Scalarize the rest of nir_op_b(any\|all)_* | cherry-pick -x of main bab5285218a |
| 89dc6134c58 … 0301c677305 | 12 compiler/driver fixes from staging/26.2 (all in 26.2.5/26.2.6): nir_instr_set tex CSE (x2), no 64-bit iadd3, narrow_array_index, bi helper analysis tls-stores, lower_continue_constructs (x2), pan/lib (x3), panfrost free/leak (x2) | cherry-pick -x |
| 9049a3c5f2c | pan/bi: don't end a shader with a BARRIER clause | ours (Generated-by: LLM) |
| 45a7a7147d5, c6e6e63990b | drm-shim: GET_PARAMs for the kmod layer; signalled sync file for SYNCOBJ_HANDLE_TO_FD (host tooling only, not shipped) | ours (Generated-by: LLM) |
| ec376a8ee7e | nir/lower_cl_images: record buffer textures in texture_buffers (Bifrost texel-buffer attributes for read_image(image1d_buffer_t)) | ours (Generated-by: LLM) |
| a0a4534b14d | rusticl/mem: fix the whole-slice fast path of sw_copy and the rect copies (clEnqueueMapImage 3D etc.) | ours (Generated-by: LLM) |

**Kernel** `fix/sunxi-panfrost-softstop-resume` (armbian-build fork, worktree `wt-panfrost-softstop`, commit e544ddb00,
patch `patches.armbian/drm-panfrost-resume-a-still-active-job-after-a-timeout-instead-of-resetting.patch`): on the 500 ms
job watchdog, a slot that still reports ACTIVE is soft-stopped and resumed without the GPU reset (see "Root cause:
panfrost job timeout" below). Tags `Assisted-by: LLM` + Signed-off-by; checkpatch clean (one quoted dmesg line > 75
chars); panfrost_job.o built with W=1 in kernel-check/work-cumul (STAGE=patch: 834 patches applied, 0 failed). Not yet in
test-cumulative: the coordinator merges it; runner job 06-opencl-timeout-fix validates it.

**Kernel** `fix/sunxi-panfrost-mmu-map-warn` (armbian-build fork, worktree `wt-panfrost-mmu`), commit da59f9208
"sunxi-7.3: drm/panfrost: don't WARN when a GEM mapping cannot get its pages": `WARN_ON(IS_ERR(sgt))` ->
`IS_ERR(sgt)` in `panfrost_mmu_map()`, the error is still returned. Upstream (linux-next, drm-misc-next) still has
the WARN. Tags `Assisted-by: LLM` + Signed-off-by. checkpatch clean; built with `kernel-check/build-kernel.sh`
(panfrost.o built, CONFIG_DRM_PANFROST=m). Already merged into `test/cumulative` (13e656cca), so it is in the
cumulative test kernels; no private trial kernel needed.

## Test method

Fork Mesa is cross-built (meson, ccache, no Docker) in `mesa-work/build-cl` with the Ubuntu options plus rusticl
(`mesa-work/tools/setup-cl.sh`), installed to the board at `/root/opiz2-mesa/cl/` and selected only by environment
(`/root/opiz2-mesa/cl/env.sh`: LD_LIBRARY_PATH, __EGL_VENDOR_LIBRARY_FILENAMES, OCL_ICD_FILENAMES, VK_DRIVER_FILES).
The image's system Mesa is never touched, so nothing needs restoring; deleting `/root/opiz2-mesa` removes it.
Small repro kernels (ctypes runner `clk.py` + `t_*.py`) and the board batches are in `mesa-work/oclfix/tests/`,
raw logs in `mesa-work/oclfix/b*/`.

## Per failure class

### 1. Local atomics return 0 (Atomics 8, C11 Atomics 5)
- **Cause (two bugs).** (a) RA let `SEG_ADD.i64`'s src[1] (a zero that moved to a register because the uniform used
  the FAU slot) share the register of the low half of its destination; the pseudo-op is lowered into *SEG_ADD/+SEG_ADD,
  so the high half read a clobbered value. Only OpenCL hits it (local-memory kernel arguments are FAU uniforms).
  (b) Local cmpxchg lost lanes 1-3 of each 4-lane warp when code after a divergent loop contained another loop or an
  early end: missing reconvergence at loop exits (fixed upstream in 8b03ae787f4).
- **Fix.** 6358a76bc19 (interference src[1] vs dest[0] for SEG_ADD_I64 in bi_ra.c) + cherry-pick 2df1ec10089.
- **Before/after.** Atomics 5/13 -> 13/13 PASSED; C11 Atomics 27/32 -> 32/32 PASSED (board, batch1/batch2).

### 2. Crash "Unhandled ALU op ine" (Relationals, Integer Ops)
- **Cause.** `any()`/`all()` on 8- and 16-component vectors become `bany_inequal8/16`; bi_vectorize_filter only listed the
  2-4 component forms, so they were not scalarised and were lowered late into a vector `ine` the backend cannot emit
  (same class as mesa#10122).
- **Fix.** Cherry-pick of upstream bab5285218a (a2120a29e03).
- **Before/after.** Relationals crash -> PASSED 17 of 17. Integer Ops crash -> runs, FAILED 2 of 59
  (quick_long_math, quick_ulong_math: wrong 64-bit `/` and `%` results; see Open).

### 3. Half Ops vstore_half (5) and Basic async copies (2): lost stores before a trailing barrier
- **Cause.** Found by bisection (`t_loop64.py`): any Bifrost compute shader whose *last clause* is a BARRIER loses about
  70% of the global stores it issued before the barrier, in whole warps
  (`d[i] = s[i]; barrier(CLK_GLOBAL_MEM_FENCE);` -> ~2200/3072 words missing on system Mesa and on the fork; same kernel
  without the barrier, or with code after the barrier: 0 missing). OpenCL's `async_work_group_copy` +
  `wait_group_events` (libclc) always ends the kernel this way; vstore_half(..., __local) in the CTS copies the local
  buffer out with it.
- **Fix.** 9049a3c5f2c: after scheduling, if the program's last clause carries BARRIER, append a NOP clause
  (same mechanism as the v6 ATEST NOP), so the barrier clause is not the END clause. arch < 9 only.
- **Before/after.** Repro 2152-2480 bad -> 0 for every variant/local size; `t_async`/`t_vsh` all 0 bad;
  CTS Half FAILED 5 of 13 -> PASSED 13 of 13; Basic async_copy_local_to_global and
  async_strided_copy_local_to_global now pass (Basic FAILED 3 of 3 -> 1 of 3, the remaining one is enqueue_map_image).

### 4. Subgroup size on G31 (Vulkan agent FYI, impl-gpu-spec.md 4c)
- **Cause.** `pan_subgroup_size()` returns 8 for every v7 GPU; Mali-G31/G51 (v7.0) have 4-wide warps (lane losses in the
  repros always come in groups of 4). The compiler used the 8-lane WMASK/CLPER subgroup forms and wrong
  subgroup_id/num_subgroups, and panvk/gallium reported 8.
- **Fix.** 55fb9c9c4d3: `pan_subgroup_size_gpu(gpu_id)` (4 for v7.0), used by the Bifrost compiler, gallium
  (rusticl subgroup sizes, shader info) and panvk (subgroupSize, min/max, warps per core, executable properties).
- **Result.** OpenCL now reports a preferred work-group multiple of 4. `dEQP-VK.subgroups.basic.compute.subgroupelect`
  (MESA_VK_VERSION_OVERRIDE=1.3, PANVK_DEBUG=sync) still ends with "Incomplete job or timeout" on both the system
  panvk and the fork, with no INSTR_INVALID_ENC in dmesg this time; the hang has another cause (open, Vulkan agent).

### 5. API min_max_mem_alloc_size (1)
- **Cause.** Not a driver bug. panfrost reports max_mem_alloc = global = `os_get_gpu_heap_size()`, which is 25% of RAM on
  boards with <= 1 GiB (243 MiB here). That is above the spec minimum (128 MiB), but the CTS halves the reported value
  (MAX_DEVICE_MEMORY_SIZE_DIVISOR) before comparing with 128 MiB, so any device under 256 MiB fails.
- **Fix (image config, not code).** driconf `heap_memory_percent=0.3` (292 MiB): test passes (146 MiB after the CTS
  halving). Suggested image file `/etc/drirc.d/50-opiz2-panfrost.conf` with `<option name="heap_memory_percent"
  value="0.3"/>` for driver panfrost; left for the image owner to decide because it raises the GPU heap cap.

### 6. GLES KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence
- **Findings.** Deterministic: first pixel correct (32,32,32,255) but not all 1024x1024 pixels equal. With
  `MESA_EXTENSION_OVERRIDE=-GL_KHR_blend_equation_advanced_coherent` (test uses glBlendBarrier between draws) it
  **passes** (1.4 s). No GPU timeouts in either run (the sched timeout seen once came from the PAN_MESA_DEBUG=sync run).
  So the coherent fbfetch path (several advanced-blend draws in one fragment job) is not coherent on the G31, while
  multiplySequence (7 draws) and the other 86 blend_equation_advanced cases pass. Tried and rejected: making v7.0 use
  the v6 NOP-before-first-clause (in case the RSD shader_wait_dependency_6/7 bits are ignored): no change.
  Mesa CI runs this test on the G52 (v7.2) with no failure listed, so this looks G31/v7.0 specific.
- **Not fixed.** I did not stop advertising GL_KHR_blend_equation_advanced_coherent: in st_extensions it is tied to
  `fbfetch_coherent`, which also gates EXT_shader_framebuffer_fetch, whose dEQP tests pass; dropping it would remove a
  working feature. Options for the owner: (a) keep as is (1 known fail), (b) add a separate panfrost cap so only
  KHR_blend_equation_advanced_coherent is dropped on v7.0, (c) dig further (pandecode of the fragment job, compare with
  the Arm blob trace).

### 7. Still failing, analysed but not fixed
- **Math (wimpy, 50 subtests).** All the baseline "huge ulp / NaN / 0xffffdead at index 0" errors are wrong *whole
  buffers*, not precision: the result belongs to another iteration's input. Proven by running the same functions with
  `CL_TEST_SINGLE_THREADED=1` (PASSED 10 of 10) or with `-b` host fill (PASSED 10 of 10), while the default
  multi-threaded run with clEnqueueFillBuffer fails (FAILED 2 of 5 functions on the 5-function subset). So it is a race
  between several command queues (one per CTS thread) on sub-buffers of one parent buffer, around
  clEnqueueFillBuffer/rusticl meta clear kernels. A 4-thread ctypes repro of the same pattern (`t_mt.py`) does not
  trigger it, and a panfrost change that stops BO shadowing when several contexts exist did not help (reverted).
  The real fp16 ULP errors (about 1400 ULP at half subnormals) could not be separated from this yet.
- **Thread Dimensions (3).** quick_2d/3d still fail. Repro `t_tdim.py` (16384x4096 grid, local 256, ulong index +
  atom_add) loses exactly one row (16368 of 16384 items) in two of three windows; the same kernel without the
  out-of-range error path (`t_tdim2.py`) passes.
- **Basic enqueue_map_image (1).** IMAGE3D with ALLOC_HOST_PTR|COPY_HOST_PTR: "Sample 168218 (coord 0,4,0) Got 0,
  expected 126". -> Root cause found and fixed host-side (rusticl sw_copy fast path, a0a4534b14d), see "Mesa-side
  fixes" below; board confirmation = runner job 09-opencl-mesa2 chunk basic-b.
- **Samplerless 1Dbuffer int/uint/float (3).** Every format fails at the first size (e.g. width 329, CL_R
  SIGNED_INT8). -> Root cause found and fixed host-side (texel-buffer attributes never emitted, ec376a8ee7e), see
  "Mesa-side fixes" below; board confirmation = job 09 chunk sl.
- **Images Kernel 2D float (1).** CL_RGB UNORM/SNORM_INT8 2D *array* reads return NaN. -> Analysed below (one lost
  16-byte result per subtest, integer-coordinate reads only, seen once on the baseline); rerun on the fork = job 09
  chunks f2d-*.
- **Integer Ops quick_(u)long_math.** 64-bit division/modulo give wrong values for some elements (pairs at index 14/15
  mod 16). -> Root cause: kernel job timeout + GPU reset, see the section below. Math (multi-threaded) and Thread
  Dimensions are expected to be the same.

## Root cause: panfrost job timeout (2026-11-05, agent opencl-fixes-2)

**Integer Ops quick_(u)long_math `/` and `%` are not a compiler bug.** Established host-side, without the board:
- Interpreters for the Bifrost dumps (`mesa-work/oclfix/host/biemu.py` for the pre-/post-RA MIR, `biemu3.py` for the
  final disassembly with tuples, passthrough t/t0/t1, staging registers and clause-end load delivery; copies in
  `harness/analysis/gpu/oclfix/host/`) run the long16 division shader on the exact failing CTS inputs
  (`pairs-cts.txt`) and on the CTS random distribution: 0 wrong results at every stage, both for the precomp-tool
  compile (`panfrost_compile`, 16:53 spills) and for the real rusticl compile (167:1601 spills). The real shader comes
  from host rusticl on the panfrost drm-shim as a fake G31 (`build-shim.sh` -> `mesa-work/build-host-shim`, asserts on;
  `shim-env.sh`, `hostcl.py` drives rusticl through its ICD dispatch table; PAN_GPU_ID=7093 PAN_SHADER_PRESENT=1; the
  shim needed the GET_PARAM additions committed as 45a7a7147d5 on the fork branch). `hazard.py` found no same-clause
  register hazards.
- The CTS data says the failures are positional, not data dependent: every work-item from one item on (28632 for long
  `/`, 54405, 45804, 62428 for the other three) has elements 14/15 (the last 16-byte store of the kernel) stale while
  0-13 are right; "got" values are 0 or old quotients, i.e. the buffer content before the kernel. Only the long16
  division/modulo kernels are long enough to matter (65536 items x ~1900 clauses, > 500 ms).
- `mesa-work/oclfix/b2/dmesg.txt` from that run has exactly four
  `panfrost 1800000.gpu: gpu sched timeout, js=1, config=0x7300, status=0x8, head=..., tail=...` lines (status 0x8 =
  ACTIVE), one per failing subtest.
- Kernel (drivers/gpu/drm/panfrost/panfrost_job.c): JOB_TIMEOUT_MS = 500 -> panfrost_job_timedout -> panfrost_reset:
  JS_COMMAND_SOFT_STOP on every slot, handle the STOPPED IRQ (`job->jc = JS_TAIL`, fence not signalled, so the job is
  resumed), then **panfrost_device_reset (GPU_CMD_SOFT_RESET, no cache clean)** and drm_sched_resubmit_jobs. The soft
  reset discards the dirty L2 lines (results of the tasks finished since the last write-back, and the hardware's resume
  state in the job header), the resumed job completes and reports success. Math's `0xffffdead at index: 0` (14 lines in
  the baseline log: the CTS fill pattern survives because the kernel's stores were lost), Thread Dimensions' lost rows
  (quick_2d/3d: 64 M items, multi-second jobs) and the Images Kernel 3D int/uint/float 5000 s timeouts (a job reset and
  resumed every 500 ms) fit the same mechanism; the runner job checks them.
- Fix: branch `fix/sunxi-panfrost-softstop-resume` (above). On timeout with JS_STATUS == ACTIVE: soft-stop (100 ms
  drain instead of 10), no karma, no core dump, no GPU reset; resubmission resumes the job from JS_TAIL as before. Faults,
  soft-stop failure and the MMU-fault reset path still reset. Upstream still has the 500 ms reset (checked linux-7.3.1).
- Board validation: runner job `harness/runner-queue/06-opencl-timeout-fix.md` (package
  `harness/research/opencl-fixes/runner/`): Integer Ops, Thread Dimensions, Math in two halves (default multi-threaded),
  a regression subset of 19 passing suites, Images (Kernel 3D int), dmesg must stay free of timeouts/faults. Needs the
  next cumulative kernel to contain the branch (the script blocks otherwise).

### Oops on c14 and the follow-up 0b7e3a208 (2026-11-05, agent panfrost-softstop)

e544ddb00 alone crashed cumulative kernel c14 about 2 min into the Integer Ops chunk
(`logs/runner-timeout-fix/serial-crash-c14.txt`): `Unable to handle kernel NULL pointer dereference at virtual address
00000000000000f8`, pc `panfrost_dequeue_job+0x2c` from `panfrost_jm_handle_irqs+0x268` in the job IRQ thread (0xf8 =
`job->is_profiled` of a NULL `pfdev->jobs[slot][0]`), then `panfrost_jm_ctx_destroy` hangs in `panfrost_postclose`, a
`panfrost-reset` workqueue lockup, reboot at 21:00.

Root cause: panfrost_reset() waits for the soft-stops by polling **JOB_INT_JS_STATE, which is not live**. kbase's register
map documents it as "status==active and _next == busy snapshot from last JOB_IRQ_CLEAR" (panfrost's own IRQ handler says
the same). For a job started into an idle slot (rusticl submits one kernel at a time, so the last CLEAR saw the slot
idle) the snapshot reads idle and the wait returns at once, before the soft-stop has done anything. Upstream never
noticed because the GPU reset that follows kills the job regardless. Without the reset (e544ddb00) the sequence is: wait
returns, `panfrost_jm_handle_irqs` finds nothing, the leftover loop drops the job from `pfdev->jobs[]`, resubmission
writes the job again into `_NEXT` with START while the first incarnation is still stopping. Then either
(a) the first run reports STOPPED: the ERR handler writes NOP to `_NEXT` (cancels the resubmission), dequeues the job,
records TAIL, and nothing restarts it; 500 ms later the watchdog sees status 0x3, not ACTIVE, and resets after all
(no crash, but the fix is defeated); or (b) the first run reports DONE (jobs of ~500-600 ms, the Integer Ops long16
division case, are about to finish when the watchdog fires): the handler dequeues the resubmission's entry and signals
the fence, the job manager auto-starts `_NEXT` after a DONE, and that second run completes on a slot with no software job
-> `panfrost_dequeue_job` on NULL. The checked hypotheses that were wrong: no refcount problem (the job object is kept by
the scheduler across the resubmission), no STOPPED-handling problem (the STOPPED path is kbase's: TAIL, resume).

Fix 0b7e3a208 (`patches.armbian/drm-panfrost-wait-for-the-soft-stopped-slots-with-the-live-status.patch`, on
fix/sunxi-panfrost-softstop-resume on top of e544ddb00, pushed to fork): poll the live `JS_STATUS(i)` of every slot until
none reads ACTIVE (0x08) (`read_poll_timeout(panfrost_slots_idle, ...)`, 100 ms for an active job, 10 ms otherwise,
"Soft-stop failed" + reset on expiry as before), so the pending DONE/STOPPED interrupt is handled before the
resubmission (DONE -> jc = 0, skipped; STOPPED -> resumed from TAIL); hold a runtime PM reference across the stop and the
resubmission (the stopped job's `pm_runtime_put_autosuspend` could otherwise let the 50 ms autosuspend power the L2 off
under the soft-stopped job); `panfrost_dequeue_job` returns NULL for an empty slot (WARN, not Oops; every caller copes).
Compiled with the kernel's own flags (`.panfrost_job.o.cmd` of the c17 tree) plus `-Wextra -Werror`; checkpatch clean
except the quoted Oops line. The design stays soft-stop + resume (kbase's time-slicing), not a plain "re-arm the
timeout": a job that never stops still gets reset after 100 ms of not stopping.

Board validation: runner job `harness/runner-queue/18-panfrost-softstop.md` (same package, fix check now requires
0b7e3a208, needs c18+). New first chunk `stress`: Integer Ops quick_(u)long_math x2, Thread Dimensions quick_2d x1, the 7
Vulkan spirv_assembly vec4 frag long jobs x2 (panvk from /root/opiz2-mesa/cl, PANVK_DEBUG=sync); fail-fast on
`Unable to handle|Oops|workqueue lockup|panfrost_dequeue_job` in the serial log (watched during the chunk) or dmesg
(exit 3, logs/runner-timeout-fix/OOPS). Held jobs 08, 09, 14, 15 stay held until it passes.

Open after this (not timeout related, still Mesa-side, next agent): Images (Samplerless int/uint/float) 1Dbuffer at
width 329 and Basic enqueue_map_image IMAGE3D -> both fixed in "Mesa-side fixes" below (agent opencl-mesa2); Images
(Kernel 2D float) CL_RGB UNORM/SNORM_INT8 2D array reads NaN (analysed there, board rerun pending), blend_equation_advanced
mixedSequence. Math's real fp16 ULP errors (about 1400 ULP at half subnormals) can only be separated once the timeout fix
is on the board. Note for the subgroup commit 55fb9c9c4d3: `panfrost_compile` passes gpu_id = arch << 28 (minor 0), so
the precompiled libpan shaders for every v7 GPU are now built for 4-wide subgroups; right for the G31, wrong for a G52
image if those shaders ever use subgroup ops (none do today).

## Full rerun on the fork (commit 9049a3c5f2c): PAUSED 2026-11-05 ~18:33 (user credit limit)

Fork Mesa 9049a3c5f2c is deployed at `/root/opiz2-mesa/cl`. Results are on the board in `/root/oclfix/full-9049a3c/`
(opencl-mesa/binaries.csv, results.csv, logs; kernel-versions.txt has `uname -r` per chunk).
The run before chunking was on kernel 7.3.1-edge-sunxi64. Chunks cl1 and cl2 ran after VP9 round 4 had ended:
their kernel (expected cumulative c2) is in kernel-versions.txt and still has to be copied into this table.

| suite | baseline (8546e5fc1) | fork 9049a3c5f2c |
|---|---|---|
| Compute Info, Compiler, Common Functions, Geometric Functions | pass | pass (3/3, 73/73, 18/18, 8/8) |
| Basic | FAILED 3 of 108 | FAILED 1 of 108 (enqueue_map_image) |
| API | FAILED 1 of 149 | FAILED 1 of 149 (min_max_mem_alloc_size, heap config) |
| Images Kernel Methods / 1D int / 2D int / 1D uint / 2D uint / API Info | pass | pass |
| Relationals | crash | PASSED 17 of 17 |
| Atomics | FAILED 8 of 13 | PASSED 13 of 13 |
| Thread Dimensions | FAILED 3 of 6 | FAILED 3 of 6 (open) |
| Profiling, Events, Printf, Device Partitioning, Buffers | pass | pass |

Earlier spot runs on the fork (batch11/12, same build plus at most the later-reverted experiments): Half PASSED 13 of 13
(was 5 failed), C11 Atomics 32/32, math5 subset still FAILED 2 of 5, samplerless int/uint still fail,
blend_equation_advanced 87/88 (mixedSequence only).

A first full GLES attempt was OOM-killed: it ran under MemoryMax=700M without OOMPolicy=continue. The GLES
chunks now use the queue's settings: MemoryMax=600M, MemorySwapMax=64M, OOMPolicy=continue.

**Resume.** These are host scripts in `mesa-work/oclfix/tests/` (copies in `harness/analysis/gpu/oclfix/`):
1. `chunks.sh`: runs chunks of 20 min or less and re-queues FIFO for the lock between chunks. It resumes from
   `mesa-work/oclfix/chunks/*.done`; cl1 and cl2 are done, so **the next chunk is cl3** (Images Kernel 1D float).
   Then come cl4-cl7 (see `cl-chunks.txt`), clsplit1-8 (Kernel 2D float and clCopyImage 2D, split by image type,
   `cl-split.txt`), and the GLES chunks gles31-khr-main and gles31-main.0-4 (`lists/`).
2. `slot3d.sh`: Images Kernel 3D int/uint/float, no timeout, one type per unit. It starts after `chunks/all.done`
   and acquires only when the lock is free with an empty queue.
3. When both are done, compare the GLES results with `mesa-work/oclfix/baseline/gles31-*` (1 Fail and 2 OOM in
   main, 1 Fail in khr) and finish the table above.

Still to do after the run: copy the kernel version per chunk into the table, then report the numbers to the
coordinator (handback).

## Mesa-side fixes (2026-11-05, agent opencl-mesa2): samplerless 1Dbuffer, enqueue_map_image 3D, Kernel 2D float RGB

All host-side, no board. Fork commits ec376a8ee7e and a0a4534b14d (plus c6e6e63990b for the shim); build for the board
done in `mesa-work/build-cl` (libRusticlOpenCL md5 180855aa3acd...); runner job `harness/runner-queue/09-opencl-mesa2.md`
(package `harness/research/opencl-fixes/runner-mesa2/`, results will be in `harness/research/opencl-fixes/logs/runner-mesa2/`)
deploys it as `/root/opiz2-mesa/cl2` and runs the affected suites + a regression subset on the stock kernel.

**Host tooling added** (`mesa-work/oclfix/host/`, copies in `harness/analysis/gpu/oclfix/host/`):
- `hostclk.py`: clk.py-compatible ctypes runner on the shim through rusticl's ICD dispatch table (the shim build exports
  no cl* symbols; indices resolved from the table's pointers against `nm`, e.g. clCreateImage = 96, clEnqueueMapImage =
  57). Images, samplers, maps, read/write image, supported formats. Run it with `python3` (not `-I`), after
  `. shim-env.sh`; use `/usr/bin/python3` when numpy is needed (the venv python has none).
- Shim fix c6e6e63990b: `SYNCOBJ_HANDLE_TO_FD` now returns a signalled eventfd, so panfrost_fence_create() works and
  clFinish()/blocking maps no longer hang (the rusticl worker thread used to panic on "export failed"). Nothing
  executes on the GPU, but every CPU path (uploads, maps, copies) really runs, and `PAN_MESA_DEBUG=trace
  PANDECODE_DUMP_FILE=/tmp/x` dumps the full job chain (shader disassembly, texture/sampler/attribute descriptors).
- `t_sl1db.py` (CTS samplerless 1Dbuffer kernel, `SWAP=1` puts the buffer image second), `t_rd2da.py` (CTS 2D-array
  float read kernel), `t_map3d.py` (random map/unmap checks per image type), `t_map_cts.py` (exact replay of
  basic/enqueue_map_image with the CTS MT19937 stream via numpy's `MT19937._legacy_seeding(0)`).

### Samplerless 1Dbuffer int/uint/float (fixed: ec376a8ee7e)
- The pandecode dump of the exact CTS kernel showed texture slot 0 (the `image1d_buffer_t`) as a null descriptor and
  the shader reading the buffer image through `LEA_ATTR_IMM attribute_index:0` + `LD_CVT`: on Bifrost, panfrost reads
  texel buffers through the attribute table (`pan_nir_lower_tex.c` bi_lower_txf_buf, `pan_nir_lower_res_indices.c`).
  The compute job had `Attribute count: 0`, `Attributes: 0x0`: `panfrost_emit_image_texbuf_attribs()` returns early
  when `shader->info.attribute_count == 0`, and pan_compiler.c derives that count from `shader_info::texture_buffers`,
  which only the GLSL path (gl_nir_lower_samplers_as_deref) ever filled. OpenCL kernels go through
  `nir_lower_cl_images`, which only set `image_buffers` (write images). Upstream main has the same gap (the CI runs the
  CL CTS on T860 and G610 only, neither uses attributes for texel buffers).
- Fix: `nir_lower_cl_images` sets `texture_buffers` for read-only buffer images. Dump after: `Attribute count: 1`,
  attribute R8I on a 1D attribute buffer (stride 1, size 0x149 = 329); with the buffer image as texture 1 (`SWAP=1`):
  count 2, attribute 1 = R32F, LEA_ATTR attribute_index:1, attribute 0 a CONSTANT placeholder.
- Why the earlier board repro `t_img1db.py` passed is unexplained (its kernel also stores both raw reads, which the
  host dump of that kernel could settle); the CTS kernel's dump above and the code path are authoritative, and job 09
  chunk sl is the confirmation.

### Basic enqueue_map_image IMAGE3D (fixed: a0a4534b14d)
- `t_map_cts.py` reproduced the CTS failure byte for byte on the shim (no GPU involved): flag set
  ALLOC_HOST_PTR|COPY_HOST_PTR, IMAGE3D 64x64x64, format RG SIGNED_INT8 (pitch 128), second map origin (26,0,41) region
  (4,64,9): rows 0-3 of the mapped region were right, row 4 byte 0 "got 0 exp 126" = sample 168218, exactly the CTS
  line. The first map region (0,54,57)+(43,7,4) is unrelated, so nothing zeroed that pixel: the map simply did not copy
  it.
- Cause: `sw_copy()` (used by Image::read for maps/clEnqueueReadImage) has a whole-slice fast path guarded by
  `region[1] * pixel_size == src_row_pitch`, i.e. the ROW COUNT times the pixel size instead of the row length
  (`region[0]`). 64 rows x 2 B == 128 matched, so it memcpy'd `region[0]*region[1]*pixel_size` = 512 bytes per slice
  from the slice start and left the rest of the map uninitialised. `Buffer::copy_rect()` and `Buffer::write_rect()`
  (clEnqueueCopyBufferRect / WriteBufferRect / image-from-buffer copies) have the same `region[1] == src_row_pitch`
  test. Upstream main still has all three.
- Fix: compare `region[0]` (times pixel_size for sw_copy). After it the full replay of all CTS flag sets (ALLOC, ALLOC|
  COPY, USE, COPY, 0; 5 image types x 72-74 formats x 4 maps) reports FAILS 0 and random maps (`t_map3d.py`, 12 per
  format, 3D/2Darray/1Darray/2D) BAD 0.

### Images Kernel 2D float: CL_RGB SNORM/UNORM_INT8 2Darray NaN (analysed, board rerun pending)
- Baseline log: the 4 failures are all 2Darray RGB8 reads with *integer* coordinates (`read_image (integer coords,
  float results)` section, CLAMP_TO_EDGE and CLAMP), one sample per subtest with `(-nan,-nan,-nan,-nan)` = the 0xff
  pre-fill of the results buffer, i.e. one work-item's 16-byte result never landed. The same kernel/coords (same seed per
  subtest) fail at different sample indices (2624, 3852, 2508, 3084) for SNORM vs UNORM and CLAMP vs CLAMP_TO_EDGE,
  so it is not coordinate- or data-determined; the float-coordinate variants of the same formats and all other formats
  pass. Host dump of the kernel: texture descriptor RGB8 UNORM 21x32, 14 layers, row stride 64, surface stride 2048,
  shader F32_TO_U32 (layer) + TEXC + STORE.i128 in the last clause; nothing format-specific in rusticl's lowering.
- It was only ever seen on the baseline (system Mesa 26.2.4 + stock kernel); the fork's chunk run never reached this
  suite. Job 09 splits it into 4 chunks (read 2D, read 2Darray, write, read_write). If f2d-r2da still fails on the fork
  the next step is a board repro with the integer-coordinate kernel on RGB8 2Darray images, checking `dmesg` for a
  job timeout (the reset loses dirty L2 lines; see the kernel section) and varying the local size.

## Shipping

The image uses Ubuntu's mesa 26.2.4-1ubuntu1, so ship the branch as Debian patches on that package:
1. `git -C mesa-work/mesa-cl format-patch mesa-26.2.4..panfrost-opencl-fixes` (21 patches incl. the two drm-shim ones, which can be dropped from the Debian series; drop the
   .pick_status.json hunks if quilt complains), put them in `debian/patches/opiz2/` of the Ubuntu source
   (`mesa-work/oclfix/dl-ubuntu-mesa/`) and append them to `debian/patches/series`.
2. Bump to `26.2.4-1ubuntu1+opiz2.1` (dch), build with `dpkg-buildpackage` in an arm64 chroot or on the board
   (needs root, the user runs it), and add the resulting libgl1-mesa-dri, libegl-mesa0, libgbm1, mesa-vulkan-drivers,
   mesa-opencl-icd, mesa-libgallium debs to the image with `apt-mark hold` so the Ubuntu archive does not replace them.
3. When Ubuntu moves to 26.2.6, the 12 stable cherry-picks drop out; the remaining ones are the two upstream main
   cherry-picks and our five patches (SEG_ADD RA, subgroup size, trailing barrier, texture_buffers, sw_copy). Ours are AI-generated:
   per the user, they stay in our fork and are not sent to Mesa without asking.
