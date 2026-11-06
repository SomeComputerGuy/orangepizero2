# Job 41-de33-writeback (DEV-length, ~5 min, 1 chunk, resumable, fails fast on Oops/WARN/IOMMU fault) = flips part of job 40
Package: harness/research/de33-writeback/runner/ (script wb-job.sh, HANDOFF.md, checks there; job 41 notes at its top).
Command: `bash harness/research/de33-writeback/runner/wb-job.sh wb41`
Runs: probe, solid1 (sanity), flips-d0, flips-d4, flips-d12 (300 flips each). Checks: 0, 1, 2, 3 (solid1 only), 6, 7, 8;
4 and 5 not run (job 40 PASS).
Why again: job 40 (c35) check 6 FAIL, the kms-wb client segfaulted (rc 139) on the first flip event in all three flips runs:
it passed NULL as the atomic commit's page-flip event user data and its event handler dereferenced it. Test-client bug, not
the kernel (the commit, the flip event and the writeback fence all arrived: 1 job done, 0 failed). Fixed in harness/kms-wb.
Kernel: c35 (test-cumulative 30cee6952, Image md5 f3ec40c60dfbc0bfa94fdcf53ec9169b) or later cumulative; unchanged.
Blocked check (exit 2, BLOCKED file) as in job 40: report "not ready" with the first 30 lines of files/blocked-*/state.txt.
Display: HDMI-A-1 forced on at 1024x768@60, no sink; a missing 1024x768 mode = NOT TESTED, never FAIL (HANDOFF check 0).
Client: harness/kms-wb/out/kms-wb (rebuilt 2026-11-06, sha256 a30d348af2a096176449a5a7e40633fd9b2931f573b93a763796ac9c4421d0d4),
shipped if the board copy differs (the script does it). The board must start on the stock image kernel; HTTP server
10.56.0.1:8643 up.
Results: harness/research/de33-writeback/logs/runner-wb41/ (results.txt has the values for the checks). Job 40's logs stay
in logs/runner-wb40/.
Submitted by the de33-writeback agent, 2026-11-06.
