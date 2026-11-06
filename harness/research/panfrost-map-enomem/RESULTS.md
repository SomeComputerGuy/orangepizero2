# panfrost BO mapping under memcg pressure (work-list item 7): state

## Current state (2026-11-06)
- Kernel fix done, build-checked, in c48; runner job 63-panfrost-map-enomem queued. Waiting on the board result.

## Origin
GPU rerun 2026-11-04 (stock kernel #17, harness/analysis/gpu/cts-8546e5fc1-server, CTS queue under MemoryMax=600M):
dEQP-GLES31.functional.draw_indirect.compute_interop.large.drawelements_{separate,combined}_grid_1000x1000_drawcount_5000
= OOM (`DRM_IOCTL_PANFROST_CREATE_BO failed (err=12)`), and dmesg had `WARNING ... panfrost_mmu.c:478 at
panfrost_mmu_map+0xcc` 5x (noted in docs/status-history.md; the dmesg itself was not saved). Alone under 800M both Pass.

## Root cause
- The WARN: vanilla 7.3.1 line 477/478 `if (WARN_ON(IS_ERR(sgt)))` after drm_gem_shmem_get_pages_sgt(), which returns
  -ENOMEM (memcg limit) or -EINTR (OOM kill during dma_resv_lock_interruptible) as ordinary errors. Already removed by
  da59f9208 (fix/sunxi-panfrost-mmu-map-warn, merged test-cumulative 13e656cca on 2026-11-05, in every kernel since
  c39 / work-cumul line 477 is plain `if (IS_ERR(sgt))`). The work-list item predates that merge.
- Remaining unwind bugs in the same failure paths (a524d09da, this task):
  1. panfrost_mmu_map(): on mmu_map_sg() failure `err_put_pages: drm_gem_shmem_put_pages_locked(shmem)` - called
     without the resv lock (helper asserts it) and drops the only page ref, which belongs to the sgt cached in
     shmem->sgt -> pages freed while the sgt still maps them (stale DMA unmap at free, UAF if the BO is mapped again;
     refcount_t underflow WARN for an imported BO). Fix: just return the error.
  2. mmu_map_sg(): on map_pages() -ENOMEM the part of the failing call already mapped (`mapped`) was not unwound ->
     stale PTEs in a VA range drm_mm reuses (next map there hits -EEXIST + io-pgtable WARN). Fix: add it to
     total_mapped, unmap, flush the range.
  3. panfrost_mmu_map_fault_addr() (heap growth): when shmem_read_folio / sg_alloc / dma_map / mmu_map_sg failed,
     the folios read for the 2 MB chunk stayed in bo->base.pages while the chunk's sgt stayed empty -> the next fault
     in the chunk re-reads it and hits `drm_WARN_ON(already_owned)`. Fix: panfrost_heap_put_chunk() gives the
     chunk's folios back on those paths.
- Upstream: linux master, linux-next and drm-misc-next (fetched 2026-11-06 into
  kernel-check/dl-upstream-panfrost-mmu/) still have the WARN_ON and the unlocked put_pages_locked (introduced by
  "drm/panfrost: Handle page mapping failure"); no upstream fix to backport. Not sent upstream.

## Commits (armbian-build, pushed to remote fork)
- fix/sunxi-panfrost-mmu-map-enomem a524d09da (worktree wt-panfrost-map-enomem), patch
  patch/kernel/archive/sunxi-7.3/patches.armbian/drm-panfrost-unwind-a-failed-gpu-mapping-without-touching-its-pages.patch
  (series.conf after drm-panfrost-name-the-bos-around-an-unhandled-page-fault.patch). checkpatch clean.
  Build check: kernel-check/run-map-enomem-all.log (884 patches, 0 failed, 0 C warnings).
- test-cumulative b82264f81 (merge) = c48, Image md5 ba448c353e2327b69c7d38671a7bfc78
  (kernel-check/run-cumul-c48.log; served in kernel-check/vdec-serve/{Image.c48,modules-c48.tgz,dtb.c48}).

## Board test
Runner job harness/runner-queue/63-panfrost-map-enomem.md, package runner/map-enomem.sh + runner/HANDOFF.md:
oom chunk (the 2 cases, 6 rounds MemoryMax 600M x3/450M/500M/700M, GPU-alive probe after each), gles31-di (221),
gles31-compute (195), khr-compute (39), ocl (job-52 suites minus Relationals, fork build-cl at /root/opiz2-mesa/pme).
Results: logs/runner/.

## Open items / next step
- Next: when job 63's summary arrives (harness/runner-queue/done/63-panfrost-map-enomem.summary.md), a fresh agent
  checks: check 2 (0 WARN/oops) PASS + check 3 (no hang) PASS -> item 7 DONE, fold into the image branch. A WARN in
  files/oom/dmesg-oom.full -> read its backtrace (which path) and fix. NOT EXERCISED -> lower the limits in ROUNDS.
