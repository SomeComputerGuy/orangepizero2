# Vulkan step 2: panvk Vulkan 1.1 on the Mali-G31 (state file)

Task (user decision 2026-11-06, "wants Vulkan working"): make the fork panvk report Vulkan 1.1 on the G31 (Bifrost v7.0)
and pass dEQP-VK at that level. Step 1 (fork + PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 in the image) is separate packaging
work. Agent vk11, 2026-11-06. Memory: project-vulkan.md. Earlier work: harness/research/vk-hangs/RESULTS.md (jobs 14, 52).

## Fork (mesa-work/mesa-cl, branch panfrost-opencl-fixes, local only, never upstream)
HEAD **ded6ccea0bc** (was 0e274280595):
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
`mesa-work/build-cl` (arm64, driver string `git-ded6ccea0b`) and `build-host-shim` rebuilt at ded6ccea0bc (nice 19).

## Runner job 68 (queued)
`harness/runner-queue/68-vk11-main.md` -> `runner/vk11-main.sh` + `runner/HANDOFF.md` + `runner/vk11-cmp.py`.
Full vk-main 1.4.6.2 (3 247 552 cases) on the fork at the driver's own 1.1, newest cumulative kernel (c48 at submission,
with e544ddb00), deployed to /root/opiz2-mesa/vk3 (frozen copy `frozen/vk3` after the first deploy). 64 parts
(`logs/runner/parts/`, prebuilt), rounds of <= 780 s, copy-off every round, stall watchdog (Hang rows), pause file,
automatic lock hand-over (waiters, every 3.5 h). Estimate 16-22 h (1/100 sample: 522 s at override 1.1 -> 14.5 h, the
newly exposed extensions add cases, 1.3 took 818 s). Checks 1-9 by `vk11-main.sh --check`.
Regression baselines (vk11-cmp.py): vk-main 1/100 at 1.0 and at override 1.1 (system 26.2.4), vk-subset at 1.0 and
override 1.1 (system), job 52 fork vk-subset (override 1.1).

## Next step (fresh agent, after the job 68 summary)
1. Checks 2-4: if d9 fails (ids above max or wrong count), fix the Bifrost core-builtins lowering (e.g. inline
   warp_max from the observed range or gate shaderCoreBuiltins off on v7 if WARP_ID is not per-core) in the fork.
2. Check 9 regressions: each REG line is a real regression of the 1.1 enable -> root-cause first (function first).
3. cmp.txt NON-PASS by group: triage with harness/analysis/gpu/vk-triage.py against Mesa's g52 fails/flakes/skips
   (expected-upstream vs G31-specific); the newly exposed extension groups (maintenance4/5/7/8, size_control,
   subgroup_extended_types, float_controls2) are the likely new failures. Fix in the fork, rerun only the failing
   cases (a small caselist through deqp-run.py) rather than the full 14+ h run.
4. Then record the result in impl-gpu-spec.md 4c / the spec row, and hand step 3 (1.2+ scope) to the coordinator.
