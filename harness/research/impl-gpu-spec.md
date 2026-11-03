# GPU spec rows (Mali-G31 "MP2", GLES 1.0/2.0/3.2, OpenCL 2.0): research + plan

Spec rows (docs/spec-checklist.md lines 8-9): "GPU Mali G31 MP2, OpenGL ES 1.0/2.0/3.2" and
"GPU OpenCL 2.0". Board: kernel 7.3.1-edge-sunxi64 (Armbian integration a2371fdc1), Ubuntu 26.10,
Mesa 26.2.4-1ubuntu1, libclc-22 1:22.1.8-1ubuntu1, LLVM 22.1.8. Measured 2026-11-02/03 during the
Ethernet soak, using only short read-only GPU runs (no reboot, no driver load or unload).
Mesa source read from a blobless clone at `harness/research/gpu-src/mesa` (git-ignored), checked
at the tags `mesa-26.2.4` and `mesa-26.3.0-rc3`, and at `origin/main` 05c46778a97 (2026-10-27).

Board scripts (all run as `harness/ssh.sh 'python3 -' < script`; nothing to install):
* `harness/analysis/gpu/gpu-regs.py [--mmio]`: panfrost GET_PARAM ioctls, plus raw MMIO reads
  through /dev/mem. With `--mmio` it holds a runtime-PM reference and restores `auto` afterwards.
* `harness/analysis/gpu/gles-exts.py MAJOR MINOR`: surfaceless EGL context with version, renderer and extension list.
* `harness/analysis/gpu/gles-func.py`: GLES 3.1 smoke test with no display (compute→SSBO, 1080p
  FBO render + readback, fill rate).
* `harness/analysis/gpu/cl-probe.py`: OpenCL correctness kernels, then a probe for each OpenCL 2.0 feature.
* `harness/analysis/gpu/spv-imports.py`: lists the unresolved (Import-linkage) symbols in a libclc .spv file.

## Verdict per row

| Row | Can it be met? | Short reason |
|---|---|---|
| "Mali G31 **MP2**" | **No. The silicon has one shader core.** Document it as a marketing label. | SHADER_PRESENT = 0x1 in the hardware register. Allwinner's own manual says only "G31". Amlogic's "G31 MP2" (S905X3) also reads 0x1. |
| GLES 2.0 | **Yes**, met today | The ES 2.0 context works (it returns the backward-compatible 3.1 context). |
| GLES **1.0** | **Not today, but fixable by packaging** (new finding) | Debian/Ubuntu build Mesa with `-Dgles1=disabled`. No ES1 EGL config, ES1 context → EGL_BAD_ALLOC. Needs a Mesa rebuild with `-Dgles1=enabled` plus `libgles1` (§2.0). |
| GLES **3.2** | **Not with any released Mesa.** Possible only through (A) new Mesa driver work (GS + tessellation) or (B) the Arm proprietary stack. | Missing in panfrost: geometry shaders, tessellation, and so OES_texture_cube_map_array. Nothing exists for Bifrost/JM upstream or in an open MR. |
| OpenCL **2.0** | **Not with rusticl.** Possible only through (B) the Arm stack. With rusticl the row can be "OpenCL 3.0 with 1.2 C, conformance subset passing", plus a documented 2.0 gap. | rusticl hard-codes generic AS, program-scope globals, pipes, device enqueue, WG collectives and non-uniform WG to "unsupported" for every driver. SVM needs panfrost kernel uAPI work. |
| (found) OpenCL correctness | **Fixable now (image change)** | Ubuntu's upstream libclc-22 breaks `sin()`/`cos()` and friends on rusticl. Mesa's libclc fork 22.1.8.3 is a drop-in fix. See §3.3. |

## 1. MC1 vs MP2: the G31 on H616 has exactly one shader core

