# sunxi-7.3: orangepi-zero2: rgmii-rxid, mmc aliases, SPI-NOR supply, USB-C host overlay

Branch: `pr/group/orangepi-zero2-dt` (90337602c). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What (5 commits)
- EMAC: `phy-mode = "rgmii-rxid"` (RX delay in the RTL8211F) instead of MAC-side 3100 ps, like the Zero3.
- `mmc0` = SD, `mmc1` = SDIO WiFi aliases in `sun50i-h616-orangepi-zero.dtsi`.
- SPI-NOR `vcc-supply` = ALDO1; megous 0028 `phy-io` regulator made optional (two "using dummy regulator" lines gone).
  (Two commits: the first also set `r_pio vcc-pl-supply`, which created an RSB/AXP probe cycle; the second drops it.
  Squash before opening.)
- New overlay `sun50i-h616-usb-otg-host` (USB-C as host when powered from the header); IR stays overlay-only
  (receiver is on the expansion board, schematic v1.3).

## Why / evidence (Orange Pi Zero2)
- Intermittent boots with link up and zero RX frames. On a bad boot, enabling PHY RXDLY and setting syscon ERXDC=0
  restored RX instantly; with rgmii-rxid 10/10 cold boots had working RX.
- SD card came up as `/dev/mmcblk1` on some boots.
- `dmesg | grep -c 'dummy regulator'` 3 -> 0 for spi-nor and phy-io (board PASS).
- Overlay: fdtoverlay on the Zero2 DTB gives `dr_mode = "host"` and ehci0/ohci0 okay; on-board host test still
  needs the header-powered setup.

## Upstream status
Mainline 7.4-rc1 Zero2 DTS still uses `rgmii` + `allwinner,rx-delay-ps = <3100>`; no mmc aliases. The rxid and
alias patches are mainline-style and can be sent to linux-sunxi as well.

## Open item before opening
Ethernet on the debug kernels: bulk host->board TCP copies stall at exactly 512 KiB and 8000-byte pings lose
~33 % after about 1 h uptime (small packets fine, error counters 0, 6 TX drops). Not retested on the image kernel.
Retest first; if it reproduces, decide whether it is related to the RX delay setting.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
