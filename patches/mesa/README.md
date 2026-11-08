# Mesa patches (Mali-G31 panfrost / panvk / rusticl)

Base: Ubuntu `mesa 26.2.4-1ubuntu1` (Mesa tag mesa-26.2.4). Applied in file-name order after Ubuntu's own
debian/patches by `scripts/build-media-debs.sh mesa`; package version 26.2.4-1ubuntu1+opiz2.2. All apply with fuzz 0.

Source: github.com/SomeComputerGuy/mesa, branch panfrost-opencl-fixes, `mesa-26.2.4..26cb3c93a58`. Regenerate with

    git format-patch --no-signature --zero-commit -N -o patches/mesa mesa-26.2.4..26cb3c93a58

then bump REV[mesa] in scripts/build-media-debs.sh (the debian/changelog entry is generated from the patch subjects).

Commits marked `Generated-by: LLM` are ours and not sent upstream. The others are cherry-picks of upstream Mesa
main commits (authors and trailers kept); 0029 is the upstream Vulkan 1.1 gate (Mesa 0dbf521d381, MR 41981).

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
  panvk on v7 still needs PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 (set system-wide by the image config).
