# vmlinux BTF dedup bug (3x struct device) - root cause and fix

Status 2026-11-05: fix merged (c7, test-cumulative 283e88200), host-side verified. Board test PAUSED by the
coordinator (credit limit) before the kbase insmod / session2 step. Nothing goes upstream.

## Symptom
bifrost_kbase.ko refused on c3: `distilled base BTF type 'device' [10], size 784 has multiple candidates of the
same size (ids [95063, 95062]) in base BTF`, `failed to validate module [bifrost_kbase] BTF: -22`.
Any module carrying distilled BTF (out-of-tree, DKMS) and BPF CO-RE against these types would hit this.

## Root cause
`include/sunxi-iommu.h`, added by Armbian's `patches.armbian/drv-iommu-sunxi-add-iommu-driver.patch` (sun55i/A523
IOMMU, CONFIG_SUN55I_IOMMU=y in linux-sunxi64-edge.config), redefines `struct iommu_dma_cookie` (+ `enum
iommu_dma_cookie_type`) with an old dma-iommu.c layout: 160 bytes, members type/union{iovad,msi_iova}/
msi_page_list/fq_domain. The real one is private to drivers/iommu/dma-iommu.c: 248 bytes, 9 members
(iovad, msi_page_list, fq union, fq counters, fq_timer, ..., options). Neither sun55i file uses it (dead code).
- Compilation units: `pahole -C iommu_dma_cookie` shows the 160-byte variant in drivers/iommu/sun55i-iommu.o and
  sun55i-iommu-pgtable.o, the 248-byte one in drivers/iommu/dma-iommu.o.
- struct iommu_domain has `iova_cookie` -> iommu_dma_cookie, and iommu_domain is reachable from struct device
  (dev_iommu, iommu_ops, ...), fwnode_handle, irq_domain, etc. libbpf/pahole dedup cannot unify graphs that end
  in different bodies, so the whole cluster stays split.
- Evidence: kernel-check/btf-dedup/walk.py + roots.py (git-ignored dir) compare every duplicated named type
  pair down to the first pair whose own content differs: all 53 type names that were split by this (device,
  device_driver, bus_type, class, fwnode_*, iommu_*, irq_domain, irq_desc, irq_chip, platform_device,
  of_phandle_args, dev_pm_ops, wakeup_source, pm_callback_t, ...) end at iommu_dma_cookie 248 vs 160.
- Vanilla 7.3.1: the tarball has no include/sunxi-iommu.h and only one `struct iommu_dma_cookie {` (dma-iommu.c),
  so the clash cannot happen there. No separate vanilla build was done: it would take the single kernel build
  lock for a full build and only prove a negative. The A/B that matters is the one header change, done in the
  shared tree (c4 vs c5+fix vs c7 below). Not a pahole 1.31 / libbpf bug: dedup is right to refuse to merge
  structs whose bodies differ.

## Fix
New patch `patches.armbian/iommu-sun55i-drop-the-stale-iommu_dma_cookie-copy.patch` placed right after
drv-iommu-sunxi-add-iommu-driver.patch in sunxi-7.3/series.conf. It removes the stale enum and struct from
include/sunxi-iommu.h. The sun55i driver stays enabled; no feature dropped.
Branch fork `fix/sunxi-iommu-btf-dedup`, commit bd60a159b (based on test-cumulative ca92040e8); merged by the
coordinator as 283e88200, first included in c7 (91c6912a4).

## Results (host)
| vmlinux | STRUCT 'device' | duplicated named types (STRUCT/UNION/ENUM/TYPEDEF) | BTF types |
|---|---|---|---|
| c4 (no fix) | 3 ([95062..95064]) | 73 | 155043 |
| c5 + fix (build-kernel.sh, ARMBIAN=wt-iommu-btf) | 1 | 20 | 154229 |
| c7 (cumulative, includes fix) | 1 | 20 (same list as c5+fix) | 154233 |
The 20 left are unrelated file-local structs with the same name (cstate, urb_priv, perf_aux_event, serport,
deinterlace_ctx/dev, ...); none traces to a shared type.
Build: patches 830/0, build exit 0, 0 C warnings, dtbs 0 warnings.
kbase: kernel-check/kbase-trial/port/build.sh against c7 builds, modinfo vermagic `7.3.1 SMP preempt mod_unload
aarch64`. Host check of the distilled BTF: `bpftool btf dump file bifrost_kbase.ko -B <vmlinux>` resolves against
the c7 vmlinux and fails against the c4 vmlinux with the exact board error (multiple candidates [95063, 95062]).
Side fix (kernel-check/kbase-trial/port/build.sh, git-ignored): `rm -f bifrost_kbase.ko` before make. M= builds do
not depend on vmlinux (Makefile.modfinal needs KBUILD_BUILTIN), so after a kernel rebuild the old .ko kept BTF
distilled from the old vmlinux.

## Board
- Image kernel 7.3.1-edge-sunxi64 #17 (Oct 30): /sys/kernel/btf/vmlinux does not exist. The image kernel has no
  BTF at all, so it cannot show the duplicates. That is a separate gap, still OPEN: check the Armbian builder's
  KERNEL_BTF handling (it can turn DEBUG_INFO_BTF off, e.g. on low host memory) and make the image kernel ship BTF
  like the test kernels do.
- Stopped there: the kbase insmod check on c7 (or the newest c8) and kernel-check/kbase-trial/session2.sh did not
  run. session2 only got as far as building kbase for c8 while waiting for the lock; it never touched the board.
  To resume: `bash kernel-check/kbase-trial/session2.sh` (installs the newest c<N>, LOAD step prints dmesg after
  insmod; look for "failed to validate module" / BTF lines).
