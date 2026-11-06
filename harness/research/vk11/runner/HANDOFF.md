# HANDOFF: job 68-vk11-main (TEST, long: full dEQP-VK vk-main at Vulkan 1.1, ~16-22 h, pausable/resumable)

What: the fork panvk now reports **Vulkan 1.1** on the G31 (mesa-cl `panfrost-opencl-fixes` **9d278fabfc2**:
backport of Mesa 0dbf521d381 "panvk: enable Vulkan 1.1 and subgroups on Bifrost" + core-builtins fix ded6ccea0bc +
lazy JM descriptor pool 039c393b7fb (chunk 1 OOM) + Bifrost warp count 9d278fabfc2 (chunk 1 d9 FAIL), on top of
ab1caa7378f/0e274280595 from job 52).
**Restart 2026-11-06** after chunk 1 (BLOCKED, build ded6ccea0bc): the script itself starts clean, nothing to do by
hand: it removes a stale frozen copy, deploys the new build, wipes the board's old `/root/vk11/res` (stamp file
`res/FORK`); the host results of chunk 1 are in `logs/runner-ded6ccea0bc/` (moved there already).
This job runs all 3 247 552 cases of the vulkan-cts-1.4.6.2 vk-main on the board,
with the driver's own apiVersion (no MESA_VK_VERSION_OVERRIDE), and compares them with every earlier baseline.

## Command (from /home/aruni/orangepizero2, one background command; do not wrap it in `timeout`)
    bash harness/research/vk11/runner/vk11-main.sh
Then, when it has exited (any exit code):
    bash harness/research/vk11/runner/vk11-main.sh --check
(the script also runs `--check` itself at the end and writes `logs/runner/check.txt`).

* Exit 0 = all 64 parts ran. Exit 4 = paused (see below). Exit 2 = blocked, reason in
  `harness/research/vk11/logs/runner/BLOCKED`. Exit 1 = setup or lock error (first lines of `logs/runner/runner.log`).
