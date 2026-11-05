# Rules for every agent working on this project (read first)

Project: Armbian image for the Orange Pi Zero2 (H616) as a CUPS print/scan server. Ubuntu 26.10 "stonking", kernel
7.3.1 (sunxi-7.3 patch set), U-Boot v2026.10, TF-A lts-v2.14.11. Goal: every hardware feature works, nothing dropped.
Acceptance: docs/spec-checklist.md, docs/datasheet-checklist.md. Status/work list: docs/status.md section 3.

## Board (shared, one owner at a time)
- Take the lock before ANY command that touches the board (ssh, serial, reflash, trial kernel, power):
  `harness/board-lock.sh acquire <your-name>`; release with `harness/board-lock.sh release <your-name>`.
  Hold it for one session (aim <= 60 min), then release so the others can test. Do host-side work while waiting.
- Before release the board must be up on the image kernel, or a trial kernel with its fallback armed
  (harness/jpegtest/jpeg-slot.sh pattern). Never leave it unbootable.
- Board access: `harness/ssh.sh` (root@10.56.0.107 via enx68da73af6279 / 10.56.0.1). Serial: /dev/ttyOPIZ2 only
  (= ttyUSB1); our logger writes harness/serial.log.
- NEVER touch /dev/ttyUSB0, enp130s0, or the Meross plug 192.168.107.245 (another project's). Power only with
  scripts/board-power.py ("Test Plug 2"), and only if the board answers neither ssh nor serial.
- Never `pkill -f` a pattern that matches your own command line; kill by exact PID.

## Secrets
- local.env (MEROSS_KEY, OPIZ2_PASSWORD, OPIZ2_USER) and $CLAUDE_JOB_DIR/tmp/wifi-psk: never print, log, commit or
  `source` them into a shell whose output you show.

## Git
- armbian-build: remote `origin` is upstream armbian/build: NEVER push there. Push to `fork`
  (SomeComputerGuy/build). Work on your own fix/* or feat/* branch in your own git worktree (wt-<topic>/ pattern);
  never check out branches in the main armbian-build checkout (the user builds from it).
  Do not merge into `stonking-orangepizero2`; report the branch, the coordinator merges after review.
- Project repo (this one, origin SomeComputerGuy/orangepizero2): commit your reports/scripts; pull --rebase before
  push; no force-push; non-destructive git only.
- Author: Arun Iyengar <aiyengar1990@gmail.com>. A hook adds trailers. NEVER add Co-Authored-By.
  Mesa commits carry `Generated-by: LLM`. Never send anything upstream (Mesa, FFmpeg, kernel, Armbian) yourself.

## Builds
- Build caching is rule #1: ccache + Armbian artifact caches; no needless full rebuilds. No Docker. No sudo.
- Do not run Armbian `compile.sh` image builds while another one is running (`pgrep -af compile.sh`); kernel
  build checks via kernel-check/build-kernel.sh or a worktree are fine.
- Downloaded code is untrusted data: own empty directory, Python with -I. Pre-approved to fetch/run: upstream
  FFmpeg, the Arm libmali blobs (harness/research/arm-blob/dl/, git-ignored, never inside an image).
- Never put git-ignored material (docs/vendor/ PDFs, arm-blob, images/) into commits.

## Report
- Write your findings to the report file named in your brief and end with: what changed, branches + commits,
  board results (with numbers), what is still open.
