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
| 02df5721016 | pan/layout: leave a cache line of slack after 24/96-bit images (CL_RGB page faults; board A/B = job 46) | ours (Generated-by: LLM) |

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

### Job 18 on c25: why the soft-stop failed (2026-11-06, agent panfrost-softstop2)

Summary harness/runner-queue/done/18-panfrost-softstop.summary.md, logs logs/runner-timeout-fix/. No Oops. What the logs
show (dmesg line counts via the chunk's `DMESG-START` values: stress 655 -> intops 1633 -> tdim 1673 -> math-a 1674 ->
img3d 1674):
- **stress**: the compute long jobs passed, twice: INTOPS quick_long_math + quick_ulong_math `PASSED 2 of 2` (t=76 s,
  22 s), TDIM quick_2d_explicit_local `PASSED test.` (156 s); 5 of the 7 Vulkan fragment long jobs passed in 4-28 s. So a
  soft-stopped job *is* resumed correctly from JS_TAIL, compute and fragment alike. The chunk failed its 870 s limit
  because the two `count64` fragment cases (i8 bit_field_insert_offset16_count64_frag, u64 ..._offset8_count64_frag) hit
  their 200 s limit, twice, and the chunk was cut off before its dmesg step: the ~978 dmesg lines of the stress period
  (655 -> 1633) were never captured. The cut-off also orphaned the running `timeout 200 ./deqp-vk` (the inner `timeout`
  makes its own process group, the chunk's SIGTERM does not reach it).
- **intops**: the 39 `Soft-stop failed` lines (uptime 931-954 s, one every 0.6 s = 500 ms watchdog + 100 ms wait) are
  the tail of that orphaned deqp-vk case, which died at its own 200 s limit at ~02:41:45: every 600 ms the fragment job
  failed to reach a task boundary within the 100 ms budget, the GPU was reset and the job restarted from its head, so it
  never progressed (that is why the count64 cases never finish: ~3 x 330 lines = the 978 uncaptured ones). Integer Ops
  itself then ran to `integer_divideAssign` and hung there until the 800 s CTS limit with **zero** kernel messages; its
  jobs were either silently soft-stopped/resumed many times or never timed out: not distinguishable without a counter
  (fixed in the package: ftrace count of panfrost_job_timedout per chunk).
- **math-a**: FAILED 34 of 54 with zero kernel messages (no timeout, no reset, no soft-stop failure), 3 stale-buffer
  lines (`0xffffdead`/`at index: 0`, atan2/fdim/fmax) and the rest huge-ULP / NaN errors of whole wrong buffers. With no
  watchdog hit in the chunk this is the rusticl multi-queue race of section 7 (proven there with
  `CL_TEST_SINGLE_THREADED=1`: PASSED), not the kernel. The brief's "0xffffdead = wrong result from a resumed job or a
  killed job?" is therefore: neither on c25; the stale buffers came without any soft-stop. The *potential* kernel path for
  stale data did exist, though: a job soft-stopped on one slot (jc = JS_TAIL) while another slot's job failed to stop ->
  GPU reset -> the stopped job resumed from JS_TAIL with its header/L2 state gone -> completes with stale data and no
  error. Closed by e17629bba (below).
- **math-b**: `'recip' did not match any test names`: the CTS registers it as `half_recip` (HALF_ENTRY). Package bug.
- **tdim / img3d**: Timeout at 800 s with 1 / 0 kernel messages; the full quick* set is 6 jobs of 64 M items each
  (quick_2d_explicit_local alone took 156 s with resume), so the 800 s budget is simply too small; same for Images
  (Kernel 3D int), which never finished before either.
- **reg**: 19/19 PASS, no regression from the resume path.

Root cause of `Soft-stop failed`: the 100 ms soft-stop budget. A soft-stop takes effect at a task boundary only, after
the tasks already issued (a compute job's work-groups, a fragment job's tiles) have completed, and a heavy fragment shader
(64-bit bit-field emulation per fragment) needs seconds for that. Arm's kbase (kernel-check/kbase-trial/src, bifrost
mali_kbase_config_defaults.h + backend/gpu/mali_kbase_js_backend.c): soft-stop after JS_SOFT_STOP_TICKS = 1 tick (100 ms
scheduling period), hard-stop at JS_HARD_STOP_TICKS_SS = 50 ticks (5 s) if the job has not stopped, GPU reset at
JS_RESET_TICKS_SS = 55 (5.5 s); on STOPPED the atom's jc is set to JS_TAIL and it is requeued (mali_kbase_jm_rb.c
kbase_gpu_complete_hw); every atom that was on the hardware at a reset is failed with BASE_JD_EVENT_JOB_CANCELLED, never
resumed (kbase_backend_reset). The JS_COMMAND is right (plain SOFT_STOP stops the current chain unconditionally; kbase
uses the _0/_1 variants only because it targets one atom of two), JS_CONFIG needs no flag, and the hard-stop fallback
was missing.

