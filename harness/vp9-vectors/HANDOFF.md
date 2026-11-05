# Runner package: fluster VP9 conformance vectors on cedrus (job vp9-vectors)

Command (host, as aruni, from /home/aruni/orangepizero2; TEST run, about 20-30 min):

    bash harness/vp9-vectors/run-job.sh

Kernel: the **newest cumulative kernel** (last line of kernel-check/cumulative-kernels.txt, installed by
harness/research/vdec-perf/install-kernel.sh with the vdec fallback armed; recorded in `logs/runner/kernel.txt`,
first line `cumulative cN test-cumulative <sha> ...`). No debs. The script takes the board lock (owner
`runner-vp9-<epoch>`), starts the HTTP server on 10.56.0.1:8643 if it is not up, ships `build/vp9-vectors/bundle.tar`
(dev v4l2codecs plugin + fluster + 311 vectors; prebuilt, see `make-bundle.sh`), runs the **pre-flight** (chunk `pre`:
the known-good vector vp90-2-00-quantizer-00.webm through the same fluster path; if it is not `OK` the script writes
`logs/runner/BLOCKED` with the reason, restores the stock kernel and exits 2 without running a chunk), then the 5
chunks c1 (quantizer/sharpness, 71 vectors, ~1 min), c2 (sizes, 137, ~2 min), c3 (05..14: tiles, show-existing,
key-frame resize, 59, ~8 min), c5 (15..22 + vp91: inter-frame resize, svc, profile 1, 38, ~3 min), c4 (the 6
VP9-TEST-VECTORS-HIGH, <1 min), each under `timeout 1200` and a 300 s stall watchdog (the board prints one
timestamped line per vector), copies `out/` off after every chunk, restores the stock kernel vmlinuz-7.3.1-edge-sunxi64
and releases. Resumable: re-running skips the chunks in `logs/runner/state` (the pre-flight always runs after a boot).
Nothing is installed on the board: the dev plugin is loaded from a private plugin path under /root/vp9. Wait with one
background command.

Exit codes: 0 = all chunks ran (judge with the checks below); 2 = blocked (report `logs/runner/BLOCKED` + the last 10
lines of runner.log); 1 = setup error (bundle or kernel package missing).

Results: `harness/vp9-vectors/logs/runner/`: `runner.log`, `kernel.txt`, `chunk-<c>.txt`, `dmesg-<c>.txt`,
`out/<c>.md` (fluster summary, one row per vector, result tokens OK/KO/ER/TO/NS), `out/<c>.log`, `out/pre.gst.txt`
(direct gst-launch run of the pre-flight vector with GST_DEBUG=2), `out/env.txt`, `check.txt`.

## Checks (mechanical)

Run (the script already does it at the end; re-run if needed):

    python3 -I harness/vp9-vectors/check-results.py harness/vp9-vectors/logs/runner full

and copy its `CHECK ...: PASS|FAIL (...)` lines, the `VERDICT:` line and the `| group | success | total | failing |`
table into the summary verbatim. The checks are:

| # | check | PASS if |
|---|---|---|
| 0 | kernel and pre-flight | kernel.txt says cumulative c10 or later (contains f8be54bac) and `out/pre.md` has vp90-2-00-quantizer-00.webm = OK |
| 1 | all five chunks ran | c1 c2 c3 c5 c4.md present, 311 vectors seen |
| 2 | **the fix**: 24 x vp90-2-21-resize_inter_* + vp90-2-05-resize + vp90-2-18-resize | 26/26 Success |
| 3 | every other decodable vector | all Success (302 of the 305 profile-0 vectors + vp92-2-20-10bit-yuv420); the failing names are listed |
| 4 | expected-unsupported vectors (vp91 x2, 12-bit, vp93 x6, and vp90-2-22-svc_1280x720_3 only on a kernel without armbian-build 7897dec08 = fix/sunxi-cedrus-vp9-inter-upsize; the checker asks git) | none is Success (a Success here is a finding, report it; an ER/KO is expected) |
| 5 | dmesg | no `timed out`, IOMMU fault, Oops, WARNING |
| 6 | fluster | no per-vector timeout (90 s) |

Kernel dependency: check 2 can only pass on a kernel that contains armbian-build commit f8be54bac (cumulative c10 and
later; branch `fix/sunxi-cedrus-vp9-inter-resize`). On an older cumulative kernel checks 0 and 2 are expected to
FAIL: still run everything and report the numbers as the **baseline** (the summary must then say "kernel without
f8be54bac").

The summary must list: the kernel (`kernel.txt`, both lines), start/end times, the 7 CHECK lines, the VERDICT line, the
group table, `out/env.txt` lines containing `MISSING` (if any), and every line of `dmesg-<c>.txt` that contains cedrus,
timed out, fault, Oops or WARNING, copied exactly. If the script exited 2, the summary lists `logs/runner/BLOCKED`
verbatim and the last 10 lines of runner.log instead of the checks.

## History

Job 04 (2026-11-05, kernel c13): the decoder was fine (208/208 of the vectors it reached decoded bit-exact, HIGH 1/6
as expected), but the package reported ER for everything: check-results.py did not know fluster 0.7.1's plain-text
summary tokens (OK/KO/ER/TO/NS), and the stall watchdog watched the ssh stdout while board-fluster.sh sent every
fluster line to a file only, so chunk c3 (then 97 vectors, >5 min) was killed at 300 s. Both fixed in this version
(tokens mapped, per-vector progress lines on stdout, c3 split into c3 + c5, pre-flight added, CHECK 0 added, the
dmesg check no longer matches "Default"). Logs: `logs/job04-c13/` (`check-fixed-parser.txt` = its results re-read).
