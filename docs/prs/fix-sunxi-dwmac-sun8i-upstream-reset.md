# sunxi-7.3: dwmac-sun8i: backport upstream reset-after-PHY-init and EPHY clock leak fixes

Branch: `pr/fix/sunxi-dwmac-sun8i-upstream-reset` (fd4905d96). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
Backport `fee9c17671b6` (reset the MAC after PHY init, James Hilliard) and `d9750b3c4c27` (EPHY clock leak, Cc stable)
from 7.4; drop Armbian's `drv-net-stmmac-dwmac-sun8i-reset-emac-on-open.patch` (its own earlier version of the same
change, superseded); rebase the H616 internal-PHY/AC300 patch on top.

## Why
Maintainer-reviewed superset of the Armbian patch (also masks interrupts before the reset, still clears DMA/IRQ
registers on timeout). Fixes Ethernet loss after warm reboot on RTL8211F boards such as the Orange Pi Zero2.

## Testing
Kernel-check: 691 patches / 0 failed, Image + modules + all DTBs built, 0 warnings in dwmac-sun8i.c. On the board
in every image since 2026-11-01 (warm and cold reboots, 1 Gbit link). Patch apply verified again on c2908d2.

## Upstream status
Both commits are in Linux 7.4; drop at the sunxi 7.4 bump (harness/research/prprep-emac1.md §4).

## Risk
Touches `drv-net-stmmac-dwmac-sun8i-add-h616-internal-phy.patch` (Zero2W, CB1, X96 Mate, BPi M4 Berry EMAC1) only by
re-diffing context; those boards were not tested here.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
