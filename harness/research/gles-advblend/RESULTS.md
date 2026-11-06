# KHR-GLES31 blend_equation_advanced test_coherency.mixedSequence on the Zero2 (Mali-G31, Bifrost v7.0)

State file of the gles-advblend task (agent 2026-11-05). Memory: project-gles-advblend.md.

## Problem
`KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence` fails (87/88 of the group pass; 5/5 reruns fail,
"results differ"): 4 x 11 fullscreen draws with different advanced blend equations on a 1024x1024 RGBA8 FBO, no barrier
(GL_KHR_blend_equation_advanced_coherent is advertised), one fragment job. First pixel right, not all pixels equal.
Passes with `MESA_EXTENSION_OVERRIDE=-GL_KHR_blend_equation_advanced_coherent` (glBlendBarrier = one fragment job per
draw), `multiplySequence` (7 draws) passes, the 86 other cases (one dependent draw per pixel) pass. No GPU timeouts.
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

## Fix (mesa-work/mesa-cl, branch panfrost-opencl-fixes, commit dc7266d584b, Generated-by: LLM)
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

## Open / next step
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
