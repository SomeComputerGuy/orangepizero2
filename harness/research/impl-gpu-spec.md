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
| (measured) CTS baseline | GLES 2/3: 0 Fail. GLES 3.1: 1 Fail (Mesa CI skips that case too), 1 KHR Fail still open, 2 OOM (board RAM limit). OpenCL: **82 subtest Fails + 2 compiler crashes**. Vulkan: not run yet (runner bug, fixed) | See section 4.1. The OpenCL row above is therefore "3.0 / 1.2 C with known upstream rusticl/Bifrost bugs", not "subset passing". |
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

## 2b. Vulkan 1.1 (H616 datasheet §2.2: "G31 ... Vulkan 1.1")
`mesa-vulkan-drivers 26.2.4-1ubuntu1` and `vulkan-tools 1.4.341.0` were apt-installed on the board for testing
on 2026-11-03 (the image gets them from project commit 005aa71). Dumps:
`harness/analysis/gpu/vulkaninfo-26.2.4.txt` and `vulkaninfo-26.2.4-override1.1.txt`.

| Check | Result |
|---|---|
| Default (no env) | **panvk refuses to load:** `WARNING: panvk is not well-tested on v7, pass PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 if you know what you're doing. (VK_ERROR_INCOMPATIBLE_DRIVER)`. `vkEnumeratePhysicalDevices` fails, so the board has **no usable Vulkan device by default** |
| `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` | `deviceName = Mali-G31 MC1`, `driverName = panvk`, **`apiVersion = 1.0.354`**, `conformanceVersion = 0.0.0.0`, "panvk is not a conformant Vulkan implementation, testing use only" |
| Vulkan 1.1 promoted extensions | **all 18 present** (16bit_storage, bind_memory2, dedicated_allocation, descriptor_update_template, device_group, external_fence/memory/semaphore, get_memory_requirements2, maintenance1-3, multiview, relaxed_block_layout, sampler_ycbcr_conversion, shader_draw_parameters, storage_buffer_storage_class, variable_pointers). The features `multiview`, `variablePointers(StorageBuffer)`, `samplerYcbcrConversion` and `storageBuffer16BitAccess` are all true |
| `MESA_VK_VERSION_OVERRIDE=1.1` | reports `apiVersion = 1.1.354`. This is an override, not a claim the driver makes; see the dEQP-VK subset below |

Why 1.0, from the source:
* `src/panfrost/vulkan/panvk_physical_device.c:405` at 26.2.4 lists `case 6: case 7: case 14:` and refuses to load
  without `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER`. **This is unchanged on main** (2026-11-02, where v11 was added to the list).
* `panvk_vX_physical_device.c get_api_version()` at 26.2.4 returns 1.4 for `PAN_ARCH >= 10` and **1.0 for everything else**.
* Mesa commit **ba09d293e54 "panvk: expose vulkan 1.3 on bifrost"** (Erik Faye-Lund, 2026-07-27, MR !43245:
  "All major features needed for Vulkan 1.3 should already be fixed") changes the fallback to 1.3. It is **in
  mesa-26.3.0-rc3**. `docs/features.txt` at 26.3 lists panvk (not just panvk/v10+) under Vulkan 1.1, 1.2 and 1.3
  "all DONE". The docs table at 26.3 shows Bifrost v7 at Vulkan 1.3, still "experimental" (refuses to load
  without the env var).
