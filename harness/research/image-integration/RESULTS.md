# Image integration 2026-11-07 (state file)

State: DONE on the host; board check = runner job 69-image-check (harness/runner-queue/69-image-check.md), after the
user's `./build-all.sh OPIZ2_WIFI_REGDOM=US`. Then job 68 resumes. Summary of the work: docs/status.md section 3 B.

- armbian-build: merge/upstream-2026-11-06 = 9ba317178 (armbian/build main into 452cdd53f; stonking-orangepizero2
  fast-forwarded to it, both pushed to fork). Kernel check KVER=7.3.3: 879 patches / 0 failed, 0 C warnings, dtbs 0,
  17 dtc warnings (all pre-existing pine64-7inch-lcd + nanopi-r1s-h5), 61 h616 overlays.
- out/debs-media (56 debs, all emulated arm64 builds): ffmpeg 7:8.1.2-2ubuntu2+opiz2.5 (21), mpv 0.41.0-2ubuntu5+opiz2.1
  (3), gst-plugins-bad1.0 1.28.6-1ubuntu1+opiz2.1 (11), gst-plugins-good1.0 1.28.7-1build1+opiz2.1 (5),
  mesa 26.2.4-1ubuntu1+opiz2.1 (16 = patches/mesa, fork 0e274280595).
- Mesa vs the archive's arm64 mesa 26.2.4-1ubuntu1 (scripts/compare-mesa-debs.sh, results in mesa-compare/):
  1 package set 16/16, Version/Depends/Provides/Breaks/Replaces/... identical after removing "+opiz2.1";
  2 file lists identical except 7 doc changelog.Debian.gz: symlinks in the archive (Launchpad's pkgbinarymangler links
    identical changelogs), regular files in ours; the libgallium-<version>.so name carries our version;
  3 exported dynamic symbols identical in all 35 shared objects (libgallium: same 107 symbols, version tag
    libgallium-26.2.4-1ubuntu1+opiz2.1.so);
  4 driver set: the same DRI/VA/VDPAU/Vulkan ICD files as the archive (file lists); the per-build meson log is not
    kept by build-media-debs.sh, so no meson-summary diff;
  5 all 35 ELF files are ARM aarch64.
- Mesa cross build (user request 2026-11-07): blocked by packaging, not attempted further. With Ubuntu's control
  annotated :native (patch in mesa-cross-build-attempt.patch), apt still cannot install llvm-22-dev:arm64:
  llvm-22-tools:arm64 Depends python3-yaml:arm64, which Conflicts with the native python3-yaml the build tools need.
  Mesa therefore stays on the emulated build. The attempt (cross recipe + meson cross file with the Rust target and
  llvm-config) is kept in mesa-cross-build-attempt.patch for a later try (needs a co-installable LLVM -dev set).
- Open: GNOME desktop render with PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 (needs a display); older runner packages'
  own restore() functions still name vmlinuz-7.3.1-edge-sunxi64 (only if one is rerun).
