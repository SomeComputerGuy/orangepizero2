# vdec runner jobs (t1f9, afbc, soak3, t1fix): handoff

One script runs all four: `harness/research/vdec-perf/runner/vdec-job.sh <job>`. It handles the board lock (a fresh
owner `runner-<job>-<epoch>` per acquire), installs the **newest** cumulative kernel (last line of
kernel-check/cumulative-kernels.txt, c38 or later on 2026-11-06; for every job, since install-kernel.sh always installs
the newest tag; the Image md5 check uses that tag; t1fix additionally needs fa73c3e5e, see below; all from
kernel-check/vdec-serve) with the vdec fallback armed, runs chunks of 15 min or
less under a stall watchdog, copies the results off after every chunk, restores the stock kernel
vmlinuz-7.3.1-edge-sunxi64 and releases the lock. It hands the lock over between chunks if another session is waiting.
It is resumable: re-running the same command skips the chunks listed in `logs/runner-<job>/state`. No debs are needed.
The HTTP server on 10.56.0.1:8643 (kernel-check/vdec-serve) must be up; the script fails at its first download if it
is not.

Results: `harness/research/vdec-perf/logs/runner-<job>/`. These are `runner.log`, `chunk-<c>.txt`, `dmesg-<c>.txt`,
`files/` and `BLOCKED` (present only when the job was blocked).

Exit codes:
- 0 = all chunks ran; judge the result with the checks below.
- 2 = blocked: report the content of `BLOCKED` together with the last 10 lines of runner.log.
- 1 = setup or lock error.

## Job t1f9: test1.avs2 data collection (about 10 min, 1 chunk)
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh t1f9`
Checks, all on `logs/runner-t1f9/chunk-1.txt`:
- PASS if `grep -c ROUND-DONE` = 1.
- PASS if the line `[count] frames 2096 differing N` is present. Report N. It is data, not a pass/fail value (it was 72
  on c9).
- PASS if `timeouts 0` appears on both the first and the last `timeouts` line.
- PASS if `files/t1.got` has 2096 lines and `files/t1-sel.yuv` is 6148800 bytes.

The summary must list: N, the `[differing frames]` line (copied exactly), the `[seq]` lines, the `frame NNN:` lines,
and dmesg-1.txt.

## Job afbc: AFBC capture md5 via the GPU (about 40 min, 5 chunks: vp9p2 hevc10 avs2 hevc8 vp9p0)
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh afbc`

Precondition: the Mesa fork must be at /root/opiz2-mesa/main on the board.
- If any chunk prints `[env] BLOCKED`, stop and report "afbc blocked: Mesa fork missing on the board". Do not count
  this as a FAIL.
- On c9 (2026-11-05) the system Mesa 26.2.4 was used instead, and every EGL import failed with 0x3009.

Checks, per `chunk-<case>.txt`:
- PASS if the `[gl] GL_RENDERER` line does not contain `Mesa 26.2.4-1ubuntu1`, i.e. the system Mesa is not in use.
- PASS if the line `quick: ok=1` is present. If it is `ok=0`, report every case as INCONCLUSIVE, not FAIL.
- In the line `[<case>] dec rc ... | done: F frames, C compared, M matched, first mismatch X`:
  - PASS if C = M, C = F and F > 0.
  - Otherwise FAIL; report X.
- `dec rc 141` is harmless.

The summary must list the per-case F/C/M/X table, the `[<case>]` lines, and dmesg-<case>.txt. Dumps of any mismatch
are in files/.

