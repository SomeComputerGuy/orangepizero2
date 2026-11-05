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
  expected 126". Also in Mesa CI's G610 fail list (upstream rusticl/panfrost issue).
- **Samplerless 1Dbuffer int/uint/float (3).** Every format fails at the first size (e.g. width 329, CL_R
  SIGNED_INT8). My own 1D-buffer vs 1D-image repro with the same kernel shape passes for widths 1-16384, so the
  difference is still unknown.
- **Images Kernel 2D float (1).** CL_RGB UNORM/SNORM_INT8 2D *array* reads return NaN.
- **Integer Ops quick_(u)long_math.** 64-bit division/modulo give wrong values for some elements (pairs at index 14/15
  mod 16).

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

## Shipping

The image uses Ubuntu's mesa 26.2.4-1ubuntu1, so ship the branch as Debian patches on that package:
1. `git -C mesa-work/mesa-cl format-patch mesa-26.2.4..panfrost-opencl-fixes` (17 patches; drop the
   .pick_status.json hunks if quilt complains), put them in `debian/patches/opiz2/` of the Ubuntu source
   (`mesa-work/oclfix/dl-ubuntu-mesa/`) and append them to `debian/patches/series`.
2. Bump to `26.2.4-1ubuntu1+opiz2.1` (dch), build with `dpkg-buildpackage` in an arm64 chroot or on the board
   (needs root, the user runs it), and add the resulting libgl1-mesa-dri, libegl-mesa0, libgbm1, mesa-vulkan-drivers,
   mesa-opencl-icd, mesa-libgallium debs to the image with `apt-mark hold` so the Ubuntu archive does not replace them.
3. When Ubuntu moves to 26.2.6, the 12 stable cherry-picks drop out; the remaining ones are the two upstream main
   cherry-picks and our three patches (SEG_ADD RA, subgroup size, trailing barrier). Our three are AI-generated:
   per the user, they stay in our fork and are not sent to Mesa without asking.
