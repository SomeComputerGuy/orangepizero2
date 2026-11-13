# Mesa patches (Mali-G31 panfrost / panvk / rusticl)

Base: upstream Mesa 26.3.0 (release tarball, tag mesa-26.3.0) built with the packaging (debian/) of Ubuntu
`mesa 26.2.4-1ubuntu1`, adapted by debian/0001 (Ubuntu has no 26.3 package yet). `scripts/build-media-debs.sh mesa`
unpacks the 26.3.0 tarball and venus-protocol 1.1.3 (now an external dependency of the Venus driver; Ubuntu does
not package it) into subprojects/, takes Ubuntu's debian/ directory, applies debian/*.patch, then appends these
patches after Ubuntu's own debian/patches. Package version 26.3.0-0ubuntu1+opiz2.1. All apply with fuzz 0.

Source: github.com/SomeComputerGuy/mesa, branch opiz2-26.3, `mesa-26.3.0..opiz2-26.3`. Regenerate with

    git format-patch --no-signature --zero-commit -N -o patches/mesa mesa-26.3.0..opiz2-26.3

then bump REV[mesa] in scripts/build-media-debs.sh (the debian/changelog entry is generated from the patch subjects).

All patches are ours (`Generated-by: LLM`), not sent upstream. The 26 upstream cherry-picks of the 26.2.4 series
(Bifrost/NIR fixes, the Vulkan 1.1 gate, the Vulkan 1.3 on Bifrost series and five panvk stable fixes) are part of
Mesa 26.3.0 and were dropped, as was the revert pair 0024/0026 of the old series (net zero).

What the image gets:
- G31 (Bifrost v7.0): 4-wide subgroups, ballot / read_invocation without WMASK and with the old CLPER form,
  no shader ending in a BARRIER clause, SEG_ADD.i64 register interference (OpenCL __local atomics);
- RGB/24/96-bit image overfetch slack, A8 texel buffers refused, rusticl rect copies, lower_cl_images buffer
  textures;
- drm-shim changes (host-only test tool; mesa-drm-shim package);
- 0013-0020: panvk on Bifrost: ARM core builtins safe with the real warp count, the JM command-buffer descriptor
  pool allocated on first use, ATOM_CX staging reads counted like ATOM_RETURN, overfetch slack for explicit
  24/96-bit layouts, textureQueryLod level from the sampler, explicit_pad_B always set, texture coordinates
  rounded to zero when minifying with nearest (as the Arm driver).
- Vulkan 1.3 on Bifrost comes from Mesa 26.3.0 itself. panvk on v7 still needs PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1
  (set system-wide by the image config).