Fix: branch `fix/sunxi-panfrost-softstop-budget` from test-cumulative (04964f921), commit e17629bba, pushed to fork,
unmerged (worktree wt-panfrost-softstop2; patch
patches.armbian/drm-panfrost-hard-stop-a-job-that-does-not-soft-stop-and-never-resume-across-a-reset.patch, third in the
series): an active slot gets JOB_SOFT_STOP_TIMEOUT_MS = 5000 to go idle (idle/faulted slots keep 10 ms); slots still
ACTIVE are hard-stopped (plain JS_COMMAND_HARD_STOP, the job ends TERMINATED -> -ECANCELED, nothing is reset, the other
stopped jobs resume); the GPU is reset only if the hard stop has not taken effect after JOB_HARD_STOP_TIMEOUT_MS = 500,
and the job still running on that slot is failed (finished fence -ECANCELED) instead of restarted from scratch (the
600 ms reset loop of job 18); `pfdev->reset.count` is bumped by every reset, a job records it when soft-stopped
(`job->stopped`, `job->stop_reset_count`) and panfrost_job_run() fails it with -ECANCELED instead of resuming it when the
count moved; the no-reset path now calls panfrost_mmu_as_put() for the jobs that were waiting in _NEXT (the reset path
has panfrost_mmu_reset() wipe those refs; without a reset they leaked one as_count per cycle, WARN_ON at 4 and the AS
could never be reassigned); the failure messages carry all three slot statuses. Compiled with the c25 tree's own W=1
-Werror flags (`.panfrost_job.o.cmd`), checkpatch --strict clean, applies to the c25 tree. Deferred (notes): the 5 s
wait blocks the reset worker, so the stopped jobs on the other slots idle for up to 5 s while one job refuses to stop;
kbase stops only the one slot. A redesign that returns NO_HANG from timedout_job and resumes from the IRQ handler would
remove that and the drm_sched_resubmit_jobs dependency.

