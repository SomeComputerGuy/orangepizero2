# Vulkan step 2: panvk Vulkan 1.1 on the Mali-G31 (state file)

Task (user decision 2026-11-06, "wants Vulkan working"): make the fork panvk report Vulkan 1.1 on the G31 (Bifrost v7.0)
and pass dEQP-VK at that level. Step 1 (fork + PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 in the image) is separate packaging
work. Agent vk11, 2026-11-06. Memory: project-vulkan.md. Earlier work: harness/research/vk-hangs/RESULTS.md (jobs 14, 52).

## Fork (mesa-work/mesa-cl, branch panfrost-opencl-fixes, pushed to github.com/SomeComputerGuy/mesa, never upstream)
HEAD **26cb3c93a58** (job 71; 4800173ec22 = job 70; 9d278fabfc2 = job 68; ded6ccea0bc = job 68 chunk 1; was 0e274280595):
* 214aed48424 = cherry-pick of Mesa **0dbf521d381** "panvk: enable Vulkan 1.1 and subgroups on Bifrost" (MR 41981).
  Note: the brief named ba09d293e54, but that commit is the later 1.1 -> **1.3** bump ("expose vulkan 1.3 on bifrost",
  MR 43245); 0dbf521d381 is the 1.0 -> 1.1 gate. 1.3 is step 3 (scope 1.2+ against the G31), not done here.
  Prerequisites of MR 41981: 8b03ae787f4 (loop-exit branch reconvergence) and f11071ce865 (multiview docs) are already
  in 26.2.4 (cherry-picks came out empty); 79293b23366 (internally_synchronized_queues gate) too. Conflicts only in
  docs/features.txt, docs/relnotes/new_features.txt, src/panfrost/ci/panfrost-g52-fails.txt (fork's files kept); the
  driver hunk applied as is. The fork's pan_subgroup_size_gpu() (4-wide G31), ab1caa7378f (ballot via CLPER_OLD),
  b7a705442bd (CLPER_OLD broadcasts) and 0e274280595 are untouched.
* ded6ccea0bc "panvk: make the ARM core builtins safe on Bifrost" (Generated-by: LLM): 0dbf521d381 exposes
  VK_ARM_shader_core_builtins on v6/v7, but bi_emit_intrinsic asserted arch >= 9 for core_id / core_count / warp_id /
  warp_max_id (upstream main has the same). Bifrost has the core_id and warp_id FAU slots (3 and 2, named so by the
  disassembler): allowed on all arches. The meaning of their high words on Bifrost is unknown, so CoreCountARM and
  WarpMaxIDARM are inlined before Valhall from shaderCoreCount / shaderWarpsPerCore (panvk_preprocess_nir), like
  core_max_id already was. Host dump: probe d9 reads only `core_id.x` / `warp_id.x`. Board check: probe d9 in job 68.

* 039c393b7fb "panvk/jm: allocate the command buffer descriptor pool on first use" (Generated-by: LLM): chunk 1 OOM fix,
  see below.
* 9d278fabfc2 "panvk: report the Bifrost warp count for VK_ARM_shader_core_builtins" (Generated-by: LLM): chunk 1 d9 fix.
  New helper panvk_get_shader_warps_per_core(): before Valhall max_threads_per_core / warp size (G31: 512 / 4 = 128),
  v9+ unchanged (/ (size * 2)); shaderWarpsPerCore and the inlined WarpMaxIDARM (= that - 1) come from it.

* cc734ca5372 (ATOM_CX staging reads), 000362f6ff4 (explicit-layout overfetch slack), 4800173ec22 (textureQueryLod
  level on Bifrost): the job 68 fixes, see "Job 68 result" below.
* 26cb3c93a58 "panvk: always set explicit_pad_B when laying out an image": the job 70 fix, see "Job 70 result".

## Job 68 chunk 1 (2026-11-06, c48, build ded6ccea0bc): BLOCKED at part-00 case 4244, d9 FAIL; both fixed
Raw results moved to `logs/runner-ded6ccea0bc/` (summary harness/runner-queue/done/68-vk11-main.chunk1.summary.md).
* **Problem 1, OOM at case 4244 = a panvk over-allocation + a harness bug.** deqp runs in tree order, not caselist order:
  after api.command_buffers.allocate_single_primary (the last csv row) comes **api.command_buffers.allocate_many_primary**
  (10000 primary command buffers; allocate_many_secondary is the same). The JM panvk_create_cmdbuf() preallocated a
  64 KiB descriptor BO per command buffer (`.prealloc = true`; CSF and the other two JM pools are lazy) = 625 MiB of
  pinned GPU memory for empty command buffers, over the 600 MB memcg. Host (drm-shim G31 MC1, mmap counter preload
  /tmp-only): allocate_many_primary mapped **20000 x 64 KiB before, 0 after**; RSS 154 MB (secondary 195 MB), i.e. ~12-16 KB
  of CPU state per command buffer, so it fits the memcg now. Fix 039c393b7fb (prealloc = false, panvk_pool_alloc_mem
  already allocates a backing on demand). Not a genuine test need, not process reuse.
  Harness bug: `systemd-run --scope` has OOMPolicy=stop by default, so the first OOM kill made systemd stop the whole
  scope (deqp-run.py included: DEQP-RC 143 = SIGTERM, no OOM row, kills.json never reached 2), and the case ran again
  every round -> "3 rounds without a new result" -> BLOCKED. Reproduced on the host (user scope MemoryMax=100M:
  rc 143 without, with `-p OOMPolicy=continue` the two allocate_many cases become `OOM` rows and the list completes).
  Harness fixes (vk11-main.sh, deqp-run.py): OOMPolicy=continue; deqp-run.py writes `shard-N.current`; a round without
  a new row counts the current case, the 2nd such round records it as `ResourceLimit` (OOM kill in the round) or
  `Stuck` (`STUCK-MARKED` in runner.log) and the part goes on; BLOCKED only after 4 rounds with still no row. OOM /
  ResourceLimit / Stuck rows are non-pass rows in cmp.txt (and regressions if a baseline passed): nothing is hidden.
* **Problem 2, d9 = 4294967295: the advertised warp maximum was too small, the FAU reads are right.** Decoded d9 (hex):
  every valid lane is `3f..0100` = core id 0, core count 1, warp id 0x00-0x34, warp max 63; core id is always 0 (MC1).
  About half of the warps fail the check: 1x1x1 (16 single-lane warps) gives ids 0, ?, 32, ?, 1, ?, 33, ? ... = slots
  interleaved over 128, the "?" being 64-127. G31: 512 threads per core / 4-wide warps = 128 warps, but
  shaderWarpsPerCore was 512 / (4 * 2) = 64 (the Valhall formula). Fix 9d278fabfc2 (above). Spec: WarpIDARM in
  [0, WarpMaxIDARM], shaderWarpsPerCore = max simultaneous warps per core -> 128 / 127 on the G31. Host (shim, 256
  threads): shaderWarpsPerCore 64, WarpMaxIDARM constant 0x3f. New raw probe **d10** (`host/diag/d10-raw.comp`,
  atomics over the whole dispatch: max core/warp id, count of ids above max, invocations; 4 dispatches up to 8192
  invocations) proves it on the board: check 3b.

## 1.1 requirements against the G31 (step 2 review)
What the backport newly exposes on v7: apiVersion 1.1; KHR_maintenance4/5/7/8, KHR_shader_float_controls2,
KHR_shader_subgroup_extended_types, KHR_internally_synchronized_queues, EXT_subgroup_size_control, ARM_shader_core_builtins,
ARM_shader_core_properties, ARM_scheduling_controls (+ the shaderCoreBuiltins / schedulingControls features). Kept v9+:
maintenance6, shader_maximal_reconvergence, subgroup_uniform_control_flow, quad_control, spirv_1_4 (upstream gates
them the same way; not needed for 1.1).
* Subgroups (1.1 core): size 4 (fork, G31 is 4-wide), stages FRAGMENT|COMPUTE (1.1 needs COMPUTE; no VS because the HW
  may spawn VS invocations for non-existing indices), operations BASIC|VOTE|ARITHMETIC|BALLOT|SHUFFLE|SHUFFLE_RELATIVE|
  CLUSTERED|QUAD|ROTATE|ROTATE_CLUSTERED (0x6ff). All of them go through CLPER_OLD / the WMASK-free ballot on this GPU
  (job 52: probes and subgroup cases PASS, 0 INSTR_INVALID_ENC). quadOperationsInAllStages = false.
* subgroup_size_control: min = max = 4, requiredSubgroupSizeStages = COMPUTE, computeFullSubgroups = true (fixed warp).
* Multiview: multiview = true, maxMultiviewViewCount 8 (>= 6 required), multiviewGeometryShader/Tessellation = false
  (no GS/tess on panvk v7). Protected memory = false, protectedNoFault = false (no protected mode). Variable pointers
  (both), 16-bit storage (all four), samplerYcbcrConversion, shaderDrawParameters = true (already exposed at 1.0 and
  tested in the 1/100 runs). maxPerSetDescriptors 65535, maxMemoryAllocationSize 4 GiB - 1 (>= 1 GiB).
* Nothing had to be rejected for the hardware. ARM_scheduling_controls: the JM backend ignores
  VkDeviceQueueShaderCoreControlCreateInfoARM::shaderCoreCount (upstream too; the panfrost JM UAPI has no job-slot core
  affinity), so it is a scheduling hint only. No CTS coverage for either ARM extension (none in 1.4.6.2).

## Host checks (drm-shim fake G31, PAN_GPU_ID=7093, no override; build-host-shim at ded6ccea0bc, asserts on)
Re-run at **9d278fabfc2** (2026-11-06): host-api.txt 8627 cases identical to ded6ccea0bc (8033 Pass, 592 NotSupported,
2 known Fail, 0 diffs; `host/deqp-api2/`); api.command_buffers 129 cases 34 Pass / 77 NotSupported / 18 Fail (the shim
executes nothing) / 0 Crash, allocate_many_* Pass (`host/deqp-cmdbuf/`); vkprops apiVersion 1.1.354, createDevice OK;
d9 and d10 compile and dispatch (PAN_SHADER_PRESENT=0x1).
* `host/vkprops` (new: apiVersion, 1.1 properties/features, ARM core properties, extension list, vkCreateDevice with all
  reported 1.0+1.1 features): **apiVersion 1.1.354, 150 extensions, createDevice OK, VKPROPS-OK** (`host/vkprops-host.txt`).
* dEQP-VK on the host shim (native deqp-vk 1.4.6.2): api.info/device_init/version_check/feature_bits/
  get_device_proc_addr/maintenance + info.* = 8627 cases: **8033 Pass, 592 NotSupported, 2 Fail** (the known
  create_device_global_priority{,_khr}.basic, in Mesa's g52-fails), 0 Crash. subgroups (1/20 sample, 1816) and
  subgroups.size_control (63): 0 Crash / 0 compiler asserts; the Fail rows are expected because the shim executes
  nothing (results are zero).
* Probe d9 (`host/diag/d9-core.comp`) compiles; Bifrost code reads core_id.x / warp_id.x, count and max are constants.
* Tooling: `harness/analysis/gpu/deqp-run.py` gained `--budget S` (stop after S s, unfinished case reruns on resume,
  exit 3, no summary); host test: 12 budget rounds over 60000 cases = 60000 unique rows.

## Builds
`mesa-work/build-cl` (arm64, driver string `git-26cb3c93a5`; source tools/env-cl.sh before ninja, else rusticl
bindgen fails) and `build-host-shim` rebuilt at 26cb3c93a58 (nice 19).

## Runner job 68 (re-queued 2026-11-06 at 9d278fabfc2, restarts clean at part-00)
Restart: FORK=9d278fabfc2 in vk11-main.sh; the stale frozen copy (ded6ccea0bc) is deleted (and the script deletes any
frozen copy whose lib is not `git-<FORK>`); host results of another fork are moved to `logs/runner-<fork>/`
(`logs/runner/FORK` stamp); the board's `/root/vk11/res` is wiped when its `res/FORK` stamp differs. Probe adds d10,
`--check` adds 3b. HANDOFF.md updated (checks 1, 3b, step 2 text).
`harness/runner-queue/68-vk11-main.md` -> `runner/vk11-main.sh` + `runner/HANDOFF.md` + `runner/vk11-cmp.py`.
Full vk-main 1.4.6.2 (3 247 552 cases) on the fork at the driver's own 1.1, newest cumulative kernel (c48 at submission,
with e544ddb00), deployed to /root/opiz2-mesa/vk3 (frozen copy `frozen/vk3` after the first deploy). 64 parts
(`logs/runner/parts/`, prebuilt), rounds of <= 780 s, copy-off every round, stall watchdog (Hang rows), pause file,
automatic lock hand-over (waiters, every 3.5 h). Estimate 16-22 h (1/100 sample: 522 s at override 1.1 -> 14.5 h, the
newly exposed extensions add cases, 1.3 took 818 s). Checks 1-9 by `vk11-main.sh --check`.
Regression baselines (vk11-cmp.py): vk-main 1/100 at 1.0 and at override 1.1 (system 26.2.4), vk-subset at 1.0 and
override 1.1 (system), job 52 fork vk-subset (override 1.1).

## Coordinator note 2026-11-06 23:50 (job 68 chunk 2)
Paused by the coordinator (PAUSE file) for image integration; 1/64 parts done (part-00: 16333 Pass, 34410 NotSupported,
0 Fail/Crash/Hang, 0 regressions). Resume = same command. Open: --check 3 (d9) FAILs with no reason printed while
3b (d10) PASSes (max core 0 < count 1, max warp 127 = WarpMaxIDARM); likely the d9 check's core-count vs
shaderCoreCount condition. Next code agent: fix the check (or the probe) and make it print the failing condition.
Summary: harness/runner-queue/done/68-vk11-main.chunk2.summary.md.

## Job 68 result (2026-11-07, c48, build 9d278fabfc2): all 64 parts, analysed by agent vk11-fix
3 247 552 cases: 684 180 Pass, 2 562 827 NotSupported, 526 Fail, 9 Crash, 2 ResourceError, 8 QualityWarning.
Summary: harness/runner-queue/68-vk11-main.chunk-3.summary.md; results logs/runner/ (cmp.txt, check.txt).
Check 3 (d9) FAIL was the check, not the driver: it also read the 16 unused zero words after the 16 results of the
1x1x1 dispatch; every d9 word is `0x7f..0100` (core 0, count 1, warp <= 127) and d10 (3b) PASS. Fixed in vk11-fix.sh.
Every one of the 537 non-pass rows classified:
| rows | what | class | action |
|---|---|---|---|
| 8 Crash | robustness.image_robustness.{bind,push}...r32i.dontunroll.nonvolatile.storage_image.fmt_qual.img.samples_1.{cube,cube_array}.{comp,frag} = the 8 INSTR_INVALID_ENC / js faults (parts 45/46) | pre-existing upstream bug (Mesa g52-fails: Crash; main has it too), not 1.1 | **fixed cc734ca5372** |
| 16 Fail | drm_format_modifiers.export_import{,_fmt_features2}_with_suballoc.{r8g8b8,b8g8r8}_{unorm,snorm,srgb}, r32g32b32_{sfloat,sint,uint} (= check 9's 1 REG) | **regression of our fork commit 02df5721016** (RGB overfetch slack, job 46), not of 1.1 | **fixed 000362f6ff4** |
| 4 Fail | glsl.texture_functions.query.texturequerylod.sampler2d_{fixed,float}_trilinear{,non_zero_base_level}_fragment | pre-existing upstream bug (g52-fails; Valhall passes) | **fixed 4800173ec22** |
| 1 Crash | synchronization2.internally_synchronized_queues.device_wait_idle_device_wait_idle: "Watchdog timer timeout for touch interval" | newly exposed by 1.1 (KHR_internally_synchronized_queues); test/harness: dEQP's 30 s touch watchdog on a 4-thread x 1000-iteration case (upstream PowerVR skips the device_wait_idle cases as too slow) | rerun with the watchdog off (job 70 part-01) |
| 500 Fail | texture_functions.texture*offset*.mirrored_repeat.* | hardware limit: Khronos CTS waiver 4936 (Arm, device list includes 0x70930000 = G31; offset >= extent with MIRRORED_REPEAT); all 500 are in upstream panvk-skips.txt | none (waived) |
| 3 Fail | rasterization.primitives.no_stipple.lines{,_factor_0,_factor_large} (strict/rectangular/bresenham/line_strip pass) | pre-existing upstream known (g52-fails) | open, qpa kept by job 70 |
| 2 Fail | api.device_init.create_device_global_priority{,_khr}.basic | pre-existing upstream known (g52-fails) | open |
| 1 Fail | api.driver_properties.conformance_version (0.0.0.0 < 1.1) | newly exposed by 1.1; the driver is not conformant, upstream g52-fails | none (no false conformance claim) |
| 2 ResourceError | api.object_management.max_concurrent.device{,_group} (OUT_OF_DEVICE_MEMORY) | resource limit (1 GB board, 600 MB memcg; upstream g52-fails Fail) | none |
QualityWarning 8 (e.g. pipeline_binary unique_key_pairs) count as pass. No GPU fault other than the 8 above.

### Fixes (fork, Generated-by: LLM, pushed to github panfrost-opencl-fixes; build-cl rebuilt at 4800173ec22)
* **cc734ca5372 "pan/bi: count the ATOM_CX staging reads like ATOM_RETURN"**. Host repro (shim, asserts on): the case
  asserts `!(mode & 0x8)` in bi_pack_registers = the last tuple of a clause writes two registers. The scheduler lets
  `r10 = CSEL` (read only through the passthrough by the paired ADD) sit next to the `r5 = MUX` write because r10 is
  dead in the pre-scheduling liveness (0x27f). bi_lower_atom_c turns ATOM_RETURN (counted as reading 1 staging reg) into
  +ATOM_CX (counted as reading sr_count = 2), so the post-scheduling DCE sees r8/r10 (upper return halves) live around
  the loop (0x77f) and keeps the write -> invalid encoding. Fix: ATOM_CX keeps atom_opc (not encoded) and reads
  sr_count/2 (all for ACMPXCHG), like ATOM_RETURN. Not in upstream main (checked 2648b2059f1). Host: the 8 cases compile
  (Fail on the shim = no execution), glsl.atomic_operations (1040), image_robustness bind r32i (540),
  image.atomic_operations.compare_exchange (440): 0 asserts.
* **000362f6ff4 "panvk: reserve the overfetch slack for explicit 24/96-bit image layouts"**: 02df5721016 pads only the
  layouts we choose (64x64 RGB8: 12288 -> 16384), explicit (imported) layouts stay exact (12288), so the test bound the
  imported sub-image at another offset than the exporter's. panvk now adds the 64 B to the memory requirements of an
  explicit plane with a non-power-of-two texel size (data_size_B and gallium unchanged).
* **4800173ec22 "panvk: take the textureQueryLod level from the sampler on Bifrost"**: bi_lower_lod always rounded .x;
  for a LINEAR mipmap mode .x must be the clamped LOD. panvk (v7) now derives .x from the raw LOD (.y) and the sampler /
  texture descriptors in the set memory, like va_lower_lod on Valhall (clamp to [min, min(max, levels-1)]; None 0,
  Nearest ceil(lod+0.5)-1, trilinear the clamped LOD). Host: query.texturequerylod.* (190) 0 crashes on the shim.
* Harness: deqp-run.py `--no-watchdog`; vk11-fix.sh check 3 fixed.

## Runner job 70 (queued 2026-11-07): harness/runner-queue/70-vk11-fix.md
Package runner/{vk11-fix.sh,HANDOFF-fix.md,vk11-fix-cmp.py,fix-parts/}; results logs/runner-fix/; deploys
/root/opiz2-mesa/vk4 (frozen/vk4), board dir /root/vk11fix. 5 caselists (46 753 cases): part-00 the 536 job 68 non-pass
(qpa kept), part-01 the 9 isq *device_wait_idle* (watchdog off, 1500 s), part-02 8507 job 68 Pass in the touched groups,
part-03 vk-main 1/100, part-04 vk-subset. Checks 9a-9d = the targets pass, 10 = 0 regressions vs job 68, 11 = 0 vs the
26.2.4/job 52 baselines; INFO = remaining per known class (expected 500/3/2/1/2). Estimate 1.5-2.5 h.

## Job 70 result (2026-11-07, c51 kernel #51, build 4800173ec22): summary harness/runner-queue/done/70-vk11-fix.summary.md
46 529 cases; checks 1-9d and 11 PASS (all 28 targets + 9d fixed, 29 fixed vs job 68; 0 INSTR_INVALID_ENC / GPU
faults; 0 regressions vs 26.2.4 / job 52); remaining known classes exactly 500/3/2/1/2. Check 10 FAIL, 6 regressions:
* **5 = our fix 000362f6ff4** (memory.requirements.create_info.image.{regular,transient}_tiling_{linear,optimal},
  api.invariance.memory_requirements_matching). Cause: the new panvk_image_plane::explicit_pad_B was only written for
  explicit 24/96-bit planes. vkCreateImage zero-allocates the image, but panvk_GetDeviceImageMemoryRequirements (and
  GetDeviceImageSparseMemoryRequirements) build `struct panvk_image image;` on the stack, so the size from the create
  info carried stack garbage and differed from vkGetImageMemoryRequirements (both tests compare exactly those two;
  CTS users of the device queries: memory.requirements, api.invariance, image.subresource_layout). Host repro (shim,
  4800173ec22): those 5 + api.invariance.memory_dedicated_requirements_matching Fail; at the fix all Pass
  (memory.requirements.* + api.invariance.*: 28 Pass, 52 NotSupported, 0 Fail). **Fix 26cb3c93a58**: assign the field
  for every plane (pad stays for explicit RGB planes, so 9b / 02df5721016 are unchanged).
* **1 = memory pressure, not a fix**: synchronization2.internally_synchronized_queues.large2_large2 ResourceError
  (vkAllocateMemory OUT_OF_DEVICE_MEMORY after 0.32 s). It ran as case 8503 of 8507 of part-02 (job 68: Pass inside
  part-57). The case has 3 large threads, each a 4096x4096 RGBA8 optimal image (64 MiB) + a 64 MiB host-visible
  readback buffer (~384 MiB GEM) on the 600 MB memcg, after thousands of cases in the same dEQP process. None of the
  fixes touches RGBA8 / buffer allocation (000362f6ff4 only explicit RGB layouts; created images are zeroed). Job 71
  runs it alone in a fresh process (part-06, check 9f); check 10 reports its batch ResourceError as INFO only then.

## Runner job 71 (queued 2026-11-07): harness/runner-queue/71-vk11-fix2.md
Package runner/{vk11-fix2.sh,HANDOFF-fix2.md,fix2-parts/} + vk11-fix-cmp.py (new optional ISOPART arg = part-06: 9e,
9f, large2_large2 rule; job 70 calls unchanged); results logs/runner-fix2/; deploys /root/opiz2-mesa/vk5 (frozen/vk5),
board dir /root/vk11fix2. 7 caselists (60 173 cases): part-00..04 = job 70's, part-05 (13 419) = job 68 non-NotSupported
rows of memory.*, api.invariance.*, drm_format_modifiers.*, image.subresource_layout.* + every 10th other image.* not in
part-00..04, part-06 = large2_large2 alone. HANDOFF tells the runner to use harness/ssh.sh / BOARD_SSH_OPTS for any
manual ssh (job 70's "Host key verification failed"). Estimate 1-2 h (job 70 = 41 min of rounds).

## Next step (fresh agent, after the job 71 summary)
1. 9e FAIL -> read part-03/05 results for the case (host shim reproduces these: run them there first). 9f FAIL ->
   large2_large2 really fails: measure GEM usage of the case (3 x 128 MiB expected) against the 600 MB memcg and look
   for a panvk allocation leak / over-allocation before calling it a board limit. 10 FAIL with other cases -> root-cause.
2. All PASS -> Vulkan 1.1 done on the G31 (remaining non-pass: waiver 4936 (500), conformance_version (1),
   max_concurrent (2) by design; upstream-known lines x3, global_priority x2 on the work list, qpa in
   logs/runner-fix/files/part-00/). Then patches/mesa refresh from the fork (image integration, coordinator), record
   in impl-gpu-spec.md 4c, and hand step 3 (1.2+ scope) to the coordinator.

## Older next step (after the job 70 summary, done)
1. Checks 9a-9c FAIL -> the fix did not work on the hardware: read part-00.qpa.xz for the case. 9d Timeout/Stuck -> the
   case is slower than 1500 s: profile panvk QueueWaitIdle (vk_common: one sync per queue per call) before calling it
   a test limit. Checks 7/8/10/11 FAIL -> root-cause first (function first).
2. All PASS -> Vulkan 1.1 done on the G31: remaining non-pass = waiver 4936 (500), conformance_version (1),
   max_concurrent (2) by design; open upstream-known items (lines x3, global_priority x2) go on the work list
   (qpa in logs/runner-fix/files/part-00/). Then patches/mesa refresh from the fork (image integration, coordinator),
   record in impl-gpu-spec.md 4c, and hand step 3 (1.2+ scope) to the coordinator.