## Job soak3: soak of 70 min or more at 624 MHz with VDD-SYS at its floor (8 chunks, one iteration of about 9 min each)
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh soak3`

Each chunk runs these back to back:
- VP9 P2 P010 md5;
- H.265 Main10 P010 md5;
- AVS2 8-bit md5;
- AVS2 10-bit md5;
- the VP9 AFBC and AVS2 AFBC load runs.

Checks:
- PASS if every `chunk-<n>.txt` has one `[soak]` line, `ROUND-DONE`, and no `download failed`.
- From the `[soak]` lines (`[soak] Ns iterations=I runs ok=O fail=X max-temp T vdd-gpu-sys V timeouts Z`):
  - PASS if the sum of N is 3600 or more;
  - PASS if X = 0 in every chunk;
  - PASS if Z = 0 in every chunk;
  - PASS if T < 85000 in every chunk;
  - PASS if V = 900000 in every chunk.
- PASS if no `[FAIL` line appears in any chunk (copy any `[FAIL` lines exactly if there are some).

The summary must list one row per chunk (N, I, O, X, T, V, Z), plus the IOMMU, timeout and fault lines from the
dmesg-<n>.txt files.

## Job t1fix: test1.avs2 bit-exact after the AVS2 order-count fix (about 8 min, 1 chunk)
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh t1fix`

Kernel: the newest cumulative kernel (last line of kernel-check/cumulative-kernels.txt). It must contain
fix/sunxi-avs2-poc-base (commit fa73c3e5e, merged into test-cumulative by the coordinator). The script checks this
itself and exits 2 with `BLOCKED` ("does not contain fix/sunxi-avs2-poc-base") if the newest kernel predates the merge:
report that as "not ready: kernel without the fix", do not count it as FAIL.

Checks, all on `logs/runner-t1fix/chunk-1.txt`:
- PASS if `grep -c ROUND-DONE` = 1.
- PASS if the line `[count] frames 2096 differing 0` is present (per-frame md5 of test1.avs2 against davs2). Any other
  N is FAIL; report N and the `[differing frames]` line.
- PASS if each of the five lines `[test1.avs2]`, `[main-2160p-ra.avs2]`, `[cctv4k-10bit.avs2]`, `[main-1080p-ra.avs2]`,
  `[BQSquare_416x240_60_ra.avs2]` contains ` PASS ` (whole-stream md5 equal to the reference). Each FAIL is a
  regression; report the line.
- PASS if the first `timeouts` line (`kernel ... timeouts N`) and the last line `timeouts N` both show 0, and every
  `[<stream>]` line shows `new-timeouts 0`.
- PASS if `files/t1.got` has 2096 lines.

The summary must list: the `[seq]` line, the `[count]` line, the `[differing frames]` line (copied exactly), the five
`[<stream>]` lines, the `timeouts` lines, and dmesg-1.txt.

## Job avs2q: FFmpeg AVS2 request queueing (patches/ffmpeg 0313) md5 + starved-gap check (about 10 min, 1 chunk)
Command: `bash harness/research/vdec-perf/runner/vdec-job.sh avs2q`

Kernel: the newest cumulative kernel (last line of kernel-check/cumulative-kernels.txt; c15 fa73c3e5e or later). No debs:
the board downloads the dev binary `ffmpeg-avs2q` (kernel-check/vdec-serve/avs2, sha256 starts 01a23cd93c89daf9 = the
shared series head + 0313) and `refs-8bit.md5` (runner/refs-8bit.md5) from 10.56.0.1:8643. Results:
`logs/runner-avs2q/chunk-1.txt`, per-frame md5 lists in `files/`.

Checks, all on `chunk-1.txt`:
- PASS if `grep -c ROUND-DONE` = 1 and no `download failed` line.
- PASS if the `[binary]` line shows `sha256 01a23cd93c89daf9` and `avs2-decoder 1`.
- PASS if both `[gaps cctv4k-10bit holdback rN]` lines show `gap starved n=X` with X <= 3 (aq1: 1 per run). The
  `[gaps cctv4k-10bit lowdelay r1]` line is data (aq1: n=151); report its X too.
- PASS if the `[md5 cctv4k-10bit]` line contains ` PASS ` (Main10 P010, ref be9985dea38abffc850d73024165c990).
- PASS if `grep -c '^\[md5 .*\] PASS '` = 18 (cctv4k + 17 8-bit streams) and `grep -c '^\[md5 .*\] FAIL'` = 0. Each
  FAIL line is a regression; copy it. (Job 12's 4 `download failed` lines with cut stream names were ffmpeg reading
  the stream list from the loop's stdin; fixed with -nostdin, 10 of the 10 streams that ran passed.)
- PASS if the first line (`kernel ... timeouts N`) and the last `timeouts N` line both show 0, and every `[md5 ...]`
  line shows `new-timeouts 0`.
- PASS if dmesg-1.txt has no `timed out` line. IOMMU `Page fault` lines are reported, not a FAIL of this job (open item 4).

The summary must list: the `kernel` line, the `[binary]` line, the three `[gaps ...]` lines (copied exactly), the
`[md5 ...]` PASS/FAIL counts and any FAIL lines, the `timeouts` lines, and dmesg-1.txt.
