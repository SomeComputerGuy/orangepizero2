# Vulkan "Incomplete job or timeout" cases on the Mali-G31 (impl-gpu-spec.md 4c): state file

Task: `dEQP-VK.subgroups.basic.compute.subgroupelect` (+ the other subgroup cases) and 7
`dEQP-VK.spirv_assembly.type.vec4.*_frag` cases end with "Incomplete job or timeout" (PANVK_DEBUG=sync abort) on the
system Mesa 26.2.4 and on the fork. Decide compiler bug / descriptor bug / long job, fix in the fork, hand a runner job.
Agent vk-hangs, 2026-11-05. Memory: project-vulkan.md.

## Host tooling built (no board needed)
* `mesa-work/build-host-shim` now also builds **panvk** (`-Dvulkan-drivers=panfrost -Dtools=drm-shim,panfrost`,
  `build-host-vk.sh`); `host/vk-env.sh` = fork panvk on the panfrost noop drm-shim as a fake G31 (`PAN_GPU_ID=7093`,
  `PAN_SHADER_PRESENT=1` for MC1). The shim needed one fix for panvk (a516f2c3ddc: ALLOWED_JM_CTX_PRIORITIES medium bit,
  without it vkCreateDevice fails with VK_ERROR_NOT_PERMITTED).
