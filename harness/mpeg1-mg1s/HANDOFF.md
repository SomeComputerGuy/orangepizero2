# Runner package: MPEG-1 as V4L2_PIX_FMT_MPEG1_SLICE ('MG1S') on cedrus (job mpeg1-mg1s)

Command (host, as aruni, from /home/aruni/orangepizero2; TEST run, about 25-35 min of board time):

    bash harness/mpeg1-mg1s/run-job.sh

What it does, in order (every result is written on the host under `harness/mpeg1-mg1s/logs/runner/` as it is produced):

1. Refuses to start (exit 2, `logs/runner/BLOCKED`) unless the **newest cumulative kernel** (last line of
   kernel-check/cumulative-kernels.txt) contains armbian-build commit 8140b4eeb241ea13b872edbe93dadac618de2130
   (branch `fix/sunxi-cedrus-mpeg1-mg1s`: MG1S uAPI + cedrus). The coordinator merges that branch into
   `test-cumulative` and builds it (harness/cumul-build.sh cN) before this job can run.
2. Takes the board lock (owner `runner-mg1s-<epoch>`), starts the HTTP servers 10.56.0.1:8643 (kernel/binary shipping)
   and :8644 (test streams, kernel-check/legacy-serve) if they are not up, ships the static board FFmpeg
   `kernel-check/ffmpeg-deb/build-mg1s/ffmpeg` (shared v4l2-request set, patches/ffmpeg 0001-0312 incl. the MG1S 0304
   and the D-picture probe 0309) to `/root/mg1s/ffmpeg`. Nothing is installed system-wide.
3. Chunk `stock`, on the **stock image kernel** (the board must be on vmlinuz-7.3.1-edge-sunxi64 at start): coded formats
   of every video node (`fmts-stock.txt`), the software-fallback probe (`swfb-stock.tsv`: MPEG-1 with
   `-hwaccel v4l2request` but no hw output format vs pure software, cedrus IRQ delta) and a `v4l2-compliance` baseline
   (`compliance-stock.txt`).
4. Installs the newest cumulative kernel with the vdec fallback armed (harness/research/vdec-perf/install-kernel.sh),
   reboots, verifies the Image md5, records `kernel.txt`, then runs the chunks `fmts` (`fmts-test.txt`,
   `framesizes-test.txt`), `compliance` (`compliance-test.txt`, plus `compliance-test-patched.txt` if
   /root/v4l2c/v4l2-compliance exists on the board), `md5` (ccm1 framemd5 vs host software, `md5/summary.tsv`),
   `dpic` (tcela-18, 31 D-pictures, vs the exact DC reference legacy-dec/m1-dpic.py, `dpic.txt`), `raw` (IDCT envelope of
   MEI.stream16.long, MEI.stream16v2, tcela-16, tcela-19 and the generated 1080p30, `raw/raw.tsv`), `mpeg2` (MG2S
   regression: tcela-15, mcp10ccett, `mpeg2/summary.tsv`); `dmesg-<chunk>.txt` after every chunk. Each chunk runs under
   a timeout (600-1500 s); the longest chunk (raw) takes about 10 min.
5. Restores the stock kernel, releases the lock, runs `check-results.sh` into `check.txt`.

Resumable: re-running the same command skips the chunks listed in `logs/runner/state` (the kernel is re-installed after a
restore). Between chunks the lock is handed over (stock kernel restored first) if another session waits in
harness/queue/board.wait. Wait for the script with one background command; do not re-read logs in between.

Exit codes: 0 = all chunks ran (judge with the checks below); 2 = blocked (report `logs/runner/BLOCKED` and the last 10
lines of `logs/runner/runner.log`); 1 = setup error (kernel package, board FFmpeg or a test stream missing).

## Checks (mechanical)

    bash harness/mpeg1-mg1s/check-results.sh harness/mpeg1-mg1s/logs/runner

(already run by the script; `logs/runner/check.txt`). Copy its `CHECK n ...: PASS|FAIL|SKIP (...)` lines and the
`VERDICT:` line into the summary verbatim. The checks:

| # | check | PASS if |
|---|---|---|
| 0 | kernel | `kernel.txt` names a cumulative kernel (`cumulative cN ...`); run-job.sh only installs one that contains 8140b4eeb |
| 1 | stock formats | `fmts-stock.txt` recorded; it says whether the stock kernel enumerates MG1S (fact, both outcomes PASS) |
| 2 | **probe picks software without MG1S** | stock kernel without MG1S: both `swfb-stock.tsv` lines `same=1` (hwaccel run == software md5) and `irqs=0`. SKIP if the stock kernel already enumerates MG1S |
| 3 | **MG1S enumerated** | `fmts-test.txt`: exactly one MG1S line, on the node with `driver=cedrus`, text `'MG1S' (MPEG-1 Parsed Slice Data, compressed)` |
| 4 | v4l2-compliance | `Total for cedrus device ...: Failed: N` on the test kernel <= N on the stock kernel (same binary), and no `fail:` line mentioning MPEG/MG1S |
| 5 | **ccm1 md5** | `md5/summary.tsv` m1-ccm1: `match=129/129` and `irqs=129` (hardware decoded every frame, bit-exact) |
| 6 | **tcela-18 D-pictures in hardware** | `dpic.txt`: `frames=31 exact=31`, `irqs=31`, and the FFmpeg line `D-pictures are decoded by the device` |
| 7 | IDCT envelope | `raw/raw.tsv`: all frames (61, 4, 31, 31, 300), irqs == frames, HW max abs diff to the closest software IDCT <= max(2, simple~int envelope), per stream |
| 8 | MPEG-2 regression | `mpeg2/summary.tsv`: m2-tcela-15 `match=61/61 irqs=61`, m2-mcp10ccett `match=4/4 irqs=4` |
| 9 | dmesg | no `timed out`, fault, Oops, WARNING, `bug:` in `dmesg-*.txt` |

Reference (kernel 4321861ff + the flag-only uAPI, 2026-11-03, harness/research/impl-legacy-decode.md section 6.1): ccm1
129/129 bit-exact, tcela-18 31/31 bit-exact, MEI/tcela-16/19 max 2 within envelope 2-3, 1080p30 max 3 within 4.

The summary must list: both lines of `kernel.txt` and the line of `kernel-stock.txt`, start/end times (`runner.log`),
the 10 CHECK lines and the VERDICT line, `swfb-stock.tsv` and `fmts-test.txt` verbatim, the `Total for` lines of
`compliance-stock.txt`/`compliance-test.txt` (and `-patched` if non-empty), `dpic.txt`, `raw/raw.tsv` cut to 200
columns, `md5/summary.tsv`, `mpeg2/summary.tsv`, and every line of `dmesg-*.txt` containing timed out, fault, Oops,
WARNING or bug, copied exactly. If the script exited 2: `logs/runner/BLOCKED` verbatim and the last 10 lines of
runner.log instead of the checks.

FFmpeg deb: `scripts/build-media-debs.sh ffmpeg` (REV 3, log out/debs-media-build-opiz2.3.log) was started by the
code agent on 2026-11-05; the job does not need the deb (it uses the static binary). The summary states whether
`out/debs-media/ffmpeg_8.1.2-2ubuntu2+opiz2.3_arm64.deb` exists (fact only).
