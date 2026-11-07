# Build warnings (build-all.sh, 2026-11-07) — RESULTS

State: DONE (code + build checks). Branch `fix/build-warnings` (armbian-build, worktree `wt-build-warnings`, from
stonking-orangepizero2 9ba317178), pushed to `fork`. HEAD e79177038. Not merged; coordinator merges after the
user's build. userpatches change: `userpatches-build-warnings.patch` here (apply from the project root with
`git apply`, then commit in the project repo).

Logs scanned: minimal build dc22cfd0 (output/logs/log-build-dc22cfd0-*.log), previous desktop build 947acd6e,
server build d0ac198c (running at the time, rootfs stage done).

## 1. Kernel (xradio -Wempty-body, -Wmissing-prototypes, rtl8189es -Wunused-function)
- Cause: the upstream merge 9ba317178 took upstream's `lib/functions/compilation/patch/drivers_network.sh` and
  dropped the two `process_patch_file` lines of 7ee689650. The fix patches
  (patch/misc/xradio-fix-empty-body-and-missing-prototypes.patch, wireless-rtl8189es-guard-wireless-stats-wext.patch)
  stayed in the tree but were no longer applied. Nothing else of ours was lost in that merge (checked every file our
  side changed under lib/ config/ extensions/ packages/ patch/).
- Fix: 052c4144d re-adds both lines (both patches still apply to the bumped driver commits).
- Why the check said 0: kernel-check/build-kernel.sh injected only uwe5622, used the bare
  linux-sunxi64-edge.config (no armbian_kernel_config hooks: BTF, nftables, CFG80211_WEXT ...), KVER 7.3.1 (image:
  7.3.3), only series.conf, and incremental builds only re-warn for rebuilt files.
  Now (project repo): new kernel-check/armbian-prep.sh runs Armbian's own driver harness (drivers_network.sh, the
  driver list parsed from drivers-harness.sh, all 21 drivers, private source cache in $WORK/dl) and all 16
  armbian_kernel_config__* hooks; build-kernel.sh uses it, applies the top-level patches of the patch dir too,
  defaults KVER=7.3.3, uses the real make flags, CLEAN=1 = full warning scan, counts modpost and dtc warnings of
  both logs. Verified: harness output == the real build's cached drivers patch (diff -r: only our two fixes);
  final .config == the real build's .config (identical); 881 patches applied like the real build.
  NOTE: the default KVER moves to 7.3.3, so the next cumul build (work-cumul, 7.3.1) does one large rebuild.
- Full kernel log scan (real build was incremental: 25 C + 17 dtc warnings). Full clean check build:
  `ARMBIAN=wt-build-warnings WORK=kernel-check/work CLEAN=1 kernel-check/build-kernel.sh`
  (log kernel-check/run-build-warnings-all.log): patches 881/0 failed, **C warnings 0, modpost 0, dtc 0**.

## 2. U-Boot rsa-sign.c ENGINE deprecation (OpenSSL 4.0.3 on the host)
- Upstream master still calls ENGINE unconditionally; the "Add support for OpenSSL Provider API" series (v4,
  lists.denx.de 2026-04/06) is not merged and has open review issues (-N pkcs11 regression). No backport.
- Fix: ef580e639 adds patch/u-boot/v2026.10-sunxi64/lib-rsa-skip-engine-code-without-openssl-engine-support.patch:
  ENGINE code only without OPENSSL_NO_ENGINE (OpenSSL 4 defines it); `-N engine` then says the engine isn't
  available. PEM signing unchanged (mkimage signed a sha256,rsa2048 FIT).
- Check: kernel-check/build-uboot.sh, WORK=kernel-check/work-uboot-bw: 30 patches, 0 failed, **0 warnings**; TF-A 0.
  TF-A and the rest of U-Boot had no other warnings in the real logs.

## 3. dtc (status item 18)
- 250cc9976: pine64-7inch-lcd.dtso: #address-cells/#size-cells <1>/<0> in the i2c0 and dsi fragments;
  new patches.armbian/arm64-dts-sun50i-h5-nanopi-r1s-h5-add-ehci1-address-cells.patch (series.conf after the
  rtl8153 patch). 17 -> 0. Only sunxi-7.3 changed (sunxi-6.18/6.12 carry identical copies; not build-checked, left).

## 4. Build-script WARNINGs
- DESKTOP_APPGROUPS_SELECTED legacy: ours. userpatches patch: DESKTOP_TIER=full (same tier the legacy mapping chose,
  so the rootfs cache key is unchanged); DESKTOP_ENVIRONMENT_CONFIG_NAME (also removed upstream) dropped.
- SDCARD /var/cache/apt + /var/lib/apt/lists not empty (desktop only, 4 warnings): not our hooks; Armbian's
  rootfs-create.sh ran armbian-config module_desktops with plain chroot_sdcard (no shared apt cache mounted), so the
  GNOME .debs (808 files) and lists landed in the rootfs. ed3655d52 runs it via chroot_sdcard_custom_with_apt_logic.
  The rootfs cache key does not hash lib/, so it shows only when the desktop rootfs cache is next rebuilt.
- ORAS manifest fetch error "denied": ghcr.io answers "denied" for a repository that does not exist (rootfs of
  stonking/desktop never published by Armbian CI) and "not found" for a missing tag (checked with oras 1.3.6).
  ef77bac1a treats "denied" as an info-level cache miss; other errors still warn.
- "Package not in json, trying distro Packages index [stonking/arm64]": Armbian-side, left. github.armbian.com's
  base-files.json has no stonking (stonking is our local release); the fallback it announces works
  (base-files_14.2ubuntu2). Goes away when Armbian adds stonking; not a config issue, and hiding it in lib would
  hide a real miss.
- New in this build: "Rootfs post-tweaks size is larger than estimated tmpfs size" (minimal 2418 > 2300, server
  3013 > 2300 MiB). Ours (package set). e79177038 adds ROOTFS_TMPFS_ESTIMATED_SIZE_MIB (defaults unchanged); the
  userpatches patch sets 3500 for minimal/server (desktop keeps 6000).

## 5. Distro package noise (none ours; not patched)
- hplip SyntaxWarnings ('return' in 'finally', PEP 765, Python 3.14): upstream HPLIP/Ubuntu bug at byte-compile;
  harmless (behaviour unchanged). Not trivial to patch safely (14 sites, distro package).
- gtweak gtksettings.py:30 SyntaxWarning: same PEP 765 class, gnome-tweaks/Ubuntu bug, desktop only, harmless.
- chrony dpkg-statoverride /var/log/chrony: Ubuntu packaging bug: chrony 4.8-4ubuntu2 no longer ships the dir
  (chrony.service LogsDirectory= creates it) but postinst still runs statoverride --update. Harmless.
- ca-certificates "rehash: skipping ca-certificates.crt": harmless, bundle file in /etc/ssl/certs; normal.
- update-rc.d "start and stop actions are no longer supported" (fake-hwclock, plymouth): Debian maintainer scripts
  pass legacy runlevel args; harmless.
- "Fake start-stop-daemon called": Armbian diverts start-stop-daemon in the chroot on purpose; harmless.
- NetworkManager "could not reload connections": NM postinst runs nmcli in a chroot without a daemon; harmless.

## Open
- Coordinator: merge fix/build-warnings, apply userpatches-build-warnings.patch, then a build should show only
  the "Package not in json" WARNING plus the distro noise above.
- sunxi-6.18/6.12 copies of the two DT files still warn (other kernels; not ours to build-check).
