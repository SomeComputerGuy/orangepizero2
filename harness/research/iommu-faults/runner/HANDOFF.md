# Runner job iommu-faults: handoff (DEV, about 12 min incl. two reboots)

Command: `bash harness/research/iommu-faults/runner/iommu-job.sh`

What it does: two chunks with the same board script (`runner/board-iommu.sh`): it forces the HDMI connector on (no
monitor is attached; the DE then scans out the fbcon framebuffer in the 1024x768 fallback mode), counts the new
`Page fault` lines in dmesg, decodes a 4K H.264 stream through cedrus three times (buffer frees flush the whole IOMMU
TLB while the display scans out), counts again, and puts the connector back to `detect`.
- chunk `stock`: on the stock image kernel `vmlinuz-7.3.1-edge-sunxi64` (positive control: the unfixed driver logs
  `Page fault for 0x00000000fff00000 (master -1, dir rd)` on the first scanout frame).
- chunk `fixed`: on the newest cumulative kernel (last line of kernel-check/cumulative-kernels.txt), installed with the
  vdec fallback armed; it must contain fix/sunxi-iommu-prefetch-pt-fault (c411b37fb, merged by the coordinator). The
  script checks this itself and exits 2 with `BLOCKED` if the newest kernel predates the merge: report "not ready:
  kernel without the fix", not FAIL. The stock kernel is restored at the end.
The script handles the board lock (owner `runner-iommu-<epoch>`), a stall watchdog, and is resumable (chunks listed in
`logs/runner-iommu-faults/state` are skipped). It needs the HTTP servers 10.56.0.1:8643 (kernel-check/vdec-serve) and
10.56.0.1:8644 (kernel-check/vdec-streams) up; if a download fails the `[decode]` line says `download failed` and the
decode step is skipped (the scanout checks still count).

Results: `harness/research/iommu-faults/logs/runner-iommu-faults/`: `runner.log`, `chunk-stock.txt`, `chunk-fixed.txt`,
`dmesg-stock.txt`, `dmesg-fixed.txt`, `BLOCKED` (only when blocked).

Exit codes: 0 = both chunks ran (judge with the checks below); 2 = blocked (report `BLOCKED` + last 10 lines of
runner.log); 1 = setup or lock error.

## Checks
chunk-stock.txt (control, data: it shows that the trigger works):
- PASS if `grep -c ROUND-DONE` = 1.
- Report N from the `[scanout] ... faults-new N` line. N >= 1 means the trigger reproduces. N = 0 is INCONCLUSIVE
  (the trigger did not fire), not FAIL.
- Report M from the `[decode] ... faults-new M` line (or the `download failed` text).

chunk-fixed.txt (the actual test):
- PASS if `grep -c ROUND-DONE` = 1.
- PASS if the `[scanout]` line shows `faults-new 0`.
- PASS if the `[decode]` line shows `faults-new 0` (skip this check if it says `download failed`).
- PASS if `grep -c 'Page fault' chunk-fixed.txt dmesg-fixed.txt` = 0. Any `Page fault` line is a FAIL: copy it exactly
  (its text now names the level and the raw status, e.g. `L1 page table, status 0x80000000`).
- PASS if `timeouts 0` on the `[decode]` line and no `timed out` line in dmesg-fixed.txt.

The summary must list: both `kernel` lines, both `[scanout]` lines and both `[decode]` lines (copied exactly), the
`[dmesg]` lines of each chunk, and the content of dmesg-stock.txt / dmesg-fixed.txt.
