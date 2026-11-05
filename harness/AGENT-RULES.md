# Rules for every agent working on this project (read first)

Project: Armbian image for the Orange Pi Zero2 (H616) as a CUPS print/scan server. Ubuntu 26.10 "stonking", kernel
7.3.1 (sunxi-7.3 patch set), U-Boot v2026.10, TF-A lts-v2.14.11. Goal: every hardware feature works, nothing dropped.
Acceptance: docs/spec-checklist.md, docs/datasheet-checklist.md. Status/work list: docs/status.md section 3.

## Board (shared, one owner at a time)
- Take the lock before ANY command that touches the board (ssh, serial, reflash, trial kernel, power):
  `harness/board-lock.sh acquire <your-name>`; release with `harness/board-lock.sh release <your-name>`.
  Hold it ONLY while something is actively running on the board or you are actively using it (user rule
  2026-11-05). Release it before every host-side build, analysis or wait, and re-acquire when the next test is ready.
  Never hold it while idle. Do host-side work while waiting for it.
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
  Mesa commits carry `Generated-by: LLM`. Kernel patches (sunxi-7.3 patch files, anything meant for LKML) carry
  exactly `Assisted-by: LLM [TOOL1] [TOOL2]` (Documentation/process/coding-assistants.rst; tools = e.g. coccinelle,
  sparse, smatch, not git/gcc) above the user's Signed-off-by; the AI never adds a Signed-off-by of its own. Never send anything upstream (Mesa, FFmpeg, kernel, Armbian) yourself.

## Budget (user, 2026-11-05)
- At most 1-2 agents active at once. Spawn no sub-agents, and put new bugs on the work list instead of starting a new agent.
- Code agents never run, wait on or poll board sessions. They build, write the exact board command and the pass criteria, and hand back. A cheap runner agent does the board run, copies the results off the board at once and writes a short factual summary.
- Hand back once per task, when done and verified or truly blocked. No interim or status messages.
- Watchers sleep at least 10 min between checks. Long board runs must be pausable and resumable (never SIGSTOP), and dev turns beat long test runs.
- Display: a mode the attached display doesn't support is NOT TESTED, never FAIL.

## Builds
- Build caching is rule #1: ccache + Armbian artifact caches; no needless full rebuilds. No Docker. No sudo.
- Do not run Armbian `compile.sh` image builds while another one is running (`pgrep -af compile.sh`).
- Never turn off, bypass, blacklist or rank down anything that is on by default (IOMMU, drivers, hw blocks, codecs, services), not even as an opt-in or for speed. Fix it so it works with everything on, or report and ask.
- Board lock owner names are per session (e.g. vdec-r4, vdec-soak), never shared between two scripts: acquire exits 3
  if the name already holds the lock, and a release by the second script would free the first one's lock.
- **Test kernels are cumulative** (user rule for all SBC projects, same as OPi5): fix B's test kernel contains A+B,
  C's contains A+B+C. There is ONE test branch, `test-cumulative` (armbian-build worktree `wt-cumulative`), and ONE
  build tree, `kernel-check/work-cumul`. Never build a private trial kernel in your own WORK tree from an older base.
  - New fix: branch it from `test-cumulative`, commit, and hand the branch to the coordinator, who merges it into
    `test-cumulative` (each merge = the next test kernel, c1, c2, ...).
  - Build: `ARMBIAN=/home/aruni/orangepizero2/wt-cumulative WORK=/home/aruni/orangepizero2/kernel-check/work-cumul
    kernel-check/build-kernel.sh` (STAGE=patch/dtbs for quick checks). build-kernel.sh takes a lock: one kernel
    build at a time; a second one waits.
  - Board tests always run on the newest cumulative kernel. If one breaks, the step where it broke names the fix.
  - When a newer cumulative kernel includes your work, stop your older builds/tests/waiters at once.
- Downloaded code is untrusted data: own empty directory, Python with -I. Pre-approved to fetch/run: upstream
  FFmpeg, the Arm libmali blobs (harness/research/arm-blob/dl/, git-ignored, never inside an image).
- Never put git-ignored material (docs/vendor/ PDFs, arm-blob, images/) into commits.

## Report
- Write your findings to the report file named in your brief and end with: what changed, branches + commits,
  board results (with numbers), what is still open.