* Conformance: Mesa's docs footnote only the **Mali-G610 Vulkan 1.4** submission for panvk (Khronos
  conformant-products #939, 2025-08-18; also #906 1.1 and #913 1.2 on G610). The Khronos Vulkan list has **no
  panvk/Bifrost entry**. **Arm's proprietary driver is conformant on Mali-G31 for Vulkan 1.3**
  (submission #691, 2022-06-29, CTS 1.3.1.x)
  (<https://www.khronos.org/conformance/adopters/conformant-products/vulkan>, fetched 2026-11-03).

What is missing for "Vulkan 1.1" with open drivers: in 26.2.4 only the version gate, and the
experimental load gate on v7. The feature set is present. Mesa 26.3 removes the version gate (it reports 1.3). The load gate
stays, and there is no conformance submission. The dEQP-VK subset below measures how well it actually works.
**dEQP-VK results and the 1.1 blockers (subgroup ops fault the G31 GPU): section 4c.**

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

### 3.5 / 4. Conformance suites: built, staged, run 2026-11-03/04 (results in 4.1)
Approved 2026-11-03. Everything is cross-built on the host (ccache), with pins and sha256s recorded. Nothing has a
complete board result yet. The first attempt was OOM-killed while the AVS2 agent's decoder used about 700 MB, and that
contributed to the 01:15 watchdog reset, so the runners now gate on free memory (see below).

| Item | Pin / source | Location (`harness/research/gpu-src/`, git-ignored) |
|---|---|---|
| VK-GL-CTS | tag `opengl-es-cts-3.2.14.1` = 067e8832315e, plus Mesa CI's GLES backports (Mesa main a1c054214a4 `build-deqp.sh`). 9 of 10 cherry-picked; **e39758bc9262 skipped** (conflicts in the shallow clone; it is a GL4 atomic-counter leak fix, no GLES impact). Also Mesa's 2 CTS patches | `dl-vk-gl-cts-opengl-es-cts-3.2.14.1/` |
| zlib 1.2.13 / libpng 1.6.50 | sha256 b3a24de9... / 71158e53... (pins from deqp `fetch_sources.py`) | `dl-zlib-1.2.13/`, `dl-libpng-1.6.50/` |
| SPIRV-Tools / glslang / SPIRV-Headers / amber / jsoncpp | 65b2ace21293 / 7881226269b1 / babee77020ff / 83c140b6f67f / 9059f5cad030 (deqp pins) | `dl-vkcts-*/` |
| OpenCL-CTS | 43111c0c7c7f (Mesa CI `build-opencl-cts.sh` pin), profile `.gitlab-ci/opencl_conformance_tests_mesa.csv` | `dl-opencl-cts-43111c0c/` |
| CMake 4.3.4 | Ubuntu 26.10 debs (`apt-get download`), sha256 in `debs.sha256` | `dl-cmake-4.3.4/` |
| aarch64 g++ 15.3.0 | the Mesa agent's already-downloaded cross debs (copied, sha256 in `debs.sha256`) | `tools-cross-gxx-15.3.0/` |
| Target libs | libEGL/libGLESv2/libGLdispatch/libOpenCL copied from the board, Mesa 26.2.4 headers | `sysroot-board/` |

Builds: `build-deqp-gles` (surfaceless: deqp-gles2/3/31 + glcts), `build-deqp-vk` (**vulkan_headless**; the surfaceless
target says "Vulkan is not supported"), `build-opencl-cts` (49 binaries, every binary the Mesa profile needs).
Stripped trees with MANIFEST.sha256: `stage-deqp-gles` (251 MB), `stage-opencl-cts` (53 MB), `stage-deqp-vk` (84 MB).

Board setup the suites need (handled by the restage script): `EGL_PLATFORM=surfaceless`, and `LD_LIBRARY_PATH` pointing at
unversioned `libEGL.so`/`libGLESv2.so`/`libvulkan.so` symlinks (dEQP dlopen()s them; the image has no -dev packages).
The fixed libclc is bind-mounted into the unit only. Smoke tests passed before the reset: dEQP-GLES2.info 6/6,
GLES31 compute.basic 41/41, OpenCL basic 3/3. gles2-main got 10 300/17 165 cases, all Pass, before the OOM.

How to run:
* `harness/analysis/gpu/cts-restage.sh [--start]` (host, idempotent). It copies only the trees whose manifests do not verify on the
  board, verifies the libclc and the queue script, makes the symlinks, apt-installs mesa-vulkan-drivers and vulkan-tools if
  missing, runs one sanity case per API and syncs. With `--start` it launches the `cts` unit (MemoryMax=320M,
  OOMScoreAdjust=1000, Restart=on-failure).
* `run-cts-queue.sh` (board) runs gles2/3/31-main, then the Khronos gles2/3/31/32 lists, then the OpenCL-CTS Mesa profile, then the
  dEQP-VK subset (5 227 cases: api/memory/compute/subgroups.basic/multiview/... groups plus 1/2000 of vk-main,
  `stage-deqp-vk/mustpass/vk-subset.txt`, sha256 071d2ebd...). Every step resumes.
* `deqp-run.py` / `clcts-run.py` never start a test process while `avs2dec` runs or MemAvailable < 350 MB. A case the
  OOM killer took is retried, not recorded as Crash. Output goes to `/root/cts/results/<suite>/results.csv` (dEQP:
  test,status,duration,detail; OpenCL: binaries.csv plus per-subtest results.csv). Pull the results into
  `harness/analysis/gpu/cts/` as the regression baseline for the route-A Mesa work.

### 4.1 Results (board image 5cc24a7c8, Mesa 26.2.4, queue finished 2026-11-04 07:08)

Machine-readable baseline: `harness/analysis/gpu/cts/<suite>/` holds `summary.txt`, `nonpass.csv` (every row that is not Pass or NotSupported) and `results.csv.xz` (all cases). OpenCL has `binaries.csv`, `results.csv` and `logs.tar.xz`. The `.qpa` logs stay on the board in `/root/cts/results`.

| Suite | Pass | NotSupported | Other |
|---|---|---|---|
| dEQP gles2-main (17165) | 17049 | 110 | 3 QualityWarning, 3 CompatibilityWarning |
| dEQP gles3-main (44768) | 44619 | 144 | 5 QualityWarning |
| dEQP gles31-main (37802) | 30480 | 7319 | **1 Fail, 2 OOM** |
| KHR gles2-khr-main (473) | 468 | 5 | none |
| KHR gles3-khr-main (6498) | 6268 | 230 | none |
| KHR gles31-khr-main (4101) | 2959 | 1141 | **1 Fail** |
| KHR gles32-khr-main (1405) | none | none | 1405 Missing: glcts creates no ES 3.2 context. This is expected because the driver exposes 3.1 (section 2). |
| OpenCL-CTS Mesa profile (61 binaries) | 3132 subtests passed | | 82 subtests failed, 2 binaries crashed, 3 timed out (below) |
| dEQP-VK subset (5227) | none | none | 5227 Missing: the run never started (below) |

There are 0 Fail in gles2 and gles3. The full Mesa CI GLES mustpass set is therefore clean except for 1 gles31 Fail and 2 gles31 OOM. Triage:

- **`dEQP-GLES31.functional.fbo.no_attachments.maximums.all`, Fail ("Framebuffer did not behave as expected").** Upstream treats it as expected. Mesa CI skips this case on the G52, the same Bifrost v7 family (`src/panfrost/ci/panfrost-g52-skips.txt`: "Huge render, which eventually times out"). It renders at GL_MAX_FRAMEBUFFER_WIDTH/HEIGHT with no attachments. On one core with 1 GB it is a limit of this board, not a bug we introduced. The .qpa on the board shows which sample point differs.
- **`...draw_indirect.compute_interop.large.drawelements_{separate,combined}_grid_1000x1000_drawcount_5000`, OOM.** This is a memory limit of the board, not a leak. Run alone under a 700 MB memcg, the separate case reached 700 MB in 8 s, and Mesa logged `DRM_IOCTL_PANFROST_CREATE_BO failed (err=12)`. The grid needs more GPU (shmem) memory than a 968 MB board can give. The combined case is the twin and still needs a run of its own.
- **`KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence`, Fail ("results differ").** This is open; it may be our setup or a G31/Mesa 26.2 problem. panfrost advertises `GL_KHR_blend_equation_advanced_coherent`. Mesa CI runs gles31-khr-main on the G52 and does not list this case in its fails or flakes files. So it is either specific to the G31 (one core, different tile setup), a regression in 26.2.4, or a flake. Next step: rerun it alone several times and read the .qpa.
- **OpenCL (rusticl on panfrost).** Mesa CI runs the OpenCL-CTS quick profile only on the G610 (Valhall, `panfrost-g610-fails.txt`). No Mesa CI covers Bifrost, so this is the first baseline.
  - The `Basic` enqueue_map_image Fail also appears in the G610 list. The other two Basic Fails (`async_copy_local_to_global` and `async_strided_copy_local_to_global`) are not in that list.
  - **Crashes:** `Relationals` and `Integer Ops` crash with SIGSEGV after "Unhandled ALU op ine" in the Bifrost compiler. The same class of missing lowering is open as mesa#10122 (G31, "Unhandled ALU op ieq"): https://gitlab.freedesktop.org/mesa/mesa/-/work_items/10122. This is a real upstream compiler bug, likely an integer vector or bit-size that bi_emit_alu does not lower.
  - **Math (54 of 106 failed):**
    - Most failures are fp16 ("half") paths, with ULP errors of about 1400 in add, subtract and others.
    - Several fp32 functions return NaN for valid inputs, for example floor(0x1p-27) gives -nan and acos(-0x1p+121) gives nan.
    - Real driver bugs: fp16 arithmetic and fp32 handling of special and denormal inputs on Bifrost. These are not hardware limits; Arm's driver passes the same tests on G31.
  - **Half Ops:** 5 vstore_half rounding variants fail (conversion rounding modes).
  - **Atomics (8 of 13) and C11 Atomics (5 of 32):** global atomic add, sub, min, max, inc, dec, cmpxchg, xor and fetch_* fail. These are wrong results, not crashes, and point to a Bifrost global-atomics bug in the rusticl path.
  - **Thread Dimensions:** 3 of 6 quick_{2d,3d} local-size cases fail.
  - **Images:** Samplerless 1Dbuffer (int, uint, float) and Kernel 2D float 2Darray fail. The `Images (Kernel 3D *)` binaries hit the 5000 s timeout. On one core that is a performance limit; they need a longer timeout or a reduced profile.
  - **Count:** 82 failed subtests in 9 binaries, plus 2 crashes and 3 timeouts. None of these come from the libclc fork; sin and cos compile and run with it.
- **dEQP-VK subset, all Missing.** deqp-vk exited without reporting a single case, and the old runner turned "clean exit, nothing reported" into "done". The likely cause is that the runner passed the GL-only Mesa CI args (`--deqp-surface-type=pbuffer`, `--deqp-gl-config-name`, `--deqp-visibility`, ...) to deqp-vk. Mesa's `deqp-panfrost-g52-vk.toml` passes none, and our sanity run of `api.smoke` without them passed. The output was not kept, so this is not proven. Fixed in `deqp-run.py`: deqp-vk gets only log/watchdog args, and a process that exits before its first case now writes `StartupError` rows plus `shard-N.startup.log`.

**Next board slot (all short, use `cts-restage.sh`; the runner now needs OOMPolicy=continue, MemoryMax=600M):**
1. Restage the new `deqp-run.py`, remove `/root/cts/results/vk-subset`, and start the queue again. Only the VK step runs, about 5227 cases with jobs=1.
2. Run the two OOM cases alone without a memcg cap while watching `/proc/meminfo` Shmem and the panfrost gems, to record their peak. Expected result: still OOM at about 900 MB or more, which stays as a recorded hardware limit.
3. Run `mixedSequence` alone 5 times, and copy its .qpa and the `no_attachments.maximums.all` .qpa to the host.
4. Optionally, rerun `Images (Kernel 3D *)` with `--timeout 20000`, and capture the `ine` shader with `BIFROST_MESA_DEBUG=shaders` for an upstream report.

### 4b. Rerun on image 8546e5fc1, server variant (2026-11-04/05, `harness/analysis/gpu/cts-8546e5fc1-server/`)

Full queue via `gpu-rerun.sh` (561 min), then the extras unit (MemoryMax=800M).

- **GLES:** identical to the first baseline. gles2 0 Fail, gles3 0 Fail, gles31-main 1 Fail
  (`fbo.no_attachments.maximums.all`, expected upstream) + 2 OOM, gles31-khr 1 Fail (`mixedSequence`), gles32-khr
  1405 StartupError (no ES 3.2 context, expected).
- **OOM cases run alone under an 800 MB memcg: both Pass.** They only OOM when the whole queue shares the board's
  memory, so they are not a driver bug; record as "run alone on 1 GB boards".
- **`KHR-GLES31.core.blend_equation_advanced.test_coherency.mixedSequence`: Fail 5/5 alone.** Deterministic, so a real
  panfrost/G31 blend_equation_advanced_coherent bug, not flakiness. Goes into the OpenCL/compiler work item
  (status.md item 3) as a GLES bug to fix or to stop advertising coherency.
- **OpenCL (rusticl):** 3136 subtests passed, 78 failed (was 3132 / 82). Binaries: 44 Pass, 11 Fail, 2 Crash
  (Relationals, Integer Ops: "Unhandled ALU op ine"), 3 Timeout (Images Kernel 3D int/uint/float at 5000 s).
  Failing subtests: Math 50 (was 54), Atomics 8, Half Ops 5, C11 Atomics 5, Basic 3, Thread Dimensions 3, API 1,
  Images Kernel 2D float 1, Samplerless int/uint/float 1 each. Same classes as section 4; this is the baseline for
  the OpenCL fixes.
- **dEQP-VK subset:** 5227 StartupError ("Vulkan is not supported", status.md item 5).

### 4c. dEQP-VK fixed and run (2026-11-05, board kernel 7.3.1-edge-sunxi64, Mesa 26.2.4, `harness/analysis/gpu/cts-vk-1.4.6.2/`)

**What was wrong:** the build source, not the target or the driver. The old `deqp-vk` came from the **GLES** release tag
`opengl-es-cts-3.2.14.1`. In the GL/GLES release branches, `framework/platform/lnx/tcuLnxPlatform.cpp` has no
`getVulkanPlatform()` (no `tcuLnxVulkanPlatform` member, even though the file sits in the tree). So the base-class
default in `tcuPlatform.cpp:54` throws "Vulkan is not supported" before libvulkan is ever loaded, whatever `DEQP_TARGET` says.
Mesa CI builds deqp-vk from a **Vulkan** release (`build-deqp.sh`: `DEQP_VK_VERSION=1.4.6.2`).

**Fix** (`harness/analysis/gpu/build-deqp-vk.sh`, host, idempotent, ccache):
* VK-GL-CTS `vulkan-cts-1.4.6.2` (f6a2970) plus Mesa CI's 4 `vk_cts_commits_to_backport` (all apply cleanly; patch sha256s
  in `dl-vulkan-cts-1.4.6.2/patches/`). External pins come from that tag's `fetch_sources.py`: SPIRV-Tools 2d14d2e76aa7,
  glslang 715c8500e7cd, SPIRV-Headers 6dd7ba990830, amber 53a4c8934bf7, jsoncpp 9059f5cad030, renderdoc header
  (sha256 checked). zlib and libpng are the same pins as the GLES tree.
* `DEQP_TARGET=vulkan_headless`. This is the Linux platform with `VK_EXT_headless_surface`; there is no X11 or Wayland on the board, and it
  is the right target once the source is right. Video tests are off. Same cross toolchain as the GLES build. `TMPDIR` is on disk, because
  /tmp is a shared tmpfs that filled up during the first try.
* Staged tree: stripped `deqp-vk` (69 MB) + `vulkan/` data + `mustpass/vk-subset.txt` (the old 5227-case subset restricted to
  names that exist in 1.4.6.2: **5225**) + `mustpass/vk-main-1in100.txt` (every 100th line of the 1.4.6.2 vk-main:
  **32476** cases). The full vk-main (3 247 552 cases, 416 MB) stays on the host (`gpu-src/vk-mustpass-1.4.6.2/`).
* Board env = Mesa CI `panfrost-g52-vk`: `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1
  PANVK_DEBUG=sync`, plus `VK_DRIVER_FILES`/`VK_ICD_FILENAMES` = panfrost_icd.json. `run-vk-subset.sh [OUT [CASELIST]]`
  runs one list under a 600 MB memcg. `cts-restage.sh` stages it; its `api.smoke` sanity now gives **6/6 Pass**.
* **`deqp-run.py` bugs found and fixed:** (1) dEQP runs a caselist in test-tree order, not file order. Resuming by
  list position after a clean exit therefore re-ran cases (11 553 rows for 5225 cases in the first try). The runner now tracks the set of reported cases,
  and on a clean exit marks the unreported ones `NotFound`. Earlier GLES results were deduplicated by name, so their numbers stand, but
  a Crash or Timeout there may have skipped unrelated cases. (2) Every SIGKILL was recorded as `OOM`. Now it is OOM only if the
  cgroup's `memory.events oom_kill` went up; otherwise it is Crash. The runs below used the old runner: their "OOM" rows are **GPU
  faults or hangs, not OOM** (0 oom-kills in the kernel log), so they are counted as Crash below.

**Results** (jobs=1, PANVK_DEBUG=sync; Crash = SIGKILL after a GPU fault or hang):

| Run | Cases | Pass | NotSupported | Fail | Crash | Time |
|---|---|---|---|---|---|---|
| vk-subset, as shipped (API 1.0) | 5225 | **3332** | 1888 | 5 | 0 | 79 s |
| vk-main 1/100, API 1.0 | 32476 | **6345** | 26121 | 3 | 7 | 447 s |
| vk-subset, `MESA_VK_VERSION_OVERRIDE=1.1` | 5225 | 3360 | 1847 | 2 | 16 | 159 s |
| vk-main 1/100, override 1.1 | 32476 | 6457 | 25987 | 3 | 29 | 522 s |
| vk-subset, override 1.3 (what Mesa 26.3 reports) | 5225 | 3390 | 1808 | 2 | 25 | 212 s |
| vk-main 1/100, override 1.3 | 32476 | 6573 | 25827 | 3 | 73 | 818 s |

At API 1.0, 99.8 % of the cases that run pass (6345 of 6355 in the 1/100 sample). The top NotSupported reasons are
extensions or features panvk v7 does not expose: shader_object, fragment_shading_rate, primitives_generated_query, the exclusive
compute queue, D16_S8, ray tracing, geometry/tessellation and sparse. In the 1/100 sample, 1787 cases are gated only on "Vulkan 1.1 not supported" or
"Subgroup operations are not supported". The override opens them up.

**Triage** (`vk-triage.py`; it matches against Mesa main `src/panfrost/ci/panfrost-g52-{fails,flakes,skips}.txt`, `panvk-{skips,flakes}.txt`):
* *Test setup, now fixed:* the old wrong build (5227 StartupError), the runner re-run bug and the OOM mislabel. The 2 subset names that
  are missing in 1.4.6.2 were renamed upstream, not dropped by us.
* *Known upstream, same as the G52:* `api.device_init.create_device_global_priority{,_khr}.basic` (g52-fails). The
  `..._global_priority_query{,_khr}.basic` twins fail the same way (`vkCreateDevice` → `VK_ERROR_EXTENSION_NOT_PRESENT` with
  a global-priority struct) and are the same bug. 3 `glsl.texture_functions.*offset.mirrored_repeat.*` image mismatches are
  in `panvk-skips.txt` (Mesa does not even run them).
* *API 1.0 only:* `create_device_unsupported_features.protected_memory_features` (device creation with the 1.1 struct
  `protectedMemory=TRUE` does not return `VK_ERROR_FEATURE_NOT_PRESENT`). It passes at 1.1 and 1.3, so it is a 1.0 + 1.1-struct corner, not a 1.1 blocker.
* **Real driver bugs, G31-specific (not in any Mesa G52 list)** (updated 2026-11-05 by the vk-hangs agent, details and
  host repro in `harness/research/vk-hangs/RESULTS.md`; board verification = runner job 14-vk-hangs):
  - `spirv_assembly.type.vec4.{i8,i16,u16,u32,i64,u64}.*_frag` (7 in the sample, already at API 1.0): **long jobs, not
    hangs.** Replayed on the host with a native deqp-vk on the fork panvk under the drm-shim: the CTS fragment shader loops
    over the whole dataset in every one of the 65536 fragments (8210 iterations for `i8.clamp`, 5120 for
    `u32.bit_field_insert`, 15-19 clauses with 3 SSBO loads + 1 store each; the passing vec4 cases have <= 2560). On the
    stock kernel the 500 ms job watchdog resets the GPU (`gpu sched timeout, js=0`) and panvk's sync check aborts. The
    kernel patch e544ddb00 (soft-stop and resume a still-ACTIVE job, in the cumulative kernel) is the fix; no Mesa change.
  - **Subgroup operations** (all only reachable with the 1.1+ override): `subgroups.basic.*` (elect, barrier, memory barriers; compute,
    graphics and fragment), `subgroups.{arithmetic,clustered,quad,shuffle,ballot_broadcast}.*`, the
    `memory_model.*.subgroup.*` scope cases and `glsl.derivate.dfdx*{subgroup,dynamic_*}`. The kernel logs `js fault ...
    status=INSTR_INVALID_ENC` on js=0 (fragment) and js=1 (compute/vertex): 261 faults + 28 hangs over the override runs.
    Two compiler bugs, both G31 (v7.0) specific, both in the fork `panfrost-opencl-fixes` (`mesa-work/mesa-cl`):
    1. `pan_subgroup_size()` gave every v7 GPU 8-wide subgroups; the G31 is 4-wide. Fixed by 55fb9c9c4d3 (OpenCL agent):
       `WMASK.subgroup8`/`CLPER` 8-lane forms and wrong subgroup ids are gone, and so is INSTR_INVALID_ENC.
    2. `nir_intrinsic_read_invocation` (subgroupBroadcast, and every shuffle/quad/rotate/read_first_invocation that
       nir_lower_subgroups turns into it) emitted the full `CLPER.i32` encoding, which G71/G72/G31 (`BIFROST_LIMITED_CLPER`)
       do not decode; only the derivative path used `bi_clper()`'s `CLPER_OLD`. Fixed by b7a705442bd: `CLPER_OLD.i32` on
       those GPUs (host dump: 512 CLPER_OLD, 0 CLPER.i32 for `ballot_broadcast.compute.subgroupbroadcast_int8_t`).
       Mesa main has the same bug (nobody runs Vulkan on v7.0).
    Still open: with 55fb9c9c4d3 `dEQP-VK.subgroups.basic.compute.subgroupelect` still ends with "Incomplete job or
    timeout" and no INSTR_INVALID_ENC. Its shader is loop-free: `WMASK.subgroup4` (ballot) -> find_lsb == `lane_id`, WLS
    atomics, 16 workgroups of 1 thread first; the compute job descriptors match gallium's. So it is either another fault
    status or a stall in `WMASK` on v7.0, which only the board can tell: runner job 14 runs 8 probe shaders (plain store,
    ballot only, elect, WLS atomics only, subgroup ids, broadcast, any/all, the CTS elect shader) x 3 local sizes with
    `PANVK_DEBUG=sync,trace` and records each job's exception status and dmesg, then the dEQP cases, then vk-subset +
    OpenCL + GLES regression of the fork. `builtin_var.compute.subgroupsize_compute` passes (it only compares
    gl_SubgroupSize with the property).
    Host tooling for this (no GPU): fork panvk on the panfrost drm-shim as a fake G31, a minimal Vulkan compute runner
    `vkcomp`, native deqp-vk and glslang (`harness/research/vk-hangs/`, `harness/analysis/gpu/build-deqp-vk-host.sh`).

**What Vulkan 1.1 (datasheet row) would take from here:**
1. *Version gate:* 26.2.4 returns 1.0 for v7. Mesa 26.3 (ba09d293e54) returns 1.3. For our image, either backport that one-line
   change to an image Mesa build, or wait for an Ubuntu 26.3 package.
2. *Load gate:* v7 still needs `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1` on main. The image would have to set it system-wide, or patch it out
   in our Mesa build. That is an explicit "experimental driver" decision for the user.
3. *Make the 1.1 core subgroup ops work on the G31:* subgroup BASIC in compute is required in 1.1. Two of the three
   G31 compiler problems are fixed in the fork (4-wide subgroups, CLPER_OLD for broadcasts); whether `WMASK` (ballot,
   elect, any/all) works on v7.0 is decided by runner job 14 (`harness/research/vk-hangs/RESULTS.md`). The 7 small-int
   fragment "hangs" are long jobs that need the kernel soft-stop fix, not a Mesa change.
4. *Then* run the full 3.25 M-case vk-main at 1.1. Scaling the 1/100 timings gives roughly 14 h at 1.1 and about 23 h at 1.3, in board slots
   (resumable). Classify against the G52 lists. "Vulkan 1.1 conformant" in the Khronos sense also needs a submission (none
   exists for panvk on Bifrost), so this project can reach "Vulkan 1.1 functional, CTS-tested", not "conformant".

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

## 6. libclc branch: merged into main as 8cb2037 (pushed by the coordinator), build-time download approved
`/home/aruni/orangepizero2` repo, branch **`feat/gpu-mesa-libclc`** (worktree `wt-gpu`), off `main` 35ea99f:
* `userpatches/config-opiz2-printserver.conf`: new `post_customize_image__opiz2_mesa_libclc`. It fetches
  mesa-libclc `${OPIZ2_MESA_LIBCLC_VER}` = 22.1.8.3 `spirv64-mesa3d-.spv` once into
  `${SRC}/cache/sources/opiz2-mesa-libclc/<ver>/`, verifies the pinned sha256 (the build fails on a mismatch), runs
  `dpkg-divert --rename` on the distro file to `*.distrib`, and installs the fork. It also corrects the
  comment "panfrost GLES 3.2" to "GLES 3.1 + rusticl OpenCL 3.0".
* `.gitignore`: `harness/research/gpu-src/` (the Mesa clone and the downloaded binary).
Validation after the next image build: `cl-probe.py` must show sin/cos PASS and no "Patched Mesa libclc"
warning, and `dpkg-divert --list | grep clc` must show the divert.