* **Resume** after any exit or interruption = the same command again. Finished parts and the finished share of the
  current part are skipped (`logs/runner/state`, the board's `/root/vk11/res/part-NN/shard-0.csv`).
* **Pause** on request (coordinator / a dev turn): `touch harness/research/vk11/logs/runner/PAUSE`. The script stops
  after the current round (<= 16 min), puts the stock kernel back, releases the lock and exits 4. Resume = same command.
  `--max-hours H` does the same after H hours, if the coordinator wants the run in slices.
* Board sharing is automatic: between rounds, if another session waits in `harness/queue/board.wait`, and every 3.5 h
  in any case, the script restores the stock kernel, releases the lock, re-acquires it (queue order) and continues.
  Expect the lock owner name `runner-vk11-<epoch>` to change during the run; never treat it as stale.
* BLOCKED "board unreachable after a stall in part-NN": the board answers neither ssh after 10 min. Apply RUNNER.md
  (power-cycle with scripts/board-power.py only if it answers neither ssh nor serial), wait until ssh answers, then run
  the same command again. The script accepts the board on the stock kernel or on the trial kernel it installed. Any
  other BLOCKED reason: stop and report it.

## Kernel, Mesa, files
* Kernel: the script installs the newest cumulative kernel itself (c48 b82264f81 at submission; it must contain the
  panfrost soft-stop fix e544ddb00, the script checks) with the fallback armed, and restores the stock image kernel
  (vdec-perf/restore-kernel.sh) at the end, at every hand-over, pause and block. The board must start on the stock
  kernel (or on that trial kernel, after a blocked run).
* Mesa: no debs, nothing in system directories. The fork build `mesa-work/build-cl` (driver string `git-9d278fabfc`)
  is deployed to `/root/opiz2-mesa/vk3`; after the first deploy a frozen copy (`harness/research/vk11/frozen/vk3`)
  is what every later start deploys, so a rebuild of build-cl during the run cannot mix builds. A frozen copy of
  another commit is removed at start (log line `stale frozen copy removed`), and host/board results of another commit
  are moved away/removed (`results of fork ... moved`, `board results of another build removed`): builds never mix.
* The 64 part caselists are prebuilt in `logs/runner/parts/` (git-ignored); the script copies one part at a time to
  the board and deletes it there when the part is done.
* Results (host): `harness/research/vk11/logs/runner/`: `runner.log`, `progress.txt` (one line per round),
  `chunk-probe.txt`, `dmesg/<part>.txt`, `files/part-NN/{results.csv.xz,summary.txt,nonpass.csv,round-*.txt}`,
  `cmp.txt` (full comparison), `cmp-head.txt`, `check.txt`. The per-case results (`results.csv.xz`) are git-ignored.

## Steps the script runs (no judgement needed)
1. probe (~2 min): `vkprops` (apiVersion, 1.1 properties/features, vkCreateDevice with all of them), `vulkaninfo
   --summary` if present, the ARM core-builtins probe d9 at 3 local sizes, the raw core-builtins probe d10 at 4
   dispatches, the job-52 subgroup probes d2/d3/d6/d8.
2. part-00 .. part-63: rounds of <= 780 s of deqp-run.py (`--jobs 1 --timeout 300`, 600 MB memcg, PANVK_DEBUG=sync, the
   Mesa CI env). Every round: progress line, copy-off of the part's results, kernel log lines. Stall watchdog: no
   output for 300 s or no new result for 660 s -> the round is killed, the case that was running is recorded as `Hang`
   and the part continues. Memory: the memcg scope has OOMPolicy=continue; an OOM-killed case is retried once, then
   recorded as `OOM`. A round without a new row: the 2nd such round on the same case records it as `ResourceLimit`
   (OOM kill in that round) or `Stuck` (runner.log `STUCK-MARKED`) and the part continues. Only if 4 rounds in a row
   still add no row -> BLOCKED (should not happen).
3. end: stock kernel, lock released, `--check`.

## Mechanical checks (`--check` prints each with PASS/FAIL; copy all lines into the summary)
1. setup: runner.log has `fork: 9d278fabfc2`, `deployed vk3 ok`, `kernel fix: present`.
2. board apiVersion is 1.1.x and `VKPROPS-OK` (device created with every 1.0 + 1.1 core feature it reports).
3. ARM core builtins probe d9: rc=0 at 1x1x1, 4x1x1, 3x5x7, >= 16 values each, none 4294967295 (id > max), the core-count
   byte equals shaderCoreCount.
3b. raw core builtins probe d10 (1x1x1, 4x1x1, 3x5x7 at 4x2x2 groups, 64x1x1 at 16x8x1): rc=0, no WarpIDARM above
   WarpMaxIDARM and no CoreIDARM >= CoreCountARM in any invocation, WarpMaxIDARM = shaderWarpsPerCore - 1, CoreCountARM
   = shaderCoreCount, invocation counts 16 / 64 / 1680 / 8192 (`--check` prints one `d10` line per dispatch: copy them).
4. subgroup probes d2/d3/d6/d8 at 4x1x1 give the job-52 values (15.., 42 13 13 13.., 260.., 1..).
5. parts complete: 64 of 64.
6. every finished part's results.csv has one row per case (+ header).
7. INSTR_INVALID_ENC lines in the kernel log over the whole run: 0.
8. GPU faults over the whole run (js fault, page/translation fault/Unhandled, gpu sched timeout): 0 each. FAIL lists the
   parts whose `dmesg/<part>.txt` has them.
9. regressions: `cmp.txt` "REGRESSIONS (union over baselines)" = 0. A regression = Pass in a baseline (vk-main 1/100 at
   1.0 and at override 1.1, vk-subset at 1.0 and override 1.1 on system Mesa 26.2.4, job 52's fork vk-subset) and now not
   Pass/QualityWarning/CompatibilityWarning.
INFO lines (copy, no verdict): total COUNTS (Pass/Fail/Crash/Timeout/Hang/NotSupported/...), one BASELINE line per
baseline (REGRESSIONS/FIXED), Hang rows and stalls, stuck-case rows (`STUCK-MARKED`), Soft-stop count, BLOCKED reason.

## The summary (`harness/runner-queue/done/68-vk11-main.summary.md`) must list
* kernel `uname -v` during the run (from runner.log `kernel:` lines) and after the restore; start and end time; number of
  hand-overs (`grep -c 'lock hand-over' runner.log`) and pauses;
* all `--check` lines;
* `grep -E '^  REG ' harness/research/vk11/logs/runner/cmp.txt | head -60` copied exactly (the regression list);
* `sed -n '/^NON-PASS (not/,/^NON-PASS list/p' harness/research/vk11/logs/runner/cmp.txt | head -60` (non-pass by group);
* `grep -hE 'INSTR_INVALID_ENC|js fault|Page fault|translation fault|gpu sched timeout|Oops|BUG' harness/research/vk11/logs/runner/dmesg/*.txt | head -40`
  copied exactly;
* the result path `harness/research/vk11/logs/runner/`.
Nothing else is to be judged: Fail/Crash/Timeout cases are results for the next code agent, not a runner problem.
