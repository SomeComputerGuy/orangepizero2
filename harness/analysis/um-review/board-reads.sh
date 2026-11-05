#!/usr/bin/env bash
# Read-only board checks for the H616 user-manual review (harness/research/user-manual-review.md).
# Run on the board as root. No writes to any register or file.
set -u
echo "== kernel"; uname -r; cat /proc/version | cut -c1-120
echo "== clocksource"; cat /sys/devices/system/clocksource/clocksource0/available_clocksource
echo "== spi-nor params"; grep -E "name|jedec|read|protocol" /sys/kernel/debug/spi-nor/spi0.0/params 2>/dev/null | head -12
echo "== mtd0 sha256 + time"; /usr/bin/time -f "%e s" sha256sum /dev/mtd0ro 2>&1
echo "== mmc1 ios"; cat /sys/kernel/debug/mmc1/ios 2>/dev/null
echo "== clk_summary"; grep -E "^ *(osc32k-fanout|emac-25m|pll-audio|pll-periph0 |apb1|apb2|spdif|audio-hub|audio-codec|bus-iommu|hdmi-cec) " /sys/kernel/debug/clk/clk_summary
echo "== DRC controls"; for c in $(aplay -l 2>/dev/null | sed -n 's/^card \([0-9]*\).*/\1/p' | sort -u); do amixer -c $c controls 2>/dev/null | grep -iE "DRC|HPF"; done
echo "== devmem"
DM=""; command -v devmem >/dev/null && DM=devmem; [ -z "$DM" ] && command -v busybox >/dev/null && busybox devmem 0x03001000 >/dev/null 2>&1 && DM="busybox devmem"
if [ -n "$DM" ]; then
  for a in 0x030017BC 0x03001078 0x03001178 0x03001970 0x03001A20 0x03001A50 0x03001A54 0x03001A60 \
           0x03000030 0x07000060 0x0700000C 0x050000B4 0x050000C0 0x050004B4 0x050004C0 \
           0x0300B340 0x0300B344 0x0300B348 0x0300B350; do
    printf "%s %s\n" $a "$($DM $a 2>&1)"; done
else echo "no devmem"; fi
grep -c IO_STRICT_DEVMEM=y /boot/config-$(uname -r) 2>/dev/null
