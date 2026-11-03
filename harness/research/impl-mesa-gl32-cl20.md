# Route A: GLES 3.2 + OpenCL 2.0 on Mali-G31 with open drivers (panfrost + rusticl): plan

Status 2026-11-03. Owner: Mesa-work agent. The user chose route A on 2026-11-03.
Inputs: `impl-gpu-spec.md` (gap evidence). Mesa main a1c054214a4 (2026-11-02) in the worktree
`mesa-work/mesa`, branch `panfrost-gs-tess`. Code study of asahi and panfrost, plus a GitLab/upstream survey.

**Standing decisions (user, 2026-11-03):** GLES 1.0 follows Ubuntu. Any Mesa we ship keeps
`-Dgles1=disabled`, adds no `libgles1`, and leaves every other Ubuntu packaging flag unchanged unless this work
needs a change, which must be reported first.

## BLOCKER (found 2026-11-03, after this plan was written): Mesa's AI policy for panfrost

* Mesa's in-tree `AGENTS.md` (`CLAUDE.md` symlink, commit 8e21f0441fc) tells AI agents **not to change
  `src/panfrost` or `src/gallium/drivers/panfrost`** and to refer the user to `docs/drivers/panfrost.rst`.
  That page's "AI policy" section says: "we ask developers to refrain from using AI to generate patches. It's OK to
  use AI to analyze code, review test logs, sanity-check patches etc., but please write the code you submit
  yourself." It also asks for no AI-written issue reports or other project communication.
  The same restriction covers `src/asahi` and `src/gallium/drivers/asahi` (asahi LLM policy).
* Elsewhere in Mesa, AI-written commits must carry the exact trailer `Generated-by: LLM` (or `Assisted-by: LLM`
  when a human wrote the code with AI help).
* Consequence: phases G1-G6 put almost all their code in those two directories, so **the agent cannot
  write them**. Only these parts are outside the restricted directories: `src/poly` (shared), `src/compiler/nir`,
  `src/mesa/state_tracker`, `meson.build`, and rusticl (`src/gallium/frontends/rusticl`). The CL phases C1, C2,
  C4, C5 and C7/C8 are mostly rusticl/NIR, so they are allowed with `Generated-by: LLM`. The panfrost parts of
  C3 (memory model), C5 (generic-pointer lowering) and C6 (gallium VM hooks) are restricted.
* Action taken: the commit `meson,panfrost: build libpoly for the gallium driver` (touched
  `src/gallium/drivers/panfrost/meson.build`) was **dropped**. The poly commit was re-labelled `Generated-by: LLM`.
  Branch `panfrost-gs-tess` = main + `15bd751e896 poly: make the work-group scan independent of the subgroup size`.
* Options for the user:
  1. **The user writes the panfrost code.** The agent does what the policy allows: analysis, design,
     test programs, board runs, log triage, and review of the user's patches. It also writes the non-panfrost pieces
     (poly fixes, NIR passes, board tests). This keeps upstreaming possible.
  2. **Downstream-only AI patches**: the user explicitly authorises the agent to write panfrost code for
     image-only patches that are never submitted upstream. This contradicts the in-tree instruction, so it is
     the user's call, not the agent's. It also gives up "aim for upstream" for GL, and the patches carry
     long-term rebase cost alone.
  3. **Do CL first** (C1 non-uniform WG, C2 WG collectives, the rusticl side of C3), where AI work is permitted,
     and revisit GL later.
  4. **Reconsider route B** (Arm DDK) for the GLES 3.2 row only.

## 0. Bottom line (honest)

* **GLES 3.2**: feasible with open code and upstreamable, but large. Nothing upstream implements GS or TS
  for gallium panfrost or for any JM GPU (v4-v7), so this work duplicates nobody. Estimate:
  **~4-6 months** of focused work for GS + XFB + layered + tessellation at conformance quality (§2.5).
  Single-core G31 performance with compute-lowered GS/TS will be low. The row only needs the feature.
