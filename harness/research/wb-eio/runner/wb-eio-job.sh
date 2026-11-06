#!/bin/bash
# Job 55 (wb-eio): DE33 writeback -EIO repeat check. Thin wrapper around the afbc-wb package (same script, case set j55):
# real-hevc8 (4K H.265 8-bit, linear NV12 pass = the case that gave wb_error -5 in jobs 53/54) five times, real-hevc10,
# and the syn-hevc8/-hevc10/-vp9p0/-hevc8-xr24 regression cases. Logs: harness/research/afbc-wb/logs/runner-j55/.
# Resumable: re-running skips the cases already done. See HANDOFF.md beside this file.
exec bash /home/aruni/orangepizero2/harness/research/afbc-wb/runner/afbc-wb-job.sh j55