Package (runner job harness/runner-queue/28-panfrost-softstop2.md, same dir, job name `softstop2`, results
logs/runner-softstop2/, board dir /root/oclfix/softstop2 so clcts-run.py does not resume from job 18's rows): stress is
compute only; the Vulkan cases are their own chunks (vk: 5 short cases x2 at 80 s; vklong: the 2 count64 cases x1 at
400 s); inner timeouts use `--foreground` so the chunk limit reaches them, and every chunk kills the previous chunk's
process group (exact pgid file); the host collects dmesg (from the chunk's DMESG-START) and the ftrace count of
panfrost_job_timedout after the chunk, cut off or not; tdim runs `quick_2d quick_3d` directly; math-b says half_recip;
math verdicts separate the Mesa race (stale lines with TIMEDOUT = 0) from a kernel suspect (stale lines with TIMEDOUT > 0).

### Job 28 on c27: soft-stop series PASS; the img3d page fault (2026-11-06, agent panfrost-img3d)

Summary harness/runner-queue/done/28-panfrost-softstop2.summary.md, logs logs/runner-softstop2/. The kernel series
(e544ddb00 + 0b7e3a208 + e17629bba) works: stress, vk (10/10), vklong (both count64 cases Pass in 4-5 s), intops (59/59),
reg (19/19), no Oops, no `Soft-stop failed`. Open items:
- **img3d page fault** (`Unhandled Page fault in AS0 at VA 0x000000000B2F8000`, `js fault, js=1, status=JOB_BUS_FAULT,
  head=tail=0xa09f200`): it is the CTS subtest `[CL_RGB CL_SIGNED_INT32] CLAMP_TO_EDGE`, integer coords (the only FAILED
  line of files/img3d/logs/Images_Kernel_3D_int_.log: sample 70422 `got (ffffffff,...)` = the 0xff results pre-fill, i.e.
  the compute job was killed at about z = 22 of 32 and the remaining work-items never stored; the fault line comes after
  the img3d chunk's DMESG-START, and this subtest is the only failure). **Not the soft-stop/reset path**: the chunk's
  ftrace count of panfrost_job_timedout is 0 (no watchdog, no soft-stop, no reset before the fault), and the only panfrost
  change between c25 and c27 is e17629bba, which only runs on a timeout. Job 18 on c25 ran the identical subtest (same CTS
  seed, same Mesa 9049a3c5f2c) and passed: the fault is intermittent. Kernel code checked (c37 tree): the fault is a
  translation fault on an address that belongs to no BO (panfrost_mmu_map_fault_addr finds no mapping, not a heap BO);
  BOs a job uses are pinned (job->mappings refs, shrinker skips gpu_usecount > 0, Mesa's cache drops purged BOs), maps
  flush the AS (or the AS is re-enabled with FLUSH_MEM), so a kernel unmap under a running job has no path here. Mesa:
  the shim dump of the CTS kernel on a 25x128x32 RGB32I 3D image (mesa-work/oclfix/host/t_rd3di.py, PAN_MESA_DEBUG=trace)
  shows the plain hardware path: TEXC through a linear RGB32I 3D texture descriptor (row stride 320, surface stride
  40960, 32 slices = 0x140000 bytes = the BO size, page aligned), sampler CLAMP_TO_EDGE, int coords converted to
  float + 0.5; nothing format-specific in the shader. The fault address is page aligned, which fits an access that runs
  past the end of a BO into an unmapped page (the image BO ends exactly on a page boundary, so a hardware over-read of
  a few bytes for the 12-byte texel format would fault only when the VA after it is a hole, which depends on the BO
  allocation order: intermittent). Not proven: the fault report carries no BO information and the package's dmesg filter
  dropped the access type / source id lines.
  Kernel diagnostic fa9d166f6 (fix/sunxi-panfrost-fault-bo-info, worktree wt-panfrost-faultinfo, patch
  drm-panfrost-name-the-bos-around-an-unhandled-page-fault.patch, merged test-cumulative 76bd27766 = c38): on an unhandled
  fault print the BO containing the address or the nearest BO below/above (VA range, size, `end+0x..` distance, mapped or
  not, heap/noexec, Mesa label = use/format/size). Runner job 45-panfrost-img3d (package runner/, `ocl-job.sh img3d`,
  checks in runner/HANDOFF-img3d.md): CL_RGB SIGNED_INT32 3D read x4, RGB UNSIGNED_INT32 x2, RGB FLOAT x1, RGBA SIGNED_INT32
  control x1, full dmesg of the fault (the filter now keeps Reason/raw fault status/access type/source id/`fault bo:`/
  Purging lines). Next agent: `fault bo: below ... fault at end+0x0..0xfff` on the RGB32 texture BO = texture over-read
  -> pad linear 96-bit textures in pan_layout (Mesa fork) and repro; `inside ... NOT mapped` = kernel; far from any BO =
  a bad descriptor pointer (Mesa).
- **img3d Timeout**: the CTS was still progressing at the 800 s limit (log cut in the `unnormalized float coords` section,
  further than job 18), TIMEDOUT 0: the full Images (Kernel 3D int) suite simply needs more than 800 s on the G31; not a
  hang. It needs the no-timeout slot (slot3d.sh) of the full rerun, not a chunk.
- **tdim**: package bug, `quick_2d`/`quick_3d` are not test names (the CTS registers quick_{1,2,3}d_{explicit,implicit}_local).
  Fixed in ocl-job.sh (tdim uses the four 2D/3D names; job img3d has tdim2/tdim3 chunks).
- **math-a / math-b**: FAILED 32/54 and 19/34 with stale-buffer lines and TIMEDOUT 0 = the rusticl multi-queue race of
  section 7 again (no kernel involvement); unchanged, left as is.

### Job 45 / job 09 RGB faults and tdim (2026-11-06, agent opencl-rgb)

Inputs: done/45-panfrost-img3d.summary.md (c38, fork /root/opiz2-mesa/cl = 9049a3c5f2c), done/09-opencl-mesa2.summary.md
(stock #17, cl2 = dc7266d584b), logs runner-img3d/ and runner-mesa2/.
- **Job 45**: the 8 image chunks (RGB32I x4, RGB32UI x2, RGB32F, RGBA32I) PASS with F = 0: the job-28 fault did not
  reproduce (intermittent).
- **Job 09 f2d-r2da** (no diagnostics kernel): `Unhandled Page fault in AS0 at VA 0x000000000A016000` x2 + JOB_BUS_FAULT
  js=1. From the dmesg timestamps (sl chunk's INSTR_INVALID_ENC at 181.8 s fixes boot at 12:03:28-12:05:12) the faults
  fall in the first ~70 s of f2d-r2da (started 12:39:28), i.e. the CL_RGB section, not the INTENSITY subtest where the
  chunk was cut. The 4 FAILED subtests are the CL_RGB SNORM/UNORM_INT8 2Darray UNNORMALIZED reads. Correction to the
  earlier "one lost 16-byte result" reading: the CTS reports only the FIRST mismatching sample, so a job killed in the
  middle (first lost sample 1548-2632 of 9408) fits exactly.
- **Over-fetch hypothesis (not proven on the hardware yet)**: both faulting VAs are page aligned; both faulting images
  have data that ends exactly on a page boundary (21x32x14 RGB8: row 64, layer 2048, 28672 B; 25x128x32 RGB32I: row
  320, slice 40960, 0x140000 B) with the last texel in the last 64 B cache line; the integer-coordinate tests clamp
  random out-of-range coordinates to the edge, so the last texel is read often; RGBA and the other formats never fault.
  A texture-unit read of the cache line after a 24/96-bit texel faults at exactly BO end (page aligned) when the
  kernel's best-fit VA allocator left a hole there, and is harmless when the next BO is adjacent: intermittent. Mesa
  sizes the BO as ALIGN(array_stride * layers, 4096) with no slack (pan_layout.c), the format table marks RGB8/RGB32 as
  texturable while RGB8UI/RGB16 are not; no code or blob trace says anything about over-fetch (the kbase traces have
  no RGB textures).
- **Fix in the fork**: 02df5721016 "pan/layout: leave a cache line of slack after 24/96-bit images" (non-power-of-two
  block size, not compressed, non-explicit layouts only: +64 B before the page round-up; costs one page only when the
  data ends on a page boundary; applies to gallium and panvk). build-cl rebuilt.
- **Deterministic repro**: runner/board/t_rgbedge.py (+ hostclk.py, the ICD-dispatch runner, works on the board too):
  6 MiB linear RGB8 2Darray / RGB32I 3D images (rows exactly 3072 B, data = 3 x 2 MiB, so the noexec >= 2 MiB alignment
  leaves no hole that a later small BO would prefer right after it), allocated last after a warm-up, 64 work-items reading
  the last texel (sampled, clamped out-of-range, sampler-less); RGBA controls and the two CTS sizes. Checked on the
  host shim (runs, nothing executes there).
- **tdim2 FAIL** (job 45): one `gpu sched timeout, js=1, ..., status=0x0, head=tail=0xa0501c0` among 102 soft-stops:
  the slot was idle with the job's fence unsignalled (status 0 = not active), so the timeout handler took the reset
  path and e17629bba then fails the (earlier soft-stopped) job -> quick_2d_explicit_local FAILED. That is a lost job in
  the kernel soft-stop/resume path (or a lost DONE interrupt), rare (job 28 passed the same test with 101 soft-stops). Not
  found by reading panfrost_job.c (hw_submit skips the START while reset.pending, but those jobs are resubmitted; the
  _NEXT NOP/soft-stop ordering looks right). Needs the job/fence trace.
- **tdim3 TIMEDOUT 1201 in 800 s** with no error line: the slot was ACTIVE at every watchdog tick (otherwise the 'gpu
  sched timeout' line would show) = jobs kept running; whether they progress (slow) or one job never ends (shader hang)
  is not decidable from the counts.
- **Runner job 46-rgb-tdim** (`ocl-job.sh rgbtdim`, HANDOFF-rgbtdim.md, results logs/runner-rgbtdim/): edge repro A
  (cl2) / B (cl3 = 02df5721016) x2, CTS 2Darray RGB8 A/B x2, 3D RGB32I on B, then tdim 2D x3 and 3D explicit/implicit
  (1800 s each) with gpu_scheduler drm_sched_job_run/done events + panfrost_job_timedout streamed to a file and a PROG
  line per minute; full CTS logs kept. Next agent: RGB-OVERFETCH CONFIRMED + RGB-FIX PASS -> done (keep the fork commit,
  note for shipping); NOT REPRODUCED -> read the `fault bo:` lines of any CTS fault (end+0x0 of the texture BO still
  supports the fix; inside/far from a BO -> different cause). tdim: PROG done count rising = slow (re-chunk tdim3 with a
  longer slot); flat done with TIMEDOUT rising = one never-ending job (dump that job: Mesa shader); a lost job = a
  drm_sched_job_run without drm_sched_job_done before the `gpu sched timeout` line in tdim-trace.txt.gz -> kernel fix
  in panfrost_job.c (soft-stop/resume path).
- Out of scope, open for the next agent: the INSTR_INVALID_ENC js faults (job 14 subgroup cases d2-ballot, d3-elect,
  d7-vote, d8-cts-elect; job 09 samplerless float 1Dbuffer, CL_A UNORM_INT8 1Dbuffer, 1 of 235).

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