* **OpenCL 2.0**: every 2.0 feature is optional in CL 3.0 and hard-coded off in rusticl for *all* drivers.
  Claiming OpenCL C 2.0 requires all of them, including **device-side enqueue** and **pipes**, which no rusticl
  driver has and the JM hardware cannot do natively (an emulation design is in §3). Estimate:
  **~6-9 months**. Most of it is generic rusticl frontend work (upstream owner: Karol Herbst). The panfrost-specific
  parts are the generic-pointer lowering, the atomics memory model, and SVM, which needs a new **kernel uAPI**.
* Order to maximise value: GL first (one clear spec row, self-contained in panfrost). The CL features
  that real programs use (non-uniform WG, WG collectives, device atomics) come next. The exotic 2.0 features
  (pipes, device enqueue) come last.

## 1. Upstream landscape (read-only survey, 2026-11-03)

| Item | State | Relevance |
|---|---|---|
| Gallium panfrost GS/TS | **No MR, branch or tracker item.** Issue #9840 (<https://gitlab.freedesktop.org/mesa/mesa/-/issues/9840>): Daniel Stone, 2025-02-22: "planned, but it's quite a lot of work"; unassigned | Free lane, no duplication |
| !44118 panvk/csf GS via libpoly (<https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44118>) | Open, 30 commits, reviewed (Lars-Ivar 10-09, NXP 10-27), proposed to land behind driconf `panvk_enable_gs_xfb` | **CSF (v10+) only.** The JM side only renames things; `libpan/geometry.cl` kernels are behind `#if PAN_ARCH >= 10`. Reusable pieces: `pan_varying_collect_formats(..., is_sw_vs)`, poly `geometry.h`/`restart.h` tweaks, divergence-analysis for poly intrinsics. We should rebase on top of it once it lands and lift its kernels' arch guard instead of duplicating them |
| panfrost tracker #202 geometryShader / #203 tessellationShader (<https://gitlab.freedesktop.org/panfrost/mesa/-/work_items/202>) | olivia, panvk-CSF. Tess not started | Same as above |
| zink-on-panvk replacing gallium panfrost? | **No.** Gallium panfrost has active 2026-10 backlog (Boris, #319-#325). Zink on panvk is at GLES 2.0 (!38396) | Gallium is the right GL target for v7 |
| Kraid compiler | arch >= 9 only (`pan_use_kraid`) | G31 stays on the Bifrost compiler |
| src/poly | Used by asahi, kosmickrisp (GS merged 2026-10-29, !44786), panvk (heap, draw_helper) | Stable but churning: expect rebases |
| rusticl generic AS !29238, program-scope globals !24515 (+#15611), fine-grain SVM !35375 | Karol, open, idle/WIP; #15611: "really painful feature… not sure when" | Must coordinate, not fork |
| rusticl SVM interface (`alloc_vm`/`resource_assign_vma`/`free_vm`, !32942) | Merged 2025-06; iris/radeonsi implement it | panfrost implements none of it |
| panfrost kernel user-VA uAPI (#14417, <https://gitlab.freedesktop.org/mesa/mesa/-/issues/14417>) | Daniel Stone 2025-12-08: Collabora will "almost certainly" add it for Bifrost/v9 "in the next year or so". No series found (lore.kernel.org returned 403 to us, **unverified**) | **Duplication risk**: talk to Collabora (through the user) before writing the kernel patch |
| WG collectives, pipes, non-uniform WG, device enqueue, device-scope atomics in rusticl | No MRs or issues at all | Free lanes |

## 2. GLES 3.2 on gallium panfrost (Bifrost v7, JM)

### 2.1 Design: lower GS/TS to compute with libpoly, following asahi gallium
* Poly (`src/poly`) is a helper library: `cl/*.cl` → `vtn_bindgen2` → inlined NIR builder functions, and
  `poly_nir_lower_{vs,gs,tess}.c` call them. The *dispatched* kernels (prefix sums, restart unroll, indirect
  setup, tessellator) are still per-driver (`src/asahi/libagx/*.cl`, now `libpan/geometry.cl` in !44118).
* Variants (asahi `agx_compile_variant`, agx_state.c:1502):
  * VS feeding a GS/TCS: `poly_nir_lower_vs_before_gs`, compiled as compute and writing outputs to global memory.
  * GS: `poly_nir_lower_gs` → main/prerast compute GS, optional `gs_count`, a 1×1×1 `pre_gs`
    (XFB offsets/queries), and `gs_copy`, a **hardware VS** that re-runs the GS for one output vertex and
    also performs the XFB stores. A passthrough GS is used for XFB/adjacency/etc.
  * TCS: compute. TES: becomes a VS.
* Draw sequence for GS: [indirect setup] → VS compute → [count] → [prefix sum] → [pre_gs] → GS compute →
  rasterisation draw of `gs_copy` with poly's index buffer and count. Tess: VS → TCS → tessellate(count) →
  prefix_sum_tess → tessellate(write) → indexed-indirect draw of the TES-as-VS.

### 2.2 What gallium panfrost v7 has and lacks (code-verified)
| Area | Today on v7 | Need |
|---|---|---|
| Compute jobs inside a render batch | **Yes**: `jm_launch_xfb` (pan_jm.c:879) puts a COMPUTE job with barrier in the vertex/tiler chain; `GENX(panfrost_launch_precomp)` (pan_precomp.c:226) dispatches libpan kernels into any batch (direct grids) | Reuse for the GS pre-raster jobs |
| Indirect draws | CPU readback + stall (`util_draw_indirect`, pan_cmdstream.c:3569); `PAN_GPU_SUPPORTS_DRAW_INDIRECT` is v10+ | Phase 5: port panvk-JM's GPU path (`panlib_draw_indirect_helper`). Until then, a CPU fallback for indirect GS/TS |
| Indexed draws | v≤7 needs CPU min/max of the index buffer | For poly-generated indices, pass the known bounds and never map |
| XFB | VS variant `nir_lower_xfb_to_stores` run as a compute job; offsets CPU-tracked; indexed XFB TODO | GPU-side offsets + passthrough-GS XFB (asahi model, which also fixes indexed XFB) |
| Queries | PRIMITIVES_GENERATED/EMITTED CPU counters | GPU counters for GS draws (hybrid with the CPU delta) |
| Primitive restart | Native in the tiler | With GS: CPU `util_draw_vbo_without_prim_restart` first, later GPU `poly_unroll_restart` |
| Layered rendering (gl_Layer) | **None in gallium JM** (CSF only) | Port panvk-JM's per-layer FBD/tiler-context + per-layer replay of the raster draw. Required by OES_geometry_shader |
| Sysvals | `PAN_SYSVAL_*` in pan_context.h, `pan_nir_lower_sysvals.c`, `panfrost_upload_sysvals` | Add vp/gp/tp/vs_outputs param pointers, provoking_last, index_size; `load_ro_sink_address_poly` → OOB address |
| Bifrost compiler | Has 32/64-bit global+shared atomics, scratch, barriers, IDs, int64 lowering, subgroups (size 8) | `load_primitive_id` in FS must come from a varying when a GS is present; GS pieces compile as COMPUTE |
| Limits | WG ≤256 threads, subgroup 8, VA 4 GiB, 16 VS inputs | libagx kernels are KERNEL(1024) → resize. **`poly_work_group_scan_inclusive_add` hard-codes subgroup 32 (geometry.h)**: must be generalised in poly (upstream fix) |
| meson | `with_poly` excludes panfrost | Add it |

Bifrost hazard to test first: the visibility of compute-job writes (vertex and index data) to later vertex/tiler
jobs in the same job chain without a CACHE_FLUSH job. panvk JM already relies on this (scoreboard deps +
SUPPRESS_PREFETCH), and the G31 has one core, so the risk is low. Fallback: a CACHE_FLUSH job between pre-raster and raster.

### 2.3 Cube-map arrays
Nothing to write: panfrost already sets `cube_map_array`, and `st_extensions.c` turns on
OES/EXT_texture_cube_map_array as soon as OES_geometry_shader is exposed. The dEQP texture.cube_map_array tests will show
whether the existing sampler path is correct. It is a CTS item, not a design item.

### 2.4 Validation
Board micro-tests (mine, short): `harness/analysis/gpu/gles-gs.py` (GS amplify/emit/EndPrimitive, layered, XFB,
queries) and later `gles-tess.py`. Conformance: dEQP-GLES31 `geometry_shading.*`, `tessellation.*`,
`texture.*cube_map_array*`, and KHR-GLES32. **The GPU CTS agent runs these.** I ask through the coordinator and
reuse its builds and baseline. Regression baseline: its GLES2/3/31 mustpass results on stock 26.2.4 and on my
branch, which must match.

### 2.5 GL phases (each one useful and upstreamable alone)
| # | Phase | Deliverable | Est. |
|---|---|---|---|
| G1 | **Poly infrastructure + GS without XFB** behind `PAN_MESA_DEBUG=gs`: meson `with_poly` for panfrost; poly subgroup-size-agnostic WG scan; libpan GS kernels for v≤9 (or !44118's with the guard lifted); GS CSO/variants; sysvals; poly heap; pre-raster compute jobs; raster draw; CPU fallbacks for indirect + restart | GS programs run correctly for direct draws | 4-6 wk |
| G2 | **Layered rendering on JM gallium** (per-layer FBD/tiler ctx, raster replay with layer kill) | gl_Layer from GS; layered clears/blits | 2-3 wk |
| G3 | **GS XFB + GPU queries + passthrough-GS XFB**, then expose OES/EXT_geometry_shader by default → **OES_texture_cube_map_array appears** | GS ext. on; fixes indexed XFB too | 3-4 wk |
| G4 | **Tessellation** (TCS/TES variants, tessellator kernels, patches draw). GLES version → **3.2** | ES 3.2 context | 4-6 wk |
| G5 | GPU indirect draws on v6/v7 (port panvk-JM helper), GPU restart unroll, indirect GS/TS | Removes CPU stalls (also helps ES 3.1) | 3-4 wk |
| G6 | CTS hardening (KHR-GLES32, dEQP GS/TS), upstream review cycles, Mesa CI on G52 | Conformance-quality, upstream | ongoing |

## 3. OpenCL 2.0 in rusticl on panfrost

### 3.1 Feature table: who owns what
| Feature (2.0 mandatory unless noted) | Generic rusticl / NIR / libclc | panfrost-specific | Est. |
|---|---|---|---|
| Non-uniform work-groups | rusticl: split the NDRange into ≤8 sub-launches with offsets (or a sysval-guarded tail); flip the cap | none | 1-2 wk |
| WG collective functions (reduce/scan/broadcast/any/all) | SPIR-V Workgroup-scope group ops → NIR lowering through shared memory + barriers (a generic `nir_lower_workgroup_ops`, which may help every driver) | none (subgroup 8 path) | 2-3 wk |
| C11 atomics, device scope + seq_cst (atomic caps) | rusticl caps + correct scope mapping | Bifrost memory model: device-scope fences/barriers on JM (one core on G31; the code must be correct for multi-core G52 too) | 1-2 wk |
| Program-scope global variables | rusticl frontend: allocate and initialise a global buffer per program, relocate pointers (Karol's !24515) | none | 3-4 wk (coordinate) |
| Generic address space | rusticl (!29238) + NIR `62bit_generic` lowering | Bifrost has separate global/shared/scratch addressing: generic → tagged pointer + branchy load/store in the backend lowering | 4-6 wk |
| Coarse-grain buffer SVM | rusticl already has the interface (!32942) | **Kernel uAPI** for a user-chosen GPU VA (BO create/map at VA, or a mini VM_BIND) in drm/panfrost, plus gallium `alloc_vm`/`resource_assign_vma`/`free_vm`. 33-bit GPU VA; rusticl's VM-range scheme fits | 4-8 wk (kernel review long; Collabora intends to do this, so coordinate) |
| Pipes | rusticl + libclc: pipe objects as buffers with an atomic ring (reserve/commit), `read_pipe`/`write_pipe` builtins | none | 3-4 wk |
| Device-side enqueue | rusticl: **host-assisted emulation**. The kernel writes enqueue records (block invoke + captured args + ndrange) into a device buffer; after the parent completes, rusticl reads them back and launches the children, iterating until none remain. CL 2.0 children may not start before the parent finishes (`CLK_ENQUEUE_FLAGS_WAIT_KERNEL`; NO_WAIT may legally wait), so this is spec-legal but slow. Needs SPIR-V `OpEnqueueKernel` + block support in vtn | none (JM cannot self-enqueue) | 6-8 wk; highest risk |
| Fine-grain / system SVM | optional in 2.0 | System SVM impossible (no ATS, non-coherent) | skip |

### 3.2 CL order (value first)
C1 non-uniform WG → C2 WG collectives → C3 device-scope/seq_cst atomics (C1-C3 help real programs and every rusticl
driver, and can be upstreamed quickly) → C4 program-scope globals and C5 generic AS (coordinate with Karol's MRs) →
C6 coarse SVM (kernel uAPI; ask user for board time; coordinate with Collabora) → C7 pipes → C8 device enqueue →
claim OpenCL C 2.0 (`CL_DEVICE_OPENCL_C_ALL_VERSIONS` includes 2.0; `check_version` in core/device.rs currently caps
`clc_version` at 1.2). Validation: OpenCL-CTS 2.0 groups (`generic_address_space`, `pipes`, `device_execution`,
`SVM`, `workgroups`, `non_uniform_work_group`, `c11_atomics`, `device_timer`) run by the CTS agent.

## 4. Build and test setup (done 2026-11-03, no root, no Docker)
* Worktree `mesa-work/mesa`, branch `panfrost-gs-tess` off origin/main a1c054214a4, from the blobless clone
  in `harness/research/gpu-src/mesa`.
* Host prefix `mesa-work/deps/host-root`: `dpkg -x` of the Ubuntu 26.10 amd64 debs llvm-22(-dev,-tools), clang-22,
  libclang-22-dev, libclang-common-22-dev, libllvmspirvlib-22-dev, spirv-tools(-dev), glslang, libdrm-dev,
  libwayland-bin and libclc-22. `.pc` files are relocated. The system libLLVM/libclang-cpp are symlinked in.
* Cross compiler `mesa-work/deps/cross-root`: `dpkg -x` of g++-15/gcc-15/cpp-15-aarch64-linux-gnu (the host had
  the gcc driver but no g++).
* Python venv `mesa-work/venv`: meson 1.12.1, ninja, mako, pyyaml, packaging, ply, pycparser.
* Sysroot `mesa-work/sysroot`: rsync of the board's `/usr/lib/aarch64-linux-gnu` (read-only, nice/ionice), plus
  `dpkg -x` of arm64 -dev debs fetched through a private apt config (`deps/apt-arm64`, ports.ubuntu.com,
  Ubuntu keyring). libc6-dev 2.44-1ubuntu2 matches the board.
* Native tools build `build-host` installs `mesa_clc`, `vtn_bindgen2` and `panfrost_compile` to `host-tools/`.
  The cross build `build-arm64` (`tools/setup-arm64.sh`) uses `-Dmesa-clc=system -Dprecomp-compiler=system`, with ccache.
  Full build 3 min 15 s; incremental builds are seconds.
* **Rust is not installed on the host.** Panfrost's optional Rust parts are off (`-Dpanfrost-rust=false`).
  Rusticl (phase C) needs rustc ≥1.85 + bindgen ≥0.71. Plan: `dpkg -x` Ubuntu's rustc 1.97 / bindgen 0.72 /
  libstd-rust-dev(+arm64) debs, as for the other build dependencies.
* Board test: `tools/deploy.sh <build> <name>` installs to a stage dir, strips, and rsyncs to
  `/root/opiz2-mesa/<name>/` with an `env.sh` (LD_LIBRARY_PATH, `__EGL_VENDOR_LIBRARY_FILENAMES`,
  LIBGL_DRIVERS_PATH, GBM_BACKENDS_PATH). Only the test process sees it; system files are untouched.
  Verified: `gles-func.py` under main reports "OpenGL ES 3.1 Mesa 27.0.0-devel (git-a1c054214a)" and PASS on all
  checks, fill rate matching the system 26.2.4.

## 5. Shipping in the image (proposal: needs user approval before touching the image build)
* Base: the image ships Ubuntu's `mesa 26.2.4-1ubuntu1`. Development is on main (for upstreaming). To ship
  before upstream lands, **backport the finished series to 26.2.4** as quilt patches in Ubuntu's source package
  (`debian/patches/opiz2-*.patch`), version `26.2.4-1ubuntu1+opiz2.N`, with **all Ubuntu flags unchanged**
  (`-Dgles1=disabled` included). The backport is real work: poly has had 7 commits and panfrost many more since 26.2.4.
  The alternative is to wait for the Ubuntu Mesa that contains the upstreamed work and ship nothing patched.
* Build: the deb build needs root (sbuild/pbuilder chroot, arm64). Options for the user to choose:
  (a) inside the Armbian `compile.sh` run, as an extension that builds the source package in the arm64 rootfs chroot
  (qemu-user, slow: about 1-2 h, cached by source hash in `cache/`); (b) a native sbuild on an arm64 machine with
  root, debs committed to the build cache; (c) cross `dpkg-buildpackage -aarm64` in a root chroot on the host.
  The image then installs the debs in `post_customize_image` with `apt-mark hold` (or a local apt repo with pin
  priority) so apt does not replace them. The libclc diversion branch (`feat/gpu-mesa-libclc`) stays separate.
* Each finished phase gets: a branch in `mesa-work/mesa` (`opiz2/gl-gN-*`), a 26.2.4 backport branch, and a
  note here. Image-build changes only after the user approves.

## 6. Risks / unverified
* Compute→vertex/index visibility in one JM chain without CACHE_FLUSH (test early in G1).
* The cost of layered rendering on JM (per-layer tiler contexts) may make the dEQP layered tests slow on one core.
* Upstream churn: !44118 and olivia's XFB/queries branches modify poly and libpan. I will rebase on them
  rather than diverge, and lift their v10 guards when they land.
* Kernel uAPI for SVM: Collabora intends to do it. Writing our own risks a rejected duplicate.
* Device enqueue emulation: spec-legal by my reading of §5.13 and NO_WAIT semantics, but the CTS
  `device_execution` group has not been checked against this design. **Unverified.**
* The fable model was unavailable (usage limit) for the design study. It ran on the default model.

## 7. RESUME STATE (paused 2026-11-03 at the coordinator's request)

**Mesa branch** `panfrost-gs-tess` in `mesa-work/mesa`: main a1c054214a4 + `15bd751e896 poly: make the work-group scan
independent of the subgroup size` (`Generated-by: LLM`, kept). Working tree clean. **There is no WIP commit because no C1 code
was written yet.** GL (G1-G6) is on hold pending the user's choice of option 1, 2 or 4 (see BLOCKER). Do not touch
`src/panfrost`, `src/gallium/drivers/panfrost` or the asahi directories.

**C1 (rusticl non-uniform work-groups): where it stands.** Toolchain setup was half done:
* Done: the Rust toolchain was `dpkg -x`'d into `mesa-work/deps/rust-root` (rustc 1.97.1, bindgen 0.72.1; host std plus the
  arm64 std copied into `usr/lib/rust-1.97/lib/rustlib/aarch64-unknown-linux-gnu`). `tools/env.sh` adds rust-root to PATH and
  LD_LIBRARY_PATH (rustc has no rpath). `tools/cross-aarch64.ini` now has a `rust = [... --target aarch64-unknown-linux-gnu,
  linker = cross gcc, --sysroot]` entry and `llvm-config = tools/llvm-config-arm64`.
* Done: arm64 llvm-22-dev, libllvm22, libclang-cpp22(-dev), libclang-22-dev, libclang-common-22-dev, LLVMSPIRVLib, spirv-tools-dev,
  libclc-22(-dev), libxml2/ncurses/edit/z3 were `dpkg -x`'d into `mesa-work/sysroot`. All sha256s are in `deps/SHA256SUMS` (118 debs).
* **Not done (next steps):**
  1. Write `tools/llvm-config-arm64`: a shell wrapper that answers `--version/--libdir/--includedir/--cppflags/--libs/
     --shared-mode/--components/--targets-built` for the arm64 sysroot (`sysroot/usr/lib/llvm-22`). Model it on the host
     llvm-config (same 22.1.8) with paths rewritten. Fix the arm64 `.pc` prefixes in the sysroot (LLVMSPIRVLib libdir →
     `lib/aarch64-linux-gnu`, SPIRV-Tools), and fix any absolute symlinks in the sysroot's `usr/lib/llvm-22/lib`.
  2. Configure a separate build dir: `tools/setup-arm64.sh build-cl -Dgallium-rusticl=true -Dllvm=enabled
     -Dshared-llvm=enabled -Dmesa-clc=system -Dprecomp-compiler=system`. Mesa may want `mesa-libclc`; it falls back to the upstream libclc .pc,
     and the board needs the mesa-libclc 22.1.8.3 .spv (see impl-gpu-spec.md §3.3) bind-mounted for sin/cos.
     panfrost-rust stays off. Build `ninja -C build-cl`, then deploy with `tools/deploy.sh build-cl cl` (also stage `etc/OpenCL/vendors`
     and set `OCL_ICD_VENDORS`/`OCL_ICD_FILENAMES` to `/root/opiz2-mesa/cl/lib/libRusticlOpenCL.so.1`, plus `RUSTICL_ENABLE=panfrost`).
     Extend deploy.sh for that.
  3. Baseline: `harness/analysis/gpu/cl-probe.py` under the built rusticl (expect the same results as 26.2.4).
  4. Implement C1 in `src/gallium/frontends/rusticl` only. Report `CL_DEVICE_NON_UNIFORM_WORK_GROUP_SUPPORT` = true (api/device.rs:236).
     In the enqueue path (`core/kernel.rs` launch / `api/kernel.rs` clEnqueueNDRangeKernel validation), when global % local != 0,
     split into up to 2^dims launches (main block + remainder blocks) using global offsets, honouring `-cl-uniform-work-group-size`
     and the CL 2.0/3.0 rules (`get_enqueued_local_size()` must return the requested local size: check how rusticl lowers
     `load_enqueued_local_size`). Also allow a NULL local size with any global size. Commit with `Generated-by: LLM` and Signed-off-by.
  5. Board test: extend cl-probe.py (1000 items with local 64 must now pass, plus a 3D ragged case and a
     get_local_size/get_enqueued_local_size check). Ask the coordinator for the CTS agent's `non_uniform_work_group` + `basic` + `api`
     results on stock vs branch.
* Then C2 (WG collectives: NIR lowering in `src/compiler/nir`, rusticl cap) and the rusticl side of C3 (atomic caps).
  Stop and report if anything needs a panfrost-side edit.

**Build commands (all as user, no root):**
```
. /home/aruni/orangepizero2/mesa-work/tools/env.sh
ninja -C $MW/build-host install          # host tools: mesa_clc, vtn_bindgen2, panfrost_compile -> host-tools/bin
ninja -C $MW/build-arm64                 # GL/EGL/GBM panfrost cross build (no rusticl)
$MW/tools/deploy.sh build-arm64 main     # -> board /root/opiz2-mesa/main/ (env.sh there)
harness/ssh.sh '. /root/opiz2-mesa/main/env.sh; python3 -' < harness/analysis/gpu/gles-func.py
```
Left in place: `mesa-work/` (worktree, deps, sysroot, builds, venv) and the board's `/root/opiz2-mesa/main` (23 MB, Mesa main
a1c054214a4 build). Stray temp dir `/tmp/tmp.SzBGCLlWi7` (an arm64 libstd-rust extract, already copied) can be deleted.
