# Job 42-de33-writeback (DEV-length, ~5 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault) = job 41 with a faster client
Package: harness/research/de33-writeback/runner/ (script wb-job.sh, HANDOFF.md, checks there; job 42 notes at its top).
Command: `bash harness/research/de33-writeback/runner/wb-job.sh wb42`
Runs: probe, solid1 (sanity), flips-d0, flips-d4, flips-d12 (300 flips each). Checks: 0, 1, 2, 3 (solid1 only), 6 (job 42
limits: flip_rate 58.5-61.5, seq_gaps <= 3, frames_wrong 0, full_checked 6, full_mismatch 0, plus torn/bad/fence 0), 7, 8;
4 and 5 not run (job 40 PASS). Report the check 6 data keys listed in HANDOFF.md.
Why again: job 41 (c35) check 6 FAIL only on seq_gaps 298 / flip_rate ~7: all 300 captures per run correct, but the kms-wb
client compared every pixel through an uncached mapping (~120 ms per frame) and so flipped once every ~8 frames (test-client
artefact). The client now samples each row during the run and checks the last 6 captures in full.
Kernel: c35 (test-cumulative 30cee6952, Image md5 f3ec40c60dfbc0bfa94fdcf53ec9169b) or later cumulative; unchanged.
Blocked check (exit 2, BLOCKED file) as in job 40: report "not ready" with the first 30 lines of files/blocked-*/state.txt.
Display: HDMI-A-1 forced on at 1024x768@60, no sink; a missing 1024x768 mode = NOT TESTED, never FAIL (HANDOFF check 0).
Client: harness/kms-wb/out/kms-wb (rebuilt 2026-11-06, sha256 677c4b9e37eee21fbfa5e9a92abe946362a8750ee8fabb1e971da35c3e5202e3),
shipped if the board copy differs (the script does it). The board must start on the stock image kernel; HTTP server
10.56.0.1:8643 up.
Timeouts: ssh step 120 s, chunk 400 s, each client run 90 s, install 900 s, restore 600 s, scp 300 s; stall watchdog 120 s
without output. The stock kernel is restored at the end and before every lock hand-over.
Results: harness/research/de33-writeback/logs/runner-wb42/ (results.txt has the values for the checks). Jobs 40/41 logs
stay in logs/runner-wb40/, logs/runner-wb41/.
Submitted by the de33-writeback agent, 2026-11-06.
