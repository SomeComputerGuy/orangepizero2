# Mesa fork patches (Mali-G31 panfrost / panvk / rusticl)

Base: Ubuntu `mesa 26.2.4-1ubuntu1` (= Mesa tag mesa-26.2.4). Applied in file-name order after Ubuntu's own
debian/patches (scripts/build-media-debs.sh mesa, package version 26.2.4-1ubuntu1+opiz2.2). All 36 apply with
fuzz 0 and no offset on the Ubuntu source (checked 2026-11-07: dpkg-source -x, then `patch -p1 -F0` in order).

Source: our fork mesa-work/mesa-cl, branch panfrost-opencl-fixes (github.com/SomeComputerGuy/mesa),
`mesa-26.2.4..26cb3c93a58` (= mesa-26.2.4-36, the last board-validated fork commit: runner jobs 46, 50, 52 for
0001-0028; Vulkan 1.1 jobs 68, 70, 71, job 71 ALL PASS with 0 regressions vs job 68 and vs the system Mesa 26.2.4 /
job 52 baselines). Regenerate with

    git -C mesa-work/mesa-cl format-patch --no-signature --zero-commit -N -o patches/mesa mesa-26.2.4..26cb3c93a58

then bump REV[mesa] in scripts/build-media-debs.sh (the debian/changelog entry is generated from the patch subjects).

Commits marked `Generated-by: LLM` are ours (user decision 2026-11-04, feedback-mesa-fork): image-only, never sent
upstream. The others are cherry-picks of upstream Mesa main commits (authors and trailers kept); 0029 is the
upstream Vulkan 1.1 gate (Mesa 0dbf521d381, MR 41981) backported, so it carries both.

What the image gets from them (harness/research/opencl-fixes, gpu-invalid-enc, vk-hangs, vk11 RESULTS.md):
- G31 (Bifrost v7.0) subgroups 4 wide, ballot / read_invocation without WMASK and with the old CLPER form
  (INSTR_INVALID_ENC faults), no shader ending in a BARRIER clause, branch reconvergence at loop exits;
- RGB/24/96-bit image overfetch slack, A8 texel buffers refused (CL_A 1Dbuffer fault), rusticl rect copies;
- upstream NIR / pan fixes needed by the above;
- drm-shim changes (host-only test tool; mesa-drm-shim package);
- 0029-0036 (+opiz2.2): panvk reports Vulkan 1.1 on Bifrost by default (subgroups), ARM core builtins safe on
  Bifrost with the real warp count, the JM command-buffer descriptor pool allocated on first use (OOM), ATOM_CX
  staging reads counted like ATOM_RETURN (image_robustness INSTR_INVALID_ENC), overfetch slack for explicit
  24/96-bit panvk layouts, textureQueryLod level from the sampler, explicit_pad_B always set (memory requirements).
  panvk on v7 still needs PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 (set system-wide by the image config).
