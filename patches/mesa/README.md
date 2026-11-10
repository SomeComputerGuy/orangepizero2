# Mesa patches (Mali-G31 panfrost / panvk / rusticl)

Base: Ubuntu `mesa 26.2.4-1ubuntu1` (Mesa tag mesa-26.2.4). Applied in file-name order after Ubuntu's own
debian/patches by `scripts/build-media-debs.sh mesa`; package version 26.2.4-1ubuntu1+opiz2.3. All apply with fuzz 0.

Source: github.com/SomeComputerGuy/mesa, branch panfrost-opencl-fixes, `mesa-26.2.4..45350a1f1fc`. Regenerate with

    git format-patch --no-signature --zero-commit -N -o patches/mesa mesa-26.2.4..45350a1f1fc

then bump REV[mesa] in scripts/build-media-debs.sh (the debian/changelog entry is generated from the patch subjects).

Commits marked `Generated-by: LLM` are ours and not sent upstream. The others are cherry-picks of upstream Mesa
main commits (authors and trailers kept); 0029 is the upstream Vulkan 1.1 gate (Mesa 0dbf521d381, MR 41981); 0037-0040 are the upstream
Vulkan 1.3 on Bifrost series (7e6f47400db, 4e2e284654f, 7d163be5ade, ba09d293e54) and 0041-0045 upstream panvk
stable fixes, backported with a note.

What the image gets:
- G31 (Bifrost v7.0): 4-wide subgroups, ballot / read_invocation without WMASK and with the old CLPER form,
  no shader ending in a BARRIER clause, branch reconvergence at loop exits;
- RGB/24/96-bit image overfetch slack, A8 texel buffers refused, rusticl rect copies;
- upstream NIR / pan fixes needed by the above;
- drm-shim changes (host-only test tool; mesa-drm-shim package);
- 0029-0036: panvk reports Vulkan 1.1 on Bifrost (subgroups), ARM core builtins safe on Bifrost with the real
  warp count, the JM command-buffer descriptor pool allocated on first use, ATOM_CX staging reads counted like
  ATOM_RETURN, overfetch slack for explicit 24/96-bit panvk layouts, textureQueryLod level from the sampler,
  explicit_pad_B always set.
- 0037-0045: panvk reports Vulkan 1.3 on Bifrost (VK_KHR_maintenance6, VK_KHR_spirv_1_4, null index buffers on
  JM) plus five upstream panvk fixes (depth/stencil aspectMask, image view descriptors, JM tiler pointer, heap budget
  across instances, GetInstanceProcAddr NULL). Board conformance run pending (not yet proven on the hardware).
  panvk on v7 still needs PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 (set system-wide by the image config).
