# Mesa fork patches (Mali-G31 panfrost / panvk / rusticl)

Base: Ubuntu `mesa 26.2.4-1ubuntu1` (= Mesa tag mesa-26.2.4). Applied in file-name order after Ubuntu's own
debian/patches (scripts/build-media-debs.sh mesa). All 28 apply with fuzz 0 and no offset on the Ubuntu source.

Source: our fork mesa-work/mesa-cl, branch panfrost-opencl-fixes, `mesa-26.2.4..0e274280595` (= mesa-26.2.4-28,
the last board-validated fork commit: runner jobs 46, 50, 52 ALL PASS). Regenerate with

    git -C mesa-work/mesa-cl format-patch --no-signature --zero-commit -N -o patches/mesa mesa-26.2.4..0e274280595

Commits marked `Generated-by: LLM` are ours (user decision 2026-11-04, feedback-mesa-fork): image-only, never sent
upstream. The others are cherry-picks of upstream Mesa main commits (authors and trailers kept).
The newer Vulkan 1.1 fork commits (ded6ccea0bc..) are not here; they wait for runner job 68.

What the image gets from them (harness/research/opencl-fixes, gpu-invalid-enc, vk-hangs RESULTS.md):
- G31 (Bifrost v7.0) subgroups 4 wide, ballot / read_invocation without WMASK and with the old CLPER form
  (INSTR_INVALID_ENC faults), no shader ending in a BARRIER clause, branch reconvergence at loop exits;
- RGB/24/96-bit image overfetch slack, A8 texel buffers refused (CL_A 1Dbuffer fault), rusticl rect copies;
- upstream NIR / pan fixes needed by the above;
- drm-shim changes (host-only test tool; mesa-drm-shim package).
