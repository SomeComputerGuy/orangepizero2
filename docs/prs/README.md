# Armbian PR drafts (2026-11-02)

Drafts only; nothing is opened. Every branch below is on the fork (SomeComputerGuy/build), rebased onto
armbian/build `main` c2908d2, sunxi-7.3 series 0 failed, U-Boot/TF-A series 0 failed.
Integration of all of them: `stonking-orangepizero2-rebased` (556b18714).

## Ready (suggested order)

| # | Draft | Branch | Depends on |
|---|---|---|---|
| 1 | group-ubuntu-stonking.md | pr/group/ubuntu-stonking | - |
| 2 | fix-uboot-sunxi64-host-tools-openssl4.md | pr/fix/uboot-sunxi64-host-tools-openssl4 | - |
| 3 | fix-sunxi-dwmac-sun8i-upstream-reset.md | pr/fix/sunxi-dwmac-sun8i-upstream-reset | - |
| 4 | fix-sunxi-cedrus-h616-upstream.md | pr/fix/sunxi-cedrus-h616-upstream | - |
| 5 | fix-sunxi-pm-s2idle-dpm-backports.md | pr/fix/sunxi-pm-s2idle-dpm-backports | - |
| 6 | group-sunxi-h616-thermal-gpu.md | pr/group/sunxi-h616-thermal-gpu | - |
| 7 | group-orangepi-zero2-dt.md | pr/group/orangepi-zero2-dt | - (Ethernet retest first, see draft) |
| 8 | fix-sunxi-h616-pwm-uart0-pins.md | pr/fix/sunxi-h616-pwm-uart0-pins | - |
| 9 | fix-sunxi-drm-blend-mode.md | pr/fix/sunxi-drm-blend-mode | - |
| 10 | fix-bsp-systemd-boot-warnings.md | pr/fix/bsp-systemd-boot-warnings | - |
| 11 | group-uboot-orangepizero2.md | pr/group/uboot-orangepizero2 | - |
| 12 | group-atf-h616-suspend.md | pr/group/atf-h616-suspend | - |
| 13 | group-uwe5622.md | pr/group/uwe5622 | - |
| 14 | group-uwe5622-bt-no-blob.md | pr/group/uwe5622-bt-no-blob | 13 |

Groups are cherry-picks of the single-topic `pr/<branch>` branches (same file contents as the rebased
integration, except where a later branch in the integration changes the same file).

## Not ready

| Branch | Why |
|---|---|
| pr/feat/sunxi-h616-vdec-spec | Draft written (feat-sunxi-h616-vdec-spec.md), but it carries Jernej Skrabec's unposted work (ask him first), 10-bit 4K60 is not met yet (24.5 / 35.6 fps via P010; AFBC10 unmeasured), and one commit message has a `Claude-Session:` line |
| pr/feat/sunxi-h616-tv-encoder | New sun8i_tve driver is build-tested only; no TV tested |
| pr/feat/uboot-zero2-usb-boot | USB boot from a stick (on-board and expansion ports) not tested yet; the USB scan speed-up part is board-tested |
| pr/fix/uboot-sunxi-ce-rng-kaslr | KASLR seed board test (different `_stext` across boots) not recorded |
| pr/fix/sunxi64-bootscript-boot-source | Touches the shared `boot-sun50i-next.cmd` for every sun50i board; sandbox-verified for H616/A64/A133/A523, the SPI-boot board check ("U-boot loaded from SPI") not recorded |
| pr/fix/sunxi64-edge-realtek-phy-hwmon | Abandoned: the RTL8211F has no hwmon; the integration reverts it |

## User decisions (2026-11-02)
- OpenSSL 4 fix lives in `lib/functions/compilation/uboot.sh` (framework level): accepted.
- AI attribution: unify. At PR prep, every commit gets one trailer form, `Assisted-by: Claude` (no model suffix); stray `Claude-Session:` lines are removed. Done on fresh PR branches, never by rewriting pushed refs.
- Jernej Škrabec's decode patches: no advance ask; they keep his authorship.
- Still open: PR grouping (§ above); squash/reword items (openssl 2→1, regulators 2→1, distro subject).