Evidence:
1. **Hardware registers, read live** (`gpu-regs.py --mmio`, GPU runtime-active while reading). GPU base
   0x01800000 comes from the DT node `gpu@1800000`, reg <0x1800000 0x40000>.
   ```
   0x000 GPU_ID            0x70930000   (Mali-G31, r0p0)
   0x100 SHADER_PRESENT_LO 0x00000001   0x104 SHADER_PRESENT_HI 0x00000000
   0x110 TILER_PRESENT_LO  0x00000001   0x120 L2_PRESENT_LO     0x00000001
   0x140 SHADER_READY_LO   0x00000001   (the one present core is powered and ready)
   0x004 L2_FEATURES 0x07100206 (64 KiB L2)  0x0a0 THREAD_MAX_THREADS 0x200  0x008 CORE_FEATURES 0
   ```
   The panfrost ioctl values are identical (SHADER_PRESENT=0x1, STACK_PRESENT=0x1), and so is
   dmesg: `panfrost 1800000.gpu: shader_present=0x1 l2_present=0x1`.
   SHADER_PRESENT is a read-only register describing the synthesized configuration. Power
   state does not affect it; power state is reported by SHADER_READY/PWRTRANS. So no power domain, DT
   property or driver setting can "hide" a second core. There are no bits above bit 0.
2. **Mesa reports it correctly.** "Mali-G31 MC1" comes from popcount(shader_present) in
   `src/panfrost/lib/pan_props.c`. clinfo shows "Max compute units 1" from the same source.
3. **Vendor BSP agrees.** The orange-pi-5.4-sun50iw9 Arm kbase r20p0 (`modules/gpu/mali-bifrost/
   driver/.../platform/sunxi/mali_kbase_config_sunxi.c`) has no core mask and no per-core power
   control. It has a single PRCM gate (`GPU_POWEROFF_GATING_REG` 0x07010254, bit 0) for the whole GPU. The
   vendor DT node `sun50iw9.dtsi:466` has `compatible = "arm,mali-midgard"` and nothing core-related.
   kbase reads the same SHADER_PRESENT register and would find one core too.
4. **Allwinner never says MP2.** The H616 User Manual V1.0 §2.2.2 "GPU Architecture" says only
   "G31 · Supports OpenGL ES 1.0/2.0/3.2, Vulkan 1.1, OpenCL 2.0"
   (`kernel-check/work-audio/vendor/H616_User_Manual_V1.0_cleaned.pdf`, pdftotext line 373).
   "MP2" comes from the Orange Pi product page.
