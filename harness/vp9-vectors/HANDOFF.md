# Runner package: fluster VP9 conformance vectors on cedrus (job vp9-vectors)

Command (host, as aruni, from /home/aruni/orangepizero2; TEST run, about 20-40 min):

    bash harness/vp9-vectors/run-job.sh

Kernel: the **newest cumulative kernel** (last line of kernel-check/cumulative-kernels.txt, installed by
harness/research/vdec-perf/install-kernel.sh with the vdec fallback armed; recorded in `logs/runner/kernel.txt`).
No debs. The script takes the board lock (owner `runner-vp9-<epoch>`), starts the HTTP server on 10.56.0.1:8643 if
it is not up, ships `build/vp9-vectors/bundle.tar` (dev v4l2codecs plugin + fluster + 311 vectors; prebuilt, see
`make-bundle.sh`), runs 4 chunks (c1 quantizer/sharpness 71 vectors, c2 sizes 137, c3 the rest 97, c4 the 6
VP9-TEST-VECTORS-HIGH) each under `timeout 1200` and a 300 s stall watchdog, copies `out/` off after every chunk,
restores the stock kernel vmlinuz-7.3.1-edge-sunxi64 and releases. Resumable: re-running skips the chunks in
`logs/runner/state`. Nothing is installed on the board: the dev plugin is loaded from a private plugin path under
/root/vp9. Wait with one background command.

Exit codes: 0 = all chunks ran (judge with the checks below); 2 = blocked (report `logs/runner/BLOCKED` + the last 10
lines of runner.log); 1 = setup error (bundle or kernel package missing).

Results: `harness/vp9-vectors/logs/runner/`: `runner.log`, `kernel.txt`, `chunk-c<N>.txt`, `dmesg-c<N>.txt`,
`out/c<N>.md` (fluster summary, one row per vector), `out/c<N>.log`, `out/env.txt`, `check.txt`.

## Checks (mechanical)

Run (the script already does it at the end; re-run if needed):

    python3 -I harness/vp9-vectors/check-results.py harness/vp9-vectors/logs/runner

and copy its `CHECK ...: PASS|FAIL (...)` lines, the `VERDICT:` line and the `| group | success | total | failing |`
table into the summary verbatim. The checks are:

| # | check | PASS if |
|---|---|---|
| 1 | all four chunks ran | c1..c4.md present, 311 vectors seen |
| 2 | **the fix**: 24 x vp90-2-21-resize_inter_* + vp90-2-05-resize + vp90-2-18-resize | 26/26 Success |
| 3 | every other decodable vector | all Success (302 of the 305 profile-0 vectors + vp92-2-20-10bit-yuv420); the failing names are listed |
| 4 | expected-unsupported vectors (vp91 x2, vp90-2-22-svc_1280x720_3, 12-bit, vp93 x6) | none is Success (a Success here is a finding, report it; a Fail is expected) |
| 5 | dmesg | no `timed out`, IOMMU fault, Oops, WARNING |
| 6 | fluster | no per-vector timeout (90 s) |

Kernel dependency: check 2 can only pass on a kernel that contains armbian-build commit f8be54bac
(branch `fix/sunxi-cedrus-vp9-inter-resize`, patch media-cedrus-decode-smaller-VP9-inter-frames-in-place). On an
older cumulative kernel check 2 is expected to FAIL: still run everything and report the numbers as the **baseline**
(the summary must then say "kernel without f8be54bac").

The summary must list: the kernel (`kernel.txt`), start/end times, the 6 CHECK lines, the VERDICT line, the group
table, `out/env.txt` lines containing `MISSING` (if any), and every line of `dmesg-c<N>.txt` that contains cedrus,
timed out, fault, Oops or WARNING, copied exactly.
