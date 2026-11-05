# IOMMU page faults at 0xfff00000 (master -1, dir rd): state

Task (2026-11-05): five `sun50i-iommu 30f0000.iommu: Page fault for 0x00000000fff00000 (master -1, dir rd)` lines at uptime
2140 s on cumulative kernel c9, seen in the aq1 round's dmesg tail (vdec-perf/logs/queue-aq1/round.txt). IOMMU stays on
for every master.

## 1. Which session, which workload
- c9 booted at about 17:34:30 UTC (round.txt: uptime 3481 s at 18:32:35; board-info.txt: uptime 3266 s at 18:28:52).
  Uptime 2140 s = **18:10:10 UTC**, not 17:58.
- Board 17:33-18:10 UTC was the desktop-ffmpeg session (impl-desktop-ffmpeg.md 4.1, commit f8349fa 18:13):
  `harness/ffmpeg/mpv-board-test.sh` 17:37-17:44 (mpv `--vo=gpu --gpu-context=drm`, which **forced the HDMI connector
  on**, no monitor attached, 1024x768 fallback mode: DE scanout of the fbcon framebuffer from then on), pass 2 until
  18:02, then the packaged-ffmpeg md5 runs `kernel-check/ffmpeg-deb/board/out-c9-deb/` 18:03-18:10; the last one
  (AVS2 cctv4k 10-bit, `cctv.framemd5` written 18:10:12) ends at the fault time.
- The aq1 script printed `dmesg | grep ... | tail -5`: the five lines are the **last five**, not all of them.
- The five are vsync-spaced: 16.6-16.7 ms apart (1024x768@60 = 16.67 ms; the VE ran at 16.3 ms/frame), with a gap of
  exactly 16 frames between the bursts of 2 and 3. The reader is the display engine, not the VE.
- Same line on 2026-11-03 at 1.44 s / 1.51 s after boot in two unrelated boots with a display
  (harness/afbc-kms-play/results-2026-11-03*/de33-out/dmesg-*.txt), 16 ms after `Console: switching to colour frame
  buffer device 128x48`: the first scanout frame of the fbcon framebuffer. Once per boot, none during 600 4K flips.
- The vdec-perf rounds never show it: they run without a display (connector off, no DE scanout).

## 2. Cause
- dma-iommu allocates IOVAs top-down and size-aligned. The fbcon framebuffer (1024x768x4 = 3 MiB, aligned to 4 MiB) is
  the first allocation in the shared domain and lands at 0xffc00000-0xffefffff; the top 1 MiB 0xfff00000-0xffffffff is
  never mapped (its DTE stays invalid). 0xfff00000 is the page right after the framebuffer's end.
- The IOMMU TLB prefetcher (IOMMU_TLB_PREFETCH_REG, enabled for every master) walks the page after the one the DE is
  reading; at the end of the framebuffer that walk hits the invalid DTE. The H616 UM (3.12.6.50/51) gives
  IOMMU_L1PG_INT_REG / IOMMU_L2PG_INT_REG a bit 31 ("DBG_MODE", debug mode address switch) next to the master bits 0-6;
  Allwinner's sunxi-iommu (linux-orangepi orange-pi-5.4-sun50iw9, sunxi_iommu_irq) treats a page table interrupt with
  bit 31 as a prefetch of an invalid page table ("It's OK to prefetch an invalid pagetable") and does not report it. Our
  driver masks the register to the master bits, gets 0, and prints ilog2(0) = **-1** as the master: the decode was wrong,
  not the hardware's attribution.
- Repeats: `sun50i_iommu_iotlb_sync` flushes the whole TLB + PTW cache on every unmap, so each buffer free during a
  decode re-exposes the DE's next frame to the walk: one line per frame after a flush (ffmpeg's exit frees ~dozens of
  buffers over a few frames: bursts of 2 and 3). No device accessed 0xfff00000; nothing was stalled or lost.
- The vendor BSP for sun50iw9 writes IOMMU_TLB_PREFETCH_REG = 0 (prefetch off for every master) and the UM says
  prefetch "is suggested to disable" for G2D (master 6). We keep prefetch on (the micro-TLB is the VP9 4K60 limit;
  nothing on by default is turned off); the fix is in the fault decode.
- The register layout vs. H6: the H616 adds master 6's registers (ERR_ADDR_REG6 0x128, ERR_DATA_REG6 0x168), L1/L2 are
  ERR_ADDR_REG7/8 at 0x130/0x134 (same offsets the driver uses) and ERR_DATA_REG7/8 at 0x170/0x174 (the driver's
  `0x150 + i*4` formula would be wrong for 7/8 but is never used for them). It also has IOMMU_TLB_IVLD_MODE_SEL_REG
  (0x84) with START/END address registers (0x88/0x8c); mode 0 (default) is the H6-style addr+mask the driver uses.

## 3. Fix
- armbian-build branch **fix/sunxi-iommu-prefetch-pt-fault** (from test-cumulative 7897dec08), commit **c411b37fb**,
  pushed to `fork` only. Patch `patches.armbian/iommu-sun50i-dont-report-tlb-prefetches-of-unmapped-pages.patch`,
  series.conf line 887 (after the last patch touching sun50i-iommu.c). Dry-run on the c17 source and
  `make W=1 drivers/iommu/sun50i-iommu.o` clean.
- What it does: a page table interrupt with bit 31 (`IOMMU_PG_INT_PREFETCH`) set and no master bit returns early
  (dev_dbg, no report_iommu_fault, no reset, no zap). Real page table faults now print
  `Page fault for <iova> (master N, dir rd, L1|L2 page table, status 0x...)` (master -1 only if the hardware sets no bit
  at all, with the raw status), permission faults `..., permission, status 0x...`. Scripts grepping `Page fault` keep
  working.
- Not changed: prefetch stays on for all masters; the top-of-IOVA layout is the allocator's normal behaviour, not a bug.

## 4. Board check
Runner job `harness/runner-queue/17-iommu-faults.md` (package `runner/`, HANDOFF.md): chunk stock = positive control on
the image kernel (force the HDMI connector on, expect >= 1 fault line; H.264 4K decode x3, more lines), chunk fixed =
same on the newest cumulative kernel containing c411b37fb, expect 0 `Page fault` lines. Needs the coordinator to merge
the branch and build the next cumulative kernel first (the script blocks otherwise).

## 5. Open
- Board confirmation of bit 31 (job 17). If the fixed kernel still logs `Page fault ... (master -1, ..., status 0x0)`,
  the hardware sets no bit for the prefetch walk; then the decode should treat "no master bit" as the prefetch case.
- Side note for the work list, not done here: the UM suggests prefetch off for G2D (master 6) when a G2D driver arrives.

## For a fresh agent
Read this file, done/17-iommu-faults.summary.md, and the branch commit. Pass = chunk-fixed `faults-new 0` twice and no
`Page fault` line; then the coordinator merges and the item closes. CONFIG_DYNAMIC_DEBUG is off in the Armbian config,
so the dev_dbg line is not visible on the board; the control chunk on the stock kernel is the positive evidence.
