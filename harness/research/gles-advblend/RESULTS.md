# KHR-GLES31 blend_equation_advanced test_coherency.mixedSequence on the Zero2 (Mali-G31, Bifrost v7.0)

State file of the gles-advblend task (agent 2026-11-05). Memory: project-gles-advblend.md.
**Status: DONE 2026-11-06** (job 50 on c38 ALL PASS; fix = kernel soft-stop series; Mesa dc7266d584b reverted, 5d7c3e57df1).

## Problem
`KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence` fails (87/88 of the group pass; 5/5 reruns fail,
"results differ"): 4 x 11 fullscreen draws with different advanced blend equations on a 1024x1024 RGBA8 FBO, no barrier
(GL_KHR_blend_equation_advanced_coherent is advertised), one fragment job. First pixel right, not all pixels equal.
Passes with `MESA_EXTENSION_OVERRIDE=-GL_KHR_blend_equation_advanced_coherent` (glBlendBarrier = one fragment job per
draw), `multiplySequence` (7 draws) passes, the 86 other cases (one dependent draw per pixel) pass. ("No GPU
timeouts" was wrong: job 48 shows one `gpu sched timeout` per failing run; see "Root cause (job 48)".)
Rule: the extension stays on; no cap hides it.

## Host reproduction (no board)
- `host/advblend.c`: EGL surfaceless + GLES 3.1 repro of the CTS test (same shader, sequence, 2-triangle quad, RGBA8
  renderbuffer). Reports first pixel vs reference, distinct values, pixels != first, a 16x16-tile map of bad tiles,
  `RESULT PASS|FAIL`. Options `--seq mixed|multiply --repeat N --size W --barrier --nocoherent --dump file`.
  Board binary: `mesa-work/deps/cross-root/usr/bin/aarch64-linux-gnu-gcc-15 --sysroot=mesa-work/sysroot -O1 -o
  host/advblend-arm64 host/advblend.c -Imesa-work/mesa-cl/include -l:libEGL.so.1 -l:libGLESv2.so.2 -lm`.
  Host binary: `gcc -o host/advblend-host host/advblend.c -I.../mesa-cl/include -L.../build-host-shim/src/egl
  -L.../build-host-shim/src/mesa/glapi/es2api -lEGL -lGLESv2 -lm`; run with `. host/gl-shim-env.sh` (panfrost drm-shim,
  fake G31: descriptors and shader compiles are real, nothing executes, the readback is zero).
- mesa-work/build-host-shim was reconfigured with `-Degl=enabled -Dgles2=enabled` (meson configure; rusticl still
  there) so the GL driver runs on the host shim: `PAN_MESA_DEBUG=trace` gives the pandecode of the job chain,
  `BIFROST_MESA_DEBUG=shaders` the Bifrost disassembly.
- Findings from the trace of the unfixed driver (host/fs-disasm-base.txt = the fragment shader):
  - the fragment shader does `LD_TILE` in its FIRST clause with `wait(7)` (eldest colour), so the RSD already has
    `Shader wait dependency 7: true`; forward pixel kill is already off (`can_fpk` false with outputs_read); pixel kill /
    ZS update = Weak Early. So the dependency waits were not the problem (the earlier v6-NOP experiment never changed
    those bits either: the NOP clause carries no waits).
  - what WAS wrong for the 11 fbfetch draws: blend descriptor `Mode: Opaque` (blend disabled + full mask ->
    pan_blend_is_opaque; panfrost's own comment: opaque = "no tilebuffer read in there", yet the shader reads it),
    RSD `Overdraw alpha0/alpha1: true` ("alpha 0 is a no-op, alpha 1 fully overwrites" - false when the result depends
    on the older fragments), and `Evaluate per-sample: true` with `Multisample enable: false` on a single-sampled FBO
    (gl_nir_lower_blend_equation_advanced forces uses_sample_shading and pan_shader_prepare_rsd copies it into the
    partial RSD; the v9+ JM path and panvk gate it on the sample count).

## Fix (mesa-work/mesa-cl, branch panfrost-opencl-fixes, commit dc7266d584b, Generated-by: LLM) -- REVERTED (5d7c3e57df1), not the cause
`panfrost: don't describe tilebuffer-reading fragments as opaque (v6/v7)`: for fragment shaders whose outputs_read
includes a render target, the blend descriptor uses the fixed-function mode with the existing replace equation (when the
format is blendable and the equation is fixed-function capable; opaque otherwise), alpha_zero_nop/alpha_one_store stay
off, panfrost_overdraw_alpha() returns false; evaluate_per_sample = msaa && (min_samples > 1 || fs sample_shading) at
draw time and the shader's request is cleared from the partial RSD. Files: src/gallium/drivers/panfrost/pan_cmdstream.c,
pan_cmdstream.h, pan_screen.c, src/panfrost/lib/pan_util.h. Debug A/B switches (default off):
`PAN_MESA_DEBUG=fbfetch_opaque,fbfetch_overdraw,persample_1x` restore the three old descriptors one by one.
Host check (drm-shim trace): the 11 fbfetch draws now show Mode: Fixed-Function, Overdraw alpha0/1 false, Evaluate
per-sample false; each knob restores exactly its field. Nothing changes for shaders that do not read the tile buffer,
except that sample-shading shaders no longer run per-sample on single-sampled framebuffers.
Board build: mesa-work/build-cl (cross, ccache) contains the fix (version string `Mesa 26.2.4 (git-dc7266d584)`).

## Board validation: runner job harness/runner-queue/15-gles-advblend.md
Package runner/{gles-advblend.sh,HANDOFF.md}: deploys build-cl as /root/opiz2-mesa/gl1 (side by side), then 8 chunks:
`repro` (advblend on system Mesa = control, on the fork, with every knob combination -> tells which descriptor matters),
`khr-adv` (88 KHR cases), `deqp-fbfetch` (146), `deqp-ms` (410: sample_shading, multisample_interpolation,
sample_variables, builtin_var), `khr-ms` (199), `deqp-fbo` (118), `gles3-blend-a/b` (2304 fragment_ops.blend).
CTS chunks are compared with the baseline harness/analysis/gpu/cts/<suite>/results.csv (compare-<c>.txt, REGRESSIONS=0
required). Results: logs/runner/.

## Root cause (job 48, stock kernel #17, 2026-11-06): the fragment job outlives the 500 ms watchdog
Job 48 (done/48-gles-advblend.summary.md, logs/runner/) ran the fork 02df5721016 (contains dc7266d584b) on the STOCK
kernel #17, which lacks the panfrost soft-stop/resume series. Data:
- Every non-barrier 1024x1024 mixed run FAILS, system Mesa AND fork, with every knob combination (fork-mixed 290432,
  -2 303600, -3 283312, knob-* 285136-298400, sys-mixed 199056 wrong pixels of 1048576). The knobs make no difference:
  dc7266d584b neither fixes nor causes anything here (its theory was wrong).
- The wrong pixels all have the value **0,0,0,0** = never written (the CTS clear/first draw gives 32,32,32,255 and any
  blend result is opaque), in whole 16x16 tiles, as one contiguous block of the frame (the lower-right part of the
  tile walk) plus a few partial tiles at its edge. That is a fragment job stopped part-way, not a blend/coherency error.
- dmesg-repro: 13 x `gpu sched timeout, js=0, config=0x7b00/0x7300, status=0x8, head=tail=...` (js 0 = fragment,
  status 0x8 = ACTIVE: still running when the 500 ms panfrost watchdog fired; the reset throws away the rest of the
  frame) for 14 failing runs, khr-adv 1 (= mixedSequence), no js fault, no page fault.
- The numbers fit a job that is simply too long: 72 % of the tiles done at 500 ms -> the 44-draw job needs ~0.69 s
  (fork; system Mesa 81 % -> ~0.62 s). Predicted for x8 (88 draws, ~1.38 s): 1 - 0.5/1.38 = 64 % lost; measured
  676544/1048576 = 64.5 %. 256x256 (1/16 of the work, ~45 ms) PASS, multiplySequence (7 draws, ~0.11 s) PASS, barrier
  runs (one fragment job per draw, each ~16 ms) PASS. Cost per fragment: 44 x 1 M fragments of an LD_TILE + advanced
  blend shader in 0.69 s = ~67 M fragment-shader invocations/s on the single G31 core: plausible, no hang.
- So the failure is the kernel's job watchdog, the same mechanism as the OpenCL long jobs and the VK spirv_assembly
  fragment cases (impl-opencl-fixes.md "Root cause: panfrost job timeout"). That is fixed by the soft-stop/resume series
  in test-cumulative (e544ddb00 + 0b7e3a208 + e17629bba, c27+; job 28 PASS, job 46 tdim PASS on c38): a long job is
  soft-stopped at a tile boundary and resumed, never reset. No Mesa change is needed or made; the extension stays on.
- deqp-fbo: 3 timeouts with the same head 0xa1265c0, 512 ms apart (one job resubmitted after each reset): most likely
  dEQP-GLES31.functional.fbo.no_attachments.maximums.all (no-attachment framebuffer at the maximum size, the one Fail of
  that chunk, also Fail in the baseline): another long job, expected FIXED on c38. Not proven (results.csv has no
  per-case times).
- Fork vs system Mesa: the fork is ~10 % slower on this job (0.69 vs 0.62 s; knob-all = old descriptors is as slow, so
  not dc7266d584b; build-cl is debugoptimized + b_ndebug). Perf, deferred.
- Job 48's version check looked for the literal `git-dc7266d584`; the version string carries the fork HEAD
  (`git-02df572101`). Fixed: the package checks `git merge-base --is-ancestor dc7266d584b HEAD` (runner.log `fork: ...
  (contains dc7266d584b)`) and that build-cl is built from mesa-cl HEAD (exit 1 "stale build" otherwise).

## Board validation 2: runner job harness/runner-queue/50-gles-advblend.md (queued 2026-11-06)
Same package (runner/gles-advblend.sh, HANDOFF.md, checks 1-7), now: installs the newest cumulative kernel (c38+),
checks the soft-stop series (ancestry of e17629bba + panfrost.ko md5), restores the stock kernel with
vdec-perf/restore-kernel.sh; ftrace count of panfrost_job_timedout per chunk (trace-<c>.txt) and per repro run (`ms=`
wall time, `TO=` cumulative watchdog hits on every TAG line); `gpu sched timeout` in repro/khr-adv is now a FAIL check.
Results: logs/runner2/ (job 48's stay in logs/runner/).

## Result of job 50 (c38, 2026-11-06): DONE
- ALL PASS (summary harness/runner-queue/done/50-gles-advblend.summary.md, logs logs/runner2/): fork-mixed x3, -x8,
  -256, -barrier, multiply PASS with TO > 0 (the soft-stop path ran) and no `gpu sched timeout`; mixedSequence
  Fail -> Pass (khr-adv 88/88), no regressions in deqp-fbfetch/-ms/-fbo, khr-ms, gles3 blend a/b; deqp-fbo
  no_attachments.maximums.all Fail -> Pass (the other long job). 0 faults, stock kernel restored.
- sys-mixed (system Mesa 26.2.4) and every knob-* variant (the old descriptors) PASS too, so dc7266d584b is not needed.
- **Fix = the kernel soft-stop/resume series** (e544ddb00 + 0b7e3a208 + e17629bba, test-cumulative c27+). The image
  kernel must carry it (it is not upstream).
- **dc7266d584b reverted** in mesa-work/mesa-cl branch panfrost-opencl-fixes: 5d7c3e57df1 (Generated-by: LLM; nothing
  else used the PAN_DBG_FBFETCH_OPAQUE/OVERDRAW/PERSAMPLE_1X knobs; 02df5721016 is independent). build-cl rebuilt
  incrementally (rc 0), build-host-shim too; build-arm64 (mesa main) never had it. runner/gles-advblend.sh still checks
  FORK=dc7266d584b by ancestry: the package is retired, do not rerun it as is.
- Deferred (perf): the fork is ~10 % slower than system Mesa on the 44-draw job (build-cl is debugoptimized).

## Open / next step (before job 50, kept for the record)
- Job 50. Fresh agent after it:
  - fork-mixed* PASS, TO > 0, no `gpu sched timeout`, mixedSequence Pass -> DONE (kernel series = fix; record it in
    impl-gpu-spec.md and the memory file). Then look at the knob/sys lines: if sys-mixed and knob-all PASS too,
    dc7266d584b is not needed for this test -> revert it in the fork (keeps the fork closer to upstream; its descriptor
    changes are then unproven) and drop the knobs; if a knob line FAILS while fork-mixed passes, that descriptor matters:
    keep the commit and say why.
  - fork-mixed FAIL with TO > 0 and 0,0,0,0 tiles -> the resume path loses the rest of a fragment job: kernel
    (panfrost_job.c soft-stop/resume of js 0; check the job-chain head/tail after soft-stop) in a fix/* worktree.
  - fork-mixed FAIL with TO = 0 and non-zero wrong values -> a real coherency problem after all: then pandecode the
    board job (PAN_MESA_DEBUG=trace) as planned below.
- Shipping: the image kernel must carry the soft-stop series (it is in test-cumulative, not upstream).

Older notes (before job 48):
- Waiting for job 15. Fresh agent after it: copy the TAG lines and the compare summaries here; if `fork-mixed` still
  fails, the bad-tile map in files/repro/repro-fork-mixed.txt and the knob lines say what is left (then look at
  the clear-colour tile init vs preload, and at pandecode of the board job with PAN_MESA_DEBUG=trace via the repro).
  If a knob run passes while fork-mixed fails, that knob's descriptor is not the culprit; drop nothing without data.
- Job 09 (opencl-mesa2) deploys the same build-cl as cl2; it now also contains this commit (GL-only change).
- Shipping needs the Ubuntu deb rebuild (user, root).

2026-11-06 (agent opencl-rgb): job 15 was BLOCKED by a package bug (deploy check looked for
lib/dri/libgallium-26.2.4.so; meson installs it as lib/libgallium-26.2.4.so). Fixed in runner/gles-advblend.sh,
requeued as harness/runner-queue/48-gles-advblend.md (the build now also carries 02df5721016, the 24/96-bit image
padding; no effect on the blend cases).
