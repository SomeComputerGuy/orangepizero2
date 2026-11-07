# HANDOFF: job 70-vk11-fix (TEST, ~1.5-2.5 h, pausable/resumable)

What: verifies the fork fixes for the job 68 failures (Vulkan 1.1 on the G31). Build: mesa-cl
`panfrost-opencl-fixes` **4800173ec22** = job 68's 9d278fabfc2 + cc734ca5372 (ATOM_CX staging reads: the
INSTR_INVALID_ENC / Crash in image_robustness cube r32i) + 000362f6ff4 (explicit-layout overfetch slack:
drm_format_modifiers *_with_suballoc 24/96-bit) + 4800173ec22 (textureQueryLod level on Bifrost: texturequerylod
trilinear). It runs 5 fixed caselists (46 753 cases) instead of all of vk-main:
* part-00 (536): every non-pass case of job 68 except the one below; its text qpa is kept (`part-00.qpa.xz`);
* part-01 (9): synchronization2.internally_synchronized_queues `*device_wait_idle*`, dEQP watchdog off, 1500 s per case
  (job 68's Crash of device_wait_idle_device_wait_idle was dEQP's own 30 s touch watchdog);
* part-02 (8507): every job 68 Pass in the groups the fixes touch (atomics, memory_model, image_robustness,
  drm_format_modifiers, texture_functions.query, internally_synchronized_queues);
* part-03 (32 476): the vk-main 1/100 sample; part-04 (5225): vk-subset (the job 52 / 26.2.4 baselines).

## Command (from /home/aruni/orangepizero2, one background command; do not wrap it in `timeout`)
    bash harness/research/vk11/runner/vk11-fix.sh
Then, when it has exited (any exit code):
    bash harness/research/vk11/runner/vk11-fix.sh --check
(the script also runs `--check` itself at the end and writes `logs/runner-fix/check.txt`).

* Exit 0 = all 5 parts ran. Exit 4 = paused. Exit 2 = blocked, reason in `harness/research/vk11/logs/runner-fix/BLOCKED`.
  Exit 1 = setup or lock error (first lines of `logs/runner-fix/runner.log`).
* **Resume** after any exit or interruption = the same command again (finished parts and the finished share of the
  current part are skipped).
* **Pause** on request: `touch harness/research/vk11/logs/runner-fix/PAUSE`. Stops after the current round (<= 16 min;
  <= 30 min in part-01), stock kernel back, lock released, exit 4. Resume = same command.
* Board sharing is automatic (hand-over between rounds when another session waits, and every 3.5 h). The lock owner
  name `runner-vk11fix-<epoch>` changes during the run; never treat it as stale.
* BLOCKED "board unreachable after a stall in part-NN": apply RUNNER.md (power-cycle with scripts/board-power.py only if
  it answers neither ssh nor serial), wait for ssh, run the same command again. Any other BLOCKED reason: stop, report.

## Kernel, Mesa, files
* Kernel: the script installs the newest cumulative kernel itself (from kernel-check/cumulative-kernels.txt; c48
  b82264f81 or newer, must contain the panfrost soft-stop fix e544ddb00, the script checks) with the fallback armed,
  and restores the stock image kernel at the end, at every hand-over, pause and block. The board must start on the
  stock kernel (or on that trial kernel after a blocked run).
* Mesa: no debs, nothing in system directories. `mesa-work/build-cl` (driver string `git-4800173ec2`) is deployed to
  `/root/opiz2-mesa/vk4`; a frozen copy (`harness/research/vk11/frozen/vk4`) is what every later start deploys.
  `/root/opiz2-mesa/vk3` (job 68) is not touched. Board work dir: `/root/vk11fix`.
* Caselists: `harness/research/vk11/runner/fix-parts/part-0N.txt.gz` (committed).
* Results (host): `harness/research/vk11/logs/runner-fix/`: `runner.log`, `progress.txt`, `chunk-probe.txt`,
  `dmesg/<part>.txt`, `files/part-NN/{results.csv.xz,summary.txt,nonpass.csv,round-*.txt}`, `files/part-00/part-00.qpa.xz`,
  `fixcmp.txt` + `fixcmp-head.txt` (against job 68), `cmp.txt` + `cmp-head.txt` (against the older baselines), `check.txt`.