5. **Same label, same silicon elsewhere.** The Amlogic S905X3 is also sold as "Mali-G31 MP2" (Banana Pi M5,
   X96 Air). Its panfrost dmesg in Mesa issue #4791 is `mali-g31 id 0x7093 ... shader_present=0x1`
   (<https://gitlab.freedesktop.org/mesa/mesa/-/issues/4791>, see also #8054). "MP2" across the
   industry does not mean two shader cores in SHADER_PRESENT.
6. Throughput is consistent with one core. In `gles-func.py`, a 1080p flat-colour pass with a flush per frame
   runs at 461 fps = 956 Mpix/s = **1.59 pix/clk at 600 MHz**. Arm's launch figure for the G31 is
   "1.3 Gpix/s at 650 MHz" = 2 pix/clk (CNX, 2018-03-06,
   <https://www.cnx-software.com/2018/03/06/arm-introduces-mali-g52-mali-g31-gpus-mali-d51-display-processor-and-mali-v52-video-processor-for-mainstream-devices/>).
   The most likely origin of the "MP2" label is therefore a single core at 2 pixels per clock,
   not two cores. This is an inference; Arm does not publish the per-core pixel rate of G31
   configurations.

Conclusion: the row cannot be "fixed". Nothing on this board is disabled. The spec gap should be
written up as "G31 single shader core (SHADER_PRESENT=0x1); 'MP2' is the vendor's marketing
designation and the hardware cannot change it". The evidence for that is this section.

Side note: PLL_GPU is 300-600 MHz per the H616 User Manual, which matches the devfreq OPPs 306-600 MHz
(available_frequencies on the board). The 800 MHz that clinfo reports is a placeholder in Mesa:
`pan_screen.c:655 caps->max_clock_frequency = 800; /* MHz -- TODO */`. It is cosmetic.

## 2. GLES 3.2: exactly what is missing and what it would take

### 2.0 GLES 1.x is missing too (packaging, not hardware)
* On the board: `eglChooseConfig(EGL_RENDERABLE_TYPE=EGL_OPENGL_ES_BIT)` returns **0 configs**, and an
  ES 1.1 context fails with EGL_BAD_ALLOC (0x3003). eglinfo lists only the GL core/compat 3.1 and ES 3.1
  profiles. `libGLESv1_CM` is not installed; `libgles1` (glvnd, 1.7.0-3) is available in the archive.
* Cause: Debian and Ubuntu configure Mesa with `confflags_GLES = -Dgles1=disabled -Dgles2=enabled`
  (`debian/rules:186` in both <https://salsa.debian.org/xorg-team/lib/mesa/-/raw/debian-unstable/debian/rules>
  and <https://git.launchpad.net/ubuntu/+source/mesa/plain/debian/rules?h=ubuntu/devel>). ES 1.x in
  Mesa is the core st/mesa fixed-function path, which works on every gallium driver, panfrost included.
  Only the build flag is missing.
* Fix: rebuild Ubuntu's `mesa 26.2.4-1ubuntu1` source package with `-Dgles1=enabled` (a one-line
  debian/rules change, version `26.2.4-1ubuntu1+opiz2.1`), add `libgles1` to the image, and verify with an
  ES 1.1 context plus a small fixed-function draw. Mesa implements ES 1.1, which is a superset of 1.0. The
  build needs root (sbuild/chroot); `unshare -Ur` is blocked on this host, so it must run under your
  `compile.sh` session or on a machine with root. Carry the debs in the build cache. Any Mesa rebuild for
  Option A below would carry this flag too.

### 2.1 What the board exposes
`gles-exts.py 3 2`: `eglCreateContext(ES 3.2)` fails with EGL_BAD_MATCH (0x3009). The ES 3.1
context reports `OpenGL ES 3.1 Mesa 26.2.4-1ubuntu1`, `GLSL ES 3.10`, and 142 extensions
(`harness/analysis/gpu/gles31-exts.txt`). Every extension in the ES 3.2 set is present
except these:

| Missing | Why |
|---|---|
| GL_OES/EXT_geometry_shader | panfrost reports `shader_caps[MESA_SHADER_GEOMETRY].max_instructions = 0`. `st_extensions.c:1367` requires GS instructions > 0 and MaxGeometryShaderInvocations >= 32 |
| GL_OES/EXT_tessellation_shader | no TCS/TES stages, so ARB_tessellation_shader is off |
| GL_OES/EXT_texture_cube_map_array | **a consequence, not a gap of its own.** panfrost sets `caps->cube_map_array = true` (pan_screen.c:751), but `st_extensions.c:1779` makes OES_texture_cube_map_array depend on OES_geometry_shader |

Mesa's ES 3.2 gate (`src/mesa/main/version.c:530`, `compute_version_es2`) requires
OES_geometry_shader, ARB_tessellation_shader and OES_texture_cube_map_array, among others.
`docs/features.txt` at 26.2.4 lists panfrost as DONE for every other GLES 3.2 line, but not for
GL_OES_geometry_shader, GL_OES_tessellation_shader or GL_OES_texture_cube_map_array, and panfrost
is absent from the "GLES3.2 -- all DONE" list. Present and working on the board: KHR_blend_equation_advanced,
KHR_robustness, ASTC LDR, OES_copy_image, draw_buffers_indexed, draw_elements_base_vertex,
gpu_shader5, primitive_bounding_box, sample_shading, sample_variables, shader_image_atomic,
shader_io_blocks, shader_multisample_interpolation, texture_border_clamp, texture_buffer,
texture_stencil8, texture_storage_multisample_2d_array, EXT_color_buffer_float, KHR_debug.

### 2.2 Newer Mesa? No
* `mesa-26.3.0-rc3` and `origin/main` (2026-10-27): pan_screen.c still has no GS/TS caps. panvk on main
  still has `.geometryShader = false, .tessellationShader = false`
  (`src/panfrost/vulkan/panvk_vX_physical_device.c:315`). Since 26.2.0 no panfrost commit
  mentions geometry or tessellation.
* Open MRs (GitLab API search, label panfrost, 2026-11-03):
  * **!44118 "panvk/csf: start implementing experimental GS support"** (olivia, open, updated
    2026-10-31) <https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44118>. It uses libpoly
    (`src/poly`, the compute-based GS/tess lowering shared with asahi) and is gated behind the driconf
    `panvk_enable_gs_xfb`. It covers **Vulkan on CSF only (v10+, G310/G610 and newer)**, not
    gallium GL and not Bifrost/JM.
  * Related merged infrastructure: !37969 "panvk: hook up poly_heap and replace existing JM
    indirect vary buffer mechanism" (2025-10). panvk's JM (Bifrost) backend already allocates the poly
    heap, so the lowering library can run on v7 in principle.
  * Open issue #9840 "Panfrost - bifrost geometry shaders. Blender 3.0 does not work" (2023, still open)
    <https://gitlab.freedesktop.org/mesa/mesa/-/work_items/9840>.
* Status: panfrost GLES 3.1 is Khronos-conformant on G52, which has the same Bifrost v7 ISA as the G31
  (<https://www.collabora.com/news-and-blog/news-and-events/panfrost-achieves-opengl-es-3.1-conformance-on-mali-g52.html>).
  Mesa CI runs the full gles2/gles3/gles31 and KHR-GLES mustpass on G52 (Khadas VIM3, job
  `panfrost-g52-gl`). `src/panfrost/ci/panfrost-g52-fails.txt` contains **zero** dEQP-GLES/KHR-GLES
  entries, and `-skips.txt` contains one (`dEQP-GLES31.functional.fbo.no_attachments.maximums.all`). The G31
  is not in Mesa CI.

A Mesa backport therefore gains nothing for 3.2. Neither the Ubuntu 26.10 archive, a PPA nor
26.3/main has the feature.

### 2.3 Rejected shortcut
`MESA_GLES_VERSION_OVERRIDE=3.2` only changes the version string. GS/TS shaders still fail to
compile and dEQP-GLES32/KHR-GLES32 would fail, so it hides the gap instead of meeting the row.
Do not ship it.

### 2.4 What it would take
**Option A, Mesa driver work (open source, keeps panfrost):** implement GS and tessellation in the
gallium panfrost driver for v7 JM by lowering both to compute with libpoly, the way asahi's
gallium driver does it.
1. Shader side (`src/gallium/drivers/panfrost/pan_shader.c`, `src/panfrost/compiler`): lower VS→compute
   when GS/TS is bound, GS with `poly_nir_lower_gs`, TCS/TES with poly's tessellator kernels, plus a passthrough
   rasterization VS. Bifrost has no hardware GS/TS stage.
2. Command stream (`pan_cmdstream.c` / `pan_jm.c` per-gen JM path): run pre-draw compute jobs
   that write to the poly heap, then an IDVS/tiler job from the generated index/vertex buffers.
   Cover indirect draws, primitive restart, gl_PrimitiveID, layered rendering, XFB from GS,
   and PRIMITIVES_GENERATED queries.
3. Caps (`pan_screen.c`): GS/TCS/TES shader caps, max GS invocations >= 32, max output vertices/components.
   OES_texture_cube_map_array then turns on automatically.
4. Validation: dEQP-GLES31 geometry_shader/tessellation groups plus KHR-GLES32 mustpass on the board,
   then upstream through Mesa CI on G52.
Effort: a multi-month project for an experienced Mesa/Panfrost developer. The CSF Vulkan GS
alone (!44118 plus the xfb-queries branch) has taken the upstream author since 2025-10. Single-core G31
performance with compute-lowered GS/TS will be poor, but the row only asks for the feature.
Best route: coordinate with olivia (!44118) and Collabora so the JM gallium path reuses
the same libpoly plumbing, and carry the patches in Armbian as a Mesa build until they land upstream.

**Option B, Arm's proprietary Bifrost stack (gets GLES 3.2 *and* OpenCL 2.0):**
* Userspace: Rockchip's Arm DDK build `libmali-bifrost-g31-g24p0-{gbm,wayland-gbm,x11-gbm,cl}.so`
  for aarch64 (built for RK3326/PX30, also a "G31 MP2") from
  <https://github.com/JeffyCN/mirrors/tree/libmali> (`lib/aarch64-linux-gnu/`). The Arm EULA shipped
  with it (`END_USER_LICENCE_AGREEMENT.txt` §1.1-1.2) allows use with any "Mali-based product" and
  redistribution of the whole package with the licence included.
  Arm's DDK on G31 provides GLES 3.2, Vulkan 1.1 and OpenCL 2.0 Full Profile. This matches the H616 manual and has to be verified on the board.
* Kernel: an out-of-tree Arm kbase at a version matching the g24p0 user/kernel ABI, ported to 7.3,
  with sunxi platform glue. The vendor r20p0 glue `mali_kbase_config_sunxi.c` is GPL and covers clocks, PRCM gate,
  regulator and DVFS. kbase and panfrost cannot both drive the GPU, so this would be a build-time
  or overlay-time choice of driver (DT `compatible` / module blacklist). Choosing kbase loses
  Mesa GL/rusticl on that image, so both paths would have to be kept buildable to avoid losing features.
* Risks: closed blob; kbase churn on every kernel bump (7.3 is far newer than any Rockchip
  BSP kbase); display through GBM/dmabuf with sun4i-drm needs testing; no upstream support.
  Effort: about 1-3 weeks to get a working build, plus ongoing maintenance.

**Recommendation for the GLES row:** keep panfrost (open and conformant at 3.1) as the
default. To satisfy the row's literal number, pick A (long, upstreamable) or B (fast, proprietary,
a separate driver variant). With A, GLES 3.2 stays a documented GAP until the work lands. Decision needed from you.

## 3. OpenCL "2.0"

### 3.1 What it means
OpenCL 3.0 made every 2.0 feature optional, and rusticl reports `Device Version OpenCL 3.0`,
`Device OpenCL C Version OpenCL C 1.2` (`harness/analysis/gpu/clinfo.txt`). Under 3.0 rules,
CL_DEVICE_OPENCL_C_VERSION = 1.2 means the device does **not** claim OpenCL C 2.0. Meeting "OpenCL 2.0"
literally means a CL 2.0 device, or a CL 3.0 device with all of the 2.0 features below.

| OpenCL 2.0 feature | Board (rusticl 26.2.4 + panfrost) | Where it is decided | Needed |
|---|---|---|---|
| Coarse-grain buffer SVM | **No** (`clSVMAlloc` → NULL; clinfo SVM caps empty) | rusticl `core/device.rs:1299 svm_supported()` needs `system_svm` or `alloc_vm`/`resource_assign_vma`/`free_vm`. panfrost implements none of these (same on main) | panfrost uAPI to map a BO at a GPU VA chosen by userspace (panfrost JM has kernel-chosen VAs and no VM_BIND), plus the gallium hooks. The GPU VA is 33 bits (MMU_FEATURES 0x2821), which rusticl's VM-range scheme can handle |
| Fine-grain buffer/system SVM | No | `system_svm` | Optional in 2.0. System SVM is impossible here: no shared page tables/ATS, and the GPU is not DT-coherent |
| Generic address space | **No** (`CL_DEVICE_GENERIC_ADDRESS_SPACE_SUPPORT` false; the CL3.0 generic-pointer kernel is rejected) | **hard-coded** `api/device.rs:91 v.write::<bool>(false)` for every driver (also on main :95) | rusticl frontend work (Karol Herbst's roadmap) plus panfrost support for generic pointers (local/WLS vs global tagging) |
| Program-scope global variables | **No** ("program scope variable must reside in constant address space") | **hard-coded** `api/device.rs:179 MAX_GLOBAL_VARIABLE_SIZE 0` | rusticl frontend |
| Pipes | **No** | **hard-coded** `api/device.rs:239` | rusticl frontend. Almost no CL 3.0 implementation has pipes |
| Device-side enqueue | **No** | **hard-coded** `api/device.rs:59-62` | rusticl plus hardware/firmware; the JM GPU cannot self-enqueue, so it would need emulation |
| Work-group collective functions | **No** | **hard-coded** `api/device.rs:350` | rusticl lowering (doable via local memory) |
| Non-uniform work-groups | **No** (enqueue of 1000 items with local size 64 → CL_INVALID_WORK_GROUP_SIZE, -54) | **hard-coded** `api/device.rs:218` | rusticl |
| C11 atomics, device scope / seq_cst | **No** (caps: relaxed, work-group scope only) | rusticl atomic caps | rusticl plus driver memory model |
| SPIR-V IL | Yes (1.0-1.6) | | |
| fp16 (cl_khr_fp16), int64, images incl. 3D writes, depth images | **Yes**, verified by kernels | | |

Observation: `-cl-std=CL2.0` is **accepted** by rusticl's compiler. A generic-pointer kernel
built with it compiles, although the device reports OpenCL C 1.2. Strictly this should be
CL_INVALID_BUILD_OPTIONS. It is a rusticl leniency, and it is not 2.0 support.

Conclusion: with rusticl (26.2, 26.3 and main), the "OpenCL 2.0" row **cannot be met** on any
Mali, or on any rusticl driver for most of the rows above. The missing pieces are mostly in the frontend,
plus kernel uAPI for SVM. The only way to reach 2.0 in the near term is Option B (Arm DDK
`libmali-bifrost-g31-g24p0-cl`).

### 3.2 Board results (`cl-probe.py`, 2026-11-03; math checked in ULPs against references computed from the exact f32 inputs, limits from OpenCL 1.2 §7.4)
```
vector fma 1M floats                                    PASS
local reduction + barrier + global atomic_add           PASS
fp16 arithmetic + 64-bit integers                       PASS
sqrt 1.6 / exp 0.8 / log 1.2 / pow 0.5 / atan 1.2 / tanh 2.0 ulp   PASS
native_sin                                              implementation-defined (large error away from 0, allowed)
sin, cos                                                FAIL to build: "Internal compilation error: nir_shader not fully linked"
```

### 3.3 Found bug: upstream libclc-22 breaks rusticl's sin/cos (fix: Mesa libclc fork)
* Ubuntu ships Mesa 26.2.4 with the **upstream** `libclc-22 1:22.1.8-1ubuntu1`. Every OpenCL
  program prints `Rusticl warning: Patched Mesa libclc not detected...` (added by Mesa commit
  ba022bc4ced, MR !43020).
* `spv-imports.py` on `/usr/lib/clc/spirv64-mesa3d-.spv` (Ubuntu) finds the unresolved import
  `_Z37__clc_flush_denormal_if_not_supportedf`. sin/cos call it, and rusticl does not provide it. rusticl
  only provides `__clc_*_subnormals_supported` / `__clc_denormals_are_zero_*`
  (`rusticl_nir.c:195-204`). Since 26.1.5 rusticl rejects unlinked NIR (commit 02e187d684c "rusticl:
  abort compilation if the nir shader is not fully linked"), which produces the error. Upstream reports of the same
  error: #15971, #16042 (radeonsi).
* Mesa's fork **mesa-libclc 22.1.8.3** (<https://gitlab.freedesktop.org/karolherbst/mesa-libclc>,
  release notes: "Ensures `__clc_flush_denormal_if_not_supported` has an implementation fixing
  compilation failures"; also fixes tgamma) ships drop-in `spirv64-mesa3d-.spv`. The README says
  "Pre-built binaries that can be used as drop-in replacements". Downloaded into
  `harness/research/gpu-src/dl-mesa-libclc-22.1.8.3/` (sha256
  `728cdfa747a1857829c104291984964971783a301a62e9468a3d5a4f1750c949`, 5 681 480 bytes).
  `spv-imports.py` finds no unresolved libclc symbols in it, only the two SPIR-V builtins.
* Board test of the fork in a private mount namespace (bind-mounted over the Ubuntu file, nothing
  changed on disk): see §3.4.
* Mesa 26.3 builds against the fork (commit 6f2f3ceab8c "clc: use our downstream fork of
  libclc"), so a future Ubuntu Mesa 26.3 will need a `mesa-libclc` package anyway.

### 3.4 Fork test on the board: PASS
`unshare -m` + `mount --bind /tmp/spirv64-mesa3d-.spv /usr/lib/clc/spirv64-mesa3d-.spv` (private
mount namespace; the host namespace and disk are unchanged, as `findmnt` confirmed), same `cl-probe.py`:
```
                 distro libclc-22 22.1.8-1ubuntu1     mesa-libclc 22.1.8.3
sin              build FAIL (not fully linked)        1.5 ulp PASS
cos              build FAIL (not fully linked)        1.4 ulp PASS
sqrt/exp/log/pow/atan/tanh   PASS                     PASS (same ULPs)
"Patched Mesa libclc not detected" warning   printed  gone
2.0 feature probe            identical (libclc does not affect it)
```
So the fork is a confirmed drop-in fix. Branch prepared (§6).

### 3.5 Conformance subset (needs your approval: external suite)
Plan: build Khronos **OpenCL-CTS** on the host. Cross-compile with `aarch64-linux-gnu-gcc`;
the arm64 sysroot comes from `dpkg -x` of the Ubuntu 26.10 arm64 debs `ocl-icd-opencl-dev` and
`opencl-headers`, so no sudo is needed. Run the subset Mesa CI uses for rusticl,
`opencl_conformance_tests_mesa.csv` (Mesa CI job `deqp-panfrost-g610-opencl-cts-quick.toml`), in wimpy
mode: basic, api, compiler, computeinfo, buffers, images (2D/3D subsets), half, integer_ops quick,
atomics, conversions -w, math_brute_force -w, relationals, commonfns, geometrics, vectors, printf,
select, spirv_new, workgroups. The CTS checks 2.0 features only when the device claims them, so it
measures 3.0/1.2-C correctness. Expected runtime on one G31 core: 2-6 h. Build cache: keep
the CTS build dir under `harness/research/gpu-src/` and rebuild incrementally.

## 4. GLES conformance with no display (needs your approval: external suite)
* **dEQP (VK-GL-CTS)** with the `surfaceless` target, the same configuration Mesa CI uses (`--deqp-surface-type=pbuffer
  --deqp-visibility=hidden --deqp-gl-config-name=rgba8888d24s8ms0`, 256x256). Cross-build
  `deqp-gles2`, `deqp-gles3`, `deqp-gles31` and `glcts` on the host (`-DDEQP_TARGET=surfaceless`;
  sysroot by `dpkg -x` of libegl-dev, libgles-dev, libgbm-dev, libpng-dev, zlib1g-dev arm64). Run
  gles2/3/31-main mustpass plus KHR-GLES31 with deqp-runner (Rust, cross-built) or a shard
  loop, using `--fraction 4` for a first pass. Also run dEQP-GLES31/KHR-GLES32 to record exactly which 3.2
  tests are "NotSupported". Compare against Mesa CI's G52 baseline (0 expected fails).
* **glmark2:** upstream has no surfaceless flavour. Without a display the options are
  `glmark2-es2-wayland` under `weston --backend=headless --renderer=gl` (two Ubuntu packages,
  installed with apt), or a real HDMI sink. Ask before installing.
* What already ran with no display (`gles-func.py`): compute shader → SSBO (64k) PASS, 1080p
  RGBA8 FBO render + readback PASS, glGetError clean. Fill rate: noise shader 111 fps at 1080p (230 Mpix/s),
  flat colour 461 fps (956 Mpix/s, 1.59 pix/clk at 600 MHz); devfreq went up to 600 MHz.

## 5. Recommended plan

0. **GLES 1.0 (new gap):** rebuild the Ubuntu Mesa deb with `-Dgles1=enabled` and add `libgles1` (§2.0).
   This needs a build with root; I have not done it. Plan approval needed.
1. **MP2 row: close as "hardware limit, documented".** Update spec-checklist row 8 to: "G31 single
   core (SHADER_PRESENT=0x1, §1). MP2 is a marketing label; Allwinner's manual says G31".
2. **OpenCL correctness (do now, small image change):** install the mesa-libclc 22.1.8.3
   `spirv64-mesa3d-.spv` over Ubuntu's, using `dpkg-divert` so apt does not undo it. Pin the URL and sha256, and cache the file
   in the Armbian cache dir. Branch prepared (§6). Drop it once Ubuntu packages mesa-libclc or
   patches libclc.
3. **OpenCL row:** run the CTS subset (§3.5, after approval) to prove "OpenCL 3.0 / OpenCL C 1.2
   conformant subset". Record the 2.0 feature table (§3.1) as the gap. OpenCL 2.0 literally requires
   Option B, or long-term rusticl frontend work plus panfrost SVM uAPI.
4. **GLES 3.2 row:** run dEQP (§4, after approval) to prove 3.1. Then decide between A (Mesa GS/TS on
   JM via libpoly, months, upstreamable) and B (Arm kbase + libmali g24p0 as an alternative GPU
   driver variant, weeks, proprietary). B is the only option that meets both 3.2 and CL 2.0 soon.
5. Cosmetic Mesa patch (optional): report the devfreq max clock (600 MHz) instead of the hard-coded 800 in
   `pan_screen.c:655`.
6. Fix the inaccurate comment in `userpatches/config-opiz2-printserver.conf:48` ("panfrost GLES 3.2"),
   which is included in the prepared branch.

## 6. Prepared branch (not merged, not pushed, image not rebuilt)
`/home/aruni/orangepizero2` repo, branch **`feat/gpu-mesa-libclc`** (worktree `wt-gpu`), off `main` 35ea99f:
* `userpatches/config-opiz2-printserver.conf`: new `post_customize_image__opiz2_mesa_libclc`. It fetches
  mesa-libclc `${OPIZ2_MESA_LIBCLC_VER}` = 22.1.8.3 `spirv64-mesa3d-.spv` once into
  `${SRC}/cache/sources/opiz2-mesa-libclc/<ver>/`, verifies the pinned sha256 (the build fails on a mismatch), runs
  `dpkg-divert --rename` on the distro file to `*.distrib`, and installs the fork. It also corrects the
  comment "panfrost GLES 3.2" to "GLES 3.1 + rusticl OpenCL 3.0".
* `.gitignore`: `harness/research/gpu-src/` (the Mesa clone and the downloaded binary).
Validation after the next image build: `cl-probe.py` must show sin/cos PASS and no "Patched Mesa libclc"
warning, and `dpkg-divert --list | grep clc` must show the divert.
