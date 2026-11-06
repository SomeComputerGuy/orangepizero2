# Job 19-display-tearing (DEV-length, ~10 min in 2 chunks, resumable, fails fast on Oops/WARN)
Package: harness/research/display-tearing/runner/ (script tearing-job.sh, HANDOFF.md, checks 0-7 there).
Command: `bash harness/research/display-tearing/runner/tearing-job.sh latch`
Kernel: chunk `stock` runs on the stock image kernel (baseline), chunk `fix` on the newest cumulative kernel, which must
contain fix/sunxi-h616-de33-vblank-latch at b04527be4 (wt-display-tearing; DE33 registers written from the vblank IRQ
instead of the commit worker). Coordinator: merge b04527be4 into test-cumulative and build/serve it first (c20 or later;
c19 is refused). The script blocks (exit 2) if the installed kernel lacks it. The board must start on the stock image kernel.
Display: HDMI-A-1 forced on at 1024x768@60, no sink; a missing 1024x768 mode = NOT TESTED, never FAIL (HANDOFF check 0).
Results: harness/research/display-tearing/logs/runner-latch/ (results.txt has the values for the checks).
Submitted by the display-tearing agent, 2026-11-05.
