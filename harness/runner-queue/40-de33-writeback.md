# Job 40-de33-writeback (DEV-length, ~7 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault) = job 30 re-queued
Package: harness/research/de33-writeback/runner/ (script wb-job.sh, HANDOFF.md, checks 0-8 there).
Command: `bash harness/research/de33-writeback/runner/wb-job.sh wb40`
Why again: job 30 (c27) FAIL, every flip+writeback commit -EINVAL and "dumb buffer: Invalid argument" for XR30. Causes:
the test client attached the writeback connector in a non-modeset commit (a connector change is a full modeset; fixed in
harness/kms-wb, it now attaches it in its modeset commit) and the kernel refused XRGB2101010 framebuffers (no plane has the
format; fixed by 300d79df7). Also 30706dcc8 (capture armed only after its commit is latched) and the shifted flips labels
in results.txt.
Kernel: the newest cumulative kernel, which must contain 30706dcc8 (c35 = test-cumulative 30cee6952, Image md5
f3ec40c60dfbc0bfa94fdcf53ec9169b, or later). Blocked check (exit 2, BLOCKED file): kernel lacks 30706dcc8, DTB md5 differs,
no de33_wb_* parameters or no Writeback-1 connector; evidence in logs/runner-wb40/files/blocked-*/: report "not ready" with
the first 30 lines of state.txt.
Display: HDMI-A-1 forced on at 1024x768@60, no sink; a missing 1024x768 mode = NOT TESTED, never FAIL (HANDOFF check 0).
Client: harness/kms-wb/out/kms-wb (rebuilt 2026-11-06, sha256 0b6771963439bc2d99fb0490b053d44adc8310fefed5a0d3e74240fe386162be),
shipped if the board copy differs. The board must start on the stock image kernel; HTTP server 10.56.0.1:8643 up.
Results: harness/research/de33-writeback/logs/runner-wb40/ (results.txt has the values for the checks). Job 30's logs stay
in logs/runner-wb/.
Submitted by the de33-writeback agent, 2026-11-06.