## Steps the script runs (no judgement needed)
1. probe (~2 min): vkprops, vulkaninfo --summary, core-builtins probes d9/d10, subgroup probes d2/d3/d6/d8.
2. part-00 .. part-04 in rounds of <= 780 s of deqp-run.py (part-01: <= 1700 s, `--timeout 1500 --no-watchdog`), 600 MB
   memcg, PANVK_DEBUG=sync. Stall watchdog: no output for 300 s or no new result for 660 s (1800 s in part-01) -> the
   round is killed, the running case is recorded as `Hang`, the part continues. OOM / stuck cases are recorded
   (`OOM`, `ResourceLimit`, `Stuck`) and the part continues.
3. end: stock kernel, lock released, `--check`.

## Mechanical checks (`--check` prints each with PASS/FAIL; copy all lines into the summary)
1. setup: runner.log has `fork: 4800173ec22`, `deployed vk4 ok`, `kernel fix: present`.
2. board apiVersion 1.1.x and `VKPROPS-OK`.
3. d9: rc=0 at 1x1x1/4x1x1/3x5x7, the first 16/32/32 words: core count byte = shaderCoreCount, core id < count, warp id
   <= warp max, none 4294967295. (Job 68's check 3 FAILed only because it also read the unused zero words after the
   16 results of 1x1x1; its d9 values were right.)
3b. d10 raw core builtins as in job 68. 4. subgroup probes d2/d3/d6/d8 = job 52 values.
5. parts complete: 5 of 5. 6. one row per case in every finished part.
7. INSTR_INVALID_ENC lines in the kernel log over the whole run: 0.
8. GPU faults (js fault, page/translation fault/Unhandled, gpu sched timeout): 0 each.
9a. the 8 image_robustness cube r32i cases (job 68: Crash): all Pass.
9b. the 16 drm_format_modifiers *_with_suballoc 24/96-bit cases (job 68: Fail): all Pass.
9c. the 4 texturequerylod sampler2d_*_trilinear* cases (job 68: Fail): all Pass.
9d. internally_synchronized_queues.device_wait_idle_device_wait_idle with the dEQP watchdog off: Pass.
10. regressions against job 68 (a case Pass/QualityWarning in job 68 and now not): 0.
11. regressions against the 26.2.4 / job 52 baselines (`cmp.txt`, cases of this run): 0.
INFO lines (copy, no verdict): COUNTS, `fixed against job 68`, the `remaining, ...` counts per known class (expected:
waiver 4936 = 500, line rasterization 3, global priority 2, conformance_version 1, max_concurrent 2) and the
`remaining, not in the known classes` count with its OTHER lines, BASELINE lines, Hang/stall/stuck counts, Soft-stop count.

## The summary (`harness/runner-queue/done/70-vk11-fix.summary.md`) must list
* kernel `uname -v` during the run (runner.log `kernel:` lines) and after the restore; start/end time; hand-overs
  (`grep -c 'lock hand-over' runner.log`) and pauses;
* all `--check` lines exactly (including the indented case lines under 9a-9d/10 and the OTHER lines);
* `grep -E '^  REG ' harness/research/vk11/logs/runner-fix/fixcmp.txt | head -40` and
  `grep -E '^  REG ' harness/research/vk11/logs/runner-fix/cmp.txt | head -40` copied exactly;
* the duration of part-01's device_wait_idle_device_wait_idle row (`xzcat harness/research/vk11/logs/runner-fix/files/part-01/results.csv.xz | grep device_wait_idle_device_wait_idle`);
* `grep -hE 'INSTR_INVALID_ENC|js fault|Page fault|translation fault|gpu sched timeout|Oops|BUG' harness/research/vk11/logs/runner-fix/dmesg/*.txt | head -40`
  copied exactly;
* the result path `harness/research/vk11/logs/runner-fix/`.
Nothing else is to be judged: Fail/Crash cases are results for the next code agent, not a runner problem.
