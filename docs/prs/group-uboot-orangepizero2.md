# u-boot: sunxi64: orangepizero2: AXP305 over RSB in SPL, no env probing, SPI NOR boot image

Branch: `pr/group/uboot-orangepizero2` (b2e5e1e98). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What (3 commits, all `patch/u-boot/v2026.10-sunxi64`)
- H616 support in the sun8i RSB driver and `CONFIG_SYS_I2C_SUN8I_RSB` for the Zero2.
- `ENV_IS_NOWHERE` (Armbian never saves an env; the FAT probe only printed errors).
- SPI NOR: vendor flash ID tables, `write_uboot_platform_mtd()` for armbian-install, README section.

## Why / evidence (Orange Pi Zero2)
- TF-A leaves the AXP305 in RSB mode; the SPL spoke I2C only, so every warm reboot printed "Failed to set core
  voltage" and ran at 408 MHz until Linux. With RSB: no core-voltage line warm or cold, SPL->kernel 6.5 s (was 8.5 s).
- `Loading Environment from nowhere... OK`.
- U-Boot written to the 2 MiB SPI NOR with flashcp + read-back compare; with the SD SPL zeroed the BROM boots
  "sunxi SPI" and Linux comes up from SD; fallback chain SD -> USB -> PXE -> DHCP -> prompt in ~11 s.

## Upstream status
U-Boot main (source.denx.de, 2026-11-01) has no H616 RSB support; the RSB patch is a candidate for upstream.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
