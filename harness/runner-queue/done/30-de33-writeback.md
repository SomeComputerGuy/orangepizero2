# Job 30-de33-writeback (DEV-length, ~7 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault) = job 21 re-queued
Package: harness/research/de33-writeback/runner/ (script wb-job.sh, HANDOFF.md, checks 0-8 there).
Command: `bash harness/research/de33-writeback/runner/wb-job.sh wb`
Why again: job 21 was BLOCKED "no Writeback-1 connector / de33_wb_* parameters" on c24, which does contain 6dbed6c18: the
writeback is a DT node (writeback@10000 + the de33 clock syscon range) and harness/research/vdec-perf/install-kernel.sh
installed only the Image and the modules, so the board booted the stock DTB without the node and sun50i_wb had nothing to
bind (the driver then keeps the display up without a connector, as designed). install-kernel.sh now installs the tag's DTB
too; the script verifies the DTB md5 and checks the parameters and the connector separately, with evidence when blocked.
Kernel: the newest cumulative kernel, which must contain fix/sunxi-h616-de33-writeback at 6dbed6c18 (c23+, c26 has it). No
new kernel commit is needed. Blocked check (exit 2, BLOCKED file): kernel lacks 6dbed6c18, DTB md5 on the board differs from
kernel-check/vdec-serve/sun50i-h616-orangepi-zero2.dtb.<tag>, no de33_wb_* parameters, or no Writeback-1 connector; evidence in
logs/runner-wb/files/blocked-*/ (state.txt, dmesg.txt, drm-classes.txt): report "not ready" with the first 30 lines of state.txt.
Display: HDMI-A-1 forced on at 1024x768@60, no sink; a missing 1024x768 mode = NOT TESTED, never FAIL (HANDOFF check 0).
Client: harness/kms-wb/out/kms-wb (libdrm only), shipped if the board copy differs. The board must start on the stock image
kernel; HTTP server 10.56.0.1:8643 up.
Results: harness/research/de33-writeback/logs/runner-wb/ (results.txt has the values for the checks).
Submitted by the driver-bringup agent, 2026-11-06.
