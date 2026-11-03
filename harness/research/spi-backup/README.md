# SPI NOR (mtd0, 2 MiB) updates

| Date | Before (full 2 MiB sha256) | Written | Source |
|---|---|---|---|
| 2026-11-03 | 711306f6434bee747ab96f911e5de251f87e5442e6ed33b2350cffa5522ee933 (SPL Nov 02 00:31, no DRAM retry) | 70ff8fad3b041f30c8dca52f811d26ff7150e7d553d3b9cd4756f40757975ec8 (899305 B, `flashcp -v`, read-back equal, eGON.BT0, contains "training retried") | image 4321861ff `/usr/lib/linux-u-boot-edge-orangepizero2/u-boot-sunxi-with-spl.bin` (= SD copy the board booted) |

Backup of the old contents: `mtd0-2026-11-03-pre.bin` (git-ignored binary). Restore: `flashcp -v mtd0-2026-11-03-pre.bin /dev/mtd0`.
