# u-boot: link host tools against OpenSSL 4 (ENGINE API removed) for every U-Boot

Branch: `pr/fix/uboot-sunxi64-host-tools-openssl4` (5b405dd16). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
`compile_uboot_target()` probes the host OpenSSL version. On OpenSSL >= 4 it builds the U-Boot host tools with
`HOSTCFLAGS=-DOPENSSL_ENGINE_STUBS` (OpenSSL's own compatibility stubs) after a link probe proves the stubs work;
for trees whose Makefile does not take `HOSTCFLAGS`, or hosts without usable stubs, it falls back to
`scripts/config --disable TOOLS_KWBIMAGE --disable TOOLS_LIBCRYPTO`. No-op on OpenSSL 3 hosts (Armbian's build
containers). Runs before the `post_config_uboot_target` hook, so extensions can override. The earlier
sunxi64-only source patch is removed.

## Why
OpenSSL 4.0 removed the ENGINE API; `lib/rsa/rsa-sign.c` (mkimage FIT signing, in every U-Boot since 2016) still
calls `ENGINE_*()`, so `make` fails at link time on Ubuntu 26.10 hosts (OpenSSL 4.0.3) for every family and U-Boot
version. A framework fix covers all 49 `patch/u-boot/*` dirs and vendor trees at once, next to the existing gcc-14
host workarounds in the same function, and does not change any U-Boot artifact hash (compile_uboot_target is
not hashed).

## Testing
Ubuntu 26.10 host, OpenSSL 4.0.3, U-Boot v2026.10, `orangepi_zero2_defconfig`, `make tools`:
- without the change: the tools link fails on undefined `ENGINE_*` symbols (reproduced);
- stubs path: links; `mkimage -f t.its -k keys` signs a FIT with an RSA-2048 key;
- fallback path (forced by failing the link probe): `TOOLS_LIBCRYPTO`/`TOOLS_KWBIMAGE` off after olddefconfig, tools link.
Full Orange Pi Zero2 images built on this host with the earlier source-patch variant boot on the board.

## Upstream status (2026-11-02)
Not fixed in U-Boot master (`lib/rsa/rsa-sign.c` last changed 2025-11-11). Heinrich Schuchardt's
"[PATCH 1/1] tools: fix building with OpenSSL 4.0" (June 2026) adds the same define; Quentin Schulz objected
(engines should not be built without ENGINE support; breaks the dummy-rsa-engine test). "Add support for OpenSSL
Provider API" (Eddie Kovsky, v3, January 2026) is still in review. Remove this once either lands.

## Notes for the submitter
Two commits (add sunxi64 patch, then replace it): squash into one before opening.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
