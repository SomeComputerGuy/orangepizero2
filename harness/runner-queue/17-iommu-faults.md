# Job 17-iommu-faults (DEV, ~12 min incl. two reboots)
Package: harness/research/iommu-faults/runner/ (script iommu-job.sh, HANDOFF.md).
Command: `bash harness/research/iommu-faults/runner/iommu-job.sh`
Kernel: chunk "stock" on the stock image kernel (control), chunk "fixed" on the newest cumulative kernel
(kernel-check/cumulative-kernels.txt), which must contain fix/sunxi-iommu-prefetch-pt-fault c411b37fb (the script exits 2 +
BLOCKED otherwise: report "not ready", not FAIL). No debs; HTTP servers 10.56.0.1:8643 and :8644 must be up.
Checks: HANDOFF.md "Checks" (mechanical: ROUND-DONE, `[scanout] faults-new`, `[decode] faults-new`, `Page fault` count = 0 on
the fixed kernel). Results: harness/research/iommu-faults/logs/runner-iommu-faults/. Submitted 2026-11-05 by the iommu-faults agent.