* `host/vkcomp.c`: minimal Vulkan compute runner (SPIR-V file, spec constants 0-2 = local size, N storage buffers,
  one dispatch, fence wait, prints buffer 0). Built for the host and cross-built for the board (`vkcomp-arm64`, linked
  against a stub libvulkan.so.1 so the board's loader is used). `BIFROST_MESA_DEBUG=shaders` gives NIR + Bifrost IR +
  packed clauses, `PANVK_DEBUG=trace PANDECODE_DUMP_FILE=...` the job descriptors (works under the shim).
* Native x86_64 **deqp-vk** from the same vulkan-cts-1.4.6.2 tree (`harness/analysis/gpu/build-deqp-vk-host.sh`,
  `harness/research/gpu-src/build-deqp-vk-host/`): any board case can be replayed under the shim for shader dumps.
* Native glslang (`build-glslang-host.sh`) for the diagnostic shaders `host/diag/d1..d7.comp` -> `.spv`; `d8` is the CTS
  elect compute shader (SPIR-V from the board qpa, `host/elect.spvasm`).

## Findings
1. **7 `spirv_assembly.type.vec4.*_frag` cases = long jobs, not hangs.** The CTS fragment shader of these tests loops over
   the whole dataset in *every* fragment of a 256x256 draw (no FragCoord gate): 8210 iterations for `i8.clamp`, 5120 for
   `u32.bit_field_insert_*`, each iteration 15-19 clauses with 3 SSBO loads + 1 store (host dumps `host/deqp/*.frag.txt`).
   The vec4 cases that pass (e.g. `u8.bit_field_s_extract`, 2560 iterations) are just below the 500 ms panfrost job
   watchdog; above it the stock kernel resets the GPU (`gpu sched timeout, js=0`) and panvk's sync check aborts.
   This is exactly what the kernel patch e544ddb00 (soft-stop and resume an ACTIVE job) addresses: with it in the
   cumulative kernel these cases should Pass, slowly. Nothing to fix in Mesa. Verification: runner chunks cases-frag-a/b.
2. **Subgroup compute cases: one compiler bug found and fixed, one open question for the board.**
   * Fixed (b7a705442bd): `nir_intrinsic_read_invocation` emitted the full `CLPER.i32` encoding on every GPU; G71/G72/G31
     only decode the old form (`BIFROST_LIMITED_CLPER`, fixed subgroup4/zero/none), so every subgroupBroadcast, shuffle,
     quad op, rotate and read_first_invocation faulted with INSTR_INVALID_ENC
     (`dEQP-VK.subgroups.ballot_broadcast.compute.subgroupbroadcast_int8_t` aborted at once on the fork too). Now
     `CLPER_OLD.i32` (host dump `host/broadcast-4x1x1.txt`: 512 CLPER_OLD, 0 CLPER.i32). Upstream main has the same bug.
   * Open: `subgroupelect` uses only `WMASK.subgroup4` (ballot) + `lane_id` + WLS atomics (`host/elect-1x1x1.txt`; the
     elect lowering is ballot -> find_lsb == lane id, loop-free, descriptors identical to gallium's compute job). The
     8-wide `WMASK.subgroup8` of the system Mesa faulted with INSTR_INVALID_ENC; the fork's `WMASK.subgroup4` ends in
     "Incomplete job" with no INSTR_INVALID_ENC, so it is either another fault status or a stall in WMASK on v7.0. No host
     tool can tell (the shim executes nothing; the G31 blob strings contain no mnemonics). The runner's `diag` chunk runs
     8 probe shaders x 3 local sizes on the board with `PANVK_DEBUG=sync,trace` and records each job's
     `Exception Status` + dmesg: d1 plain store, d2 ballot (WMASK only), d3 elect, d4 WLS atomics + subgroup memory
     barriers (no subgroup op), d5 subgroup ids, d6 broadcast (CLPER_OLD), d7 any/all, d8 the CTS elect shader.
     The first not-OK probe names the instruction; if d2 fails and d4 passes, WMASK is the culprit on v7.0 and the next
     agent lowers ballot differently for `BIFROST_LIMITED_CLPER` GPUs (e.g. per-lane CLPER_OLD gathers of the predicate).
3. Earlier reasoning in 4c ("pan_subgroup_size() gives 8 on a 4-wide core") was right and is in the fork (55fb9c9c4d3);
   it removed the INSTR_INVALID_ENC but not the abort.

## Fork commits (mesa-work/mesa-cl, branch panfrost-opencl-fixes, on 26.2.4; never upstream)
* b7a705442bd pan/bi: use the old CLPER form for read_invocation on limited-CLPER GPUs (Generated-by: LLM)
* a516f2c3ddc drm-shim/panfrost: report the medium JM context priority and a barrier size (host tooling only)
Cross build `mesa-work/build-cl` rebuilt (libvulkan_panfrost.so 2026-11-05 22:29); deployed by the runner as
`/root/opiz2-mesa/vk1`. OpenCL/GLES paths are untouched by b7a705442bd (rusticl exposes no subgroups; GLES
derivatives already went through `bi_clper()`); the runner's ocl and gles chunks check for regressions anyway.

## Runner job
`harness/runner-queue/14-vk-hangs.md` -> `runner/vk-hangs.sh` + `runner/HANDOFF.md` (10 chunks <= 15 min, resumable):
diag, cases-sg (7 subgroup cases), cases-frag-a/b (the 7 long frag cases, wall time recorded), subset1-4 (vk-subset
5225 cases at MESA_VK_VERSION_OVERRIDE=1.1 on the fork, compared with the 26.2.4 baseline by `runner/vk-cmp.py`), ocl
(8 OpenCL-CTS suites), gles (dEQP-GLES3 derivate, 556 cases). Results -> `logs/runner/`.

## Next step (fresh agent, after the runner summary)
1. Copy the DIAG table and CASE lines into impl-gpu-spec.md 4c. If all fork DIAG lines are OK and the subgroup cases
   pass: the task is done (then run the remaining `subgroups.*` groups). If d2/d3/d7/d8 fail with d1/d4/d5/d6 OK: WMASK
   does not work on v7.0 -> lower `ballot` without WMASK for LIMITED_CLPER GPUs (4 lanes: `CLPER_OLD` of the predicate
   from lanes 0-3, or the `WMASK` replacement the G31 blob uses). If d4 fails: WLS atomics in panvk compute (compare
   with the gallium descriptors: `host/elect-1x1x1.pandecode*`). The trace.tgz has every job's exception status.
2. frag cases: if they Pass with t= values, record the durations in 4c (long jobs, kernel fix); if they still abort
   with `gpu sched timeout`, the kernel in use lacks e544ddb00.
3. Subset: `cmp.txt` REGRESSIONS must stay 0; FIXED lists what the CLPER fix gained.

## Job 14 result and the INSTR_INVALID_ENC fixes (2026-11-06, agent gpu-invalid-enc)
Job 14 on c38 (done/14-vk-hangs.summary.md): fork d1/d4/d5/d6 OK, every probe with a ballot (d2 ballot, d3 elect, d7
any/all, d8 CTS elect) faults `js fault, js=1, status=INSTR_INVALID_ENC` at any local size -> **WMASK is not executable
on the G31** (G71/G72/G31 = BIFROST_LIMITED_CLPER: old CLPER only, no WMASK). The 7 frag cases PASS on c38 (4-5 s each,
the soft-stop kernel fix; finding 1 confirmed), subset REGRESSIONS 0 with 4 FIXED; 12 subgroup Crashes remained (all
elect/barrier cases go through ballot), subset1 12 js faults; ocl/gles regression chunks PASS.
* Fix ab1caa7378f "pan/bi: lower ballot without WMASK on limited-CLPER GPUs": ballot = OR over lanes 0-3 of
  (CLPER_OLD(pred, lane) & (1 << lane)) (inactive lanes read 0, bools are 0/~0). Host dumps: no WMASK in d2/d3/d7/d8
  nor in dEQP-VK.subgroups basic/ballot_broadcast/clustered/vote/ballot_other cases; CLPER_OLD only, no CLPER.i32.
* Job 09's samplerless float CL_A UNORM_INT8 1Dbuffer fault (other half of the task) is fixed by 0e274280595 (see
  impl-opencl-fixes.md): A8_UNORM attribute (texel buffer) faults the G31; gallium now honours PAN_BIND_TEXEL_BUFFER.
* Build: build-cl and build-host-shim rebuilt at 0e274280595. Runner job harness/runner-queue/52-gpu-invalid-enc.md
  (package harness/research/gpu-invalid-enc/runner/, results gpu-invalid-enc/logs/runner/, deploys /root/opiz2-mesa/vk2).
* Next step (fresh agent after job 52): 8a 0 INSTR_INVALID_ENC + 2b values + cases-sg Pass + 5b 0 subgroup STILL ->
  task done, copy into impl-gpu-spec.md 4c. If d2 values are wrong but no fault: CLPER_OLD of an inactive lane is not
  zero -> AND with a ballot of the lane being active (e.g. gate by lane_id < active count). If a fault remains, read
  the trace.tgz shader of that tag for the faulting clause.
