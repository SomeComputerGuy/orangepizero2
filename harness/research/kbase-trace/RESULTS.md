# kbase GLES 3.2 reference traces: state (status.md work list item 8)

Updated 2026-11-06 (fix agent after runner job 16). Background, tools, port notes: ../impl-gles32-arm-traces.md.

## Current state
- Runner job **64-kbase-traces2** queued (harness/runner-queue/64-kbase-traces2.md; package runner/kbase-traces.sh v2 +
  runner/HANDOFF.md). Kernel c48 (test-cumulative b82264f81); bifrost_kbase.ko rebuilt for c48 2026-11-06 21:00
  (kernel-check/kbase-trial/build-c48.log, stamp bifrost_kbase.ko.tag "c48 ba448c35..."). No trial-kernel rebuild was
  needed: the kbase build config is unchanged, the failure was in the user-space tracer.
- Results will land in harness/research/arm-blob/traces/runner-j64/ (git-ignored). Job 16 results stay in .../runner/.

## Job 16 (c20, 2026-11-05 23:42) findings
1. kbase load PASS (BTF ok, /dev/mali0, DDK g25p0, sunxi glue 456 MHz); probe rc 0 with all 19 files.
2. **Trace segfault (TRACE-RC 139) = kbtrace.c bug.** is_mali() recorded KBT_OPEN through rec() before init() had
   opened the trace file (out == NULL): ioctl()/mmap() called init() only after the is_mali() check, so the blob's
   first ioctl on /dev/mali0 crashed in fwrite(NULL). Signature matches: no kbtrace.bin, empty info.txt. Reproduced on
   the host with the old source (path-patched: rc 139, no trace file). Fix: is_mali() runs init() under the lock
   before the first record; plus calloc-failure guards in snapshot() and no reads past a non-page-multiple region.
   Host self-test kbtrace-selftest.sh (native build, fake device via KBTRACE_DEV): PASS on the fix, FAIL on the old
   code; aarch64 kbtrace.so rebuilt (`aarch64-linux-gnu-gcc -O2 -Wall -shared -fPIC -o kbtrace.so kbtrace.c -ldl
   -lpthread`, needs GLIBC_2.38 as before) and checked under qemu-aarch64 (trace written).
3. **Every probe case rendered nothing**: `lit pixels 0/4096, glError 0x505` (GL_OUT_OF_MEMORY) for all 10 cases,
   31 dmesg lines `job status 0x58 (DATA_INVALID_FAULT)` on slot 0 (fragment), one on slot 1; no MMU faults. Not yet
   explained. Ruled out statically: DT coherency (kbase default COHERENCY_NONE, no dma-coherent), IOMMU (GPU has none).
   Hypotheses for the analysis agent: tiler heap / JIT allocation too small or failing (the blob reports tiler OOM as
   GL_OUT_OF_MEMORY and the fragment job then reads an invalid polygon list), or CPU-cached descriptor memory not
   cleaned for the GPU (port of the kbase sync path to 7.3). Job 64 adds per-context debugfs sampling during the probe
   (files/probe/kctx/: mem_jit_count/phys/vm/used, atoms, mem_allocs, mem_zones, the blob's mem_profile) and the trace
   gives the JIT_ALLOC atoms and the fragment job's FBD through kbdecode.
4. **Board reset in the restore**: serial.log shows a silent reset (U-Boot SPL 23:46:29, ext4 journal recovery) ~15 s
   after the restore's `rmmod bifrost_kbase; echo 1800000.gpu > panfrost/bind` started (23:46:14): a hard hang caught
   by the hardware watchdog (no console output at the default loglevel). It came back on the trial Image, the vdec
   fallback rebooted it to stock at 23:52. The ssh of that call had no keepalive (ssh.sh got ServerAlive only at
   06:54 on 11-06) and the call ran outside the step watchdog, so it sat until 01:16. Likely cause (unverified): kbase
   remove touching GPU registers while runtime-suspended (clocks off, prcm_ppu domain off: the glue's runtime_init
   enables clocks/reset but term only disables runtime PM). Job 64 runs it as a separate diagnostic `unload` step with
   loglevel 8 and keeps the serial.log slice (serial.txt); the restore itself is a plain reboot.
5. Check 11 printed FAIL although the stock kernel was back: the check grepped `^restored: ` but runner.log lines start
   with a timestamp. Fixed (` restored: `); on job 16's files it now PASSes.

## Harness ssh (part A, done)
- harness/ssh-opts.sh (sourced by ssh.sh and all 32 packages that had their own `K=(...)` option array, plus
  board-queue.sh, analysis/gpu/oclfix/{run-batch,run-chunk,deploy}.sh, ffmpeg/avs-board-test.sh, and the untracked
  mesa-work/tools/deploy.sh): IdentitiesOnly, BatchMode, ConnectTimeout 8, ServerAlive 15 s x 8, harness/known_hosts
  with StrictHostKeyChecking=accept-new (was `no`: a changed key was accepted silently), scp() wrapper with an overall
  timeout (SCP_TIMEOUT, default 900 s), kill_pid (TERM, KILL after 5 s) used by every stall watchdog on its own ssh PID.
  harness/ssh.sh takes SSH_TIMEOUT=<s> for one-shot commands.
- Plain `ssh root@10.56.0.107` vs harness: plain ssh used ~/.ssh/known_hosts, whose three 10.56.0.107 keys dated from
  before the 2026-11-04 reflash (Armbian regenerates host keys on the first boot; reflash.sh step 9 resets only
  harness/known_hosts, which holds the current ed25519 key; harness ssh also never checked strictly). No runner log
  ever showed a changed-key warning, so the harness entry is the current key. Replaced only the 10.56.0.107 lines in
  ~/.ssh/known_hosts with the harness entry (other hosts untouched; old file kept as ~/.ssh/known_hosts.old).
  AGENT-RULES.md / RUNNER.md: "Host key verification failed" = BLOCKED, no known_hosts edits by runners.

## Next step
Wait for job 64's summary. Then (fresh agent): if TRACE-RC 0 and decoded/ exists -> start the DATA_INVALID analysis
from files/trace/decoded (fragment job FBD, tiler context/heap pointers, JIT_ALLOC atoms) and files/probe/kctx; if the
unload INFO shows a hang, fix the kbase sunxi glue remove path (power up before term, assert reset, disable clocks)
in port-7.3.py. Item 8 step 2 (GS/tess observations) only once the blob renders.
