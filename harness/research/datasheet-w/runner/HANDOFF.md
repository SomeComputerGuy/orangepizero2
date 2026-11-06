# Runner job datasheet-w (19, rerun as 24): handoff (DEV, about 12 min incl. two reboots)

Command: `bash harness/research/datasheet-w/runner/dsw-job.sh`

What it does: one DEV chunk on the newest cumulative kernel (last line of kernel-check/cumulative-kernels.txt, installed by
harness/research/vdec-perf/install-kernel.sh with the vdec fallback armed; it must contain the UM-review merges (c19) AND
armbian-build commit 61fb5e0e2 `fix/sunxi-h616-ahub-dam-aux-card` (the ahubdam card fix, merged by the coordinator after
c22), else the script exits 2 with `BLOCKED`: report "not ready", not FAIL).
Job 19 (c19) failed W6, W18 and W31; analysed 2026-11-06 (RESULTS.md "Job 19 analysed"): W6 and W31 were test bugs (uname -m
of a compat task is "aarch64" without the linux32 personality; the autoneg line was read before link-up and printed without the
"yes"), W18 is a real bug: the overlay applied and the card's probe failed with -22 ("has no playback, no capture"), fixed in
61fb5e0e2. The job runs with a fresh `logs/runner/` (job 19's is `logs/runner-job19/`). Before the reboot it puts three host-built
overlays into `/boot/overlay-user/` (`dsw-spdif-out`, `dsw-i2s3-ph`, `dsw-ahub-dam`, from kernel-check/datasheet-w/dtbo) and
adds a `user_overlays=` line to `/boot/armbianEnv.txt`; nothing under `/boot/dtb` is touched. On the board,
`board-dsw.sh` runs the mechanical checks of the datasheet W-items that need no extra hardware (hstimer, COMPAT, SPI dual
read, SDIO UHS, WiFi 32 kHz clock, codec DRC controls, S/PDIF card + clock rate, I2S3 card stream + DAM controls, DE33 planes,
DI300 device/compliance/weave, half duplex). The half-duplex test runs detached on the board (it bounces end0 for about 40 s);
the host waits for it and appends its CHECK lines. Chunk `restore` removes the overlays and the trial kernel and reboots to the
stock image kernel `vmlinuz-7.3.1-edge-sunxi64`.
The script handles the board lock (owner `runner-dsw-<epoch>`), a stall watchdog (300 s), and is resumable (chunks listed in
`logs/runner/state` are skipped). It needs the HTTP server 10.56.0.1:8643 (kernel-check/vdec-serve, used by install-kernel.sh).
No other servers, no wiring, no monitor.

Results: `harness/research/datasheet-w/logs/runner/`: `runner.log`, `checks.txt` (all CHECK/INFO lines), `hd.txt` (half
duplex), `dmesg.txt`, `board/*.txt` (per-check raw output), `BLOCKED` (only when blocked).

Exit codes: 0 = chunk ran and the board is back on the stock kernel (judge with the checks below); 2 = blocked (report
`BLOCKED` + the last 10 lines of runner.log); 1 = setup or lock error.

## Checks (all in checks.txt)
- PASS if `grep -c ROUND-DONE checks.txt` = 1.
- Every line `CHECK <item> PASS|FAIL|SKIP <value>` is one result. The summary lists ALL of them verbatim (there are about 28).
  PASS/FAIL is already decided on the line. SKIP lines are reported as SKIP with their reason, not as FAIL.
- Overall: PASS if `grep -c 'CHECK .* FAIL' checks.txt` = 0.
- `CHECK W31-half-duplex FAIL no HD-DONE` means the half-duplex script did not finish: copy hd.txt into the summary.
- dmesg.txt: copy any line containing `Page fault`, `timed out`, `Oops`, `BUG:` or `WARNING` exactly; none expected.
- runner.log: the line starting with `restored:` must show `vmlinuz-7.3.1-edge-sunxi64` and `0` (no dsw- overlay left).

The summary must list: the `kernel:` line, the `overlays:` line and the `INFO asound cards:` line from checks.txt, every
CHECK line, the `INFO aplay -D default` line, the content of hd.txt, the `restored:` line, and the dmesg lines above.
