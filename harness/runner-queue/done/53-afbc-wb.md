# Job 53-afbc-wb (TEST, ~20 min, 9 cases + 2 reboots, resumable between cases, fails fast on Oops/WARN/IOMMU fault)
Package: harness/research/afbc-wb/runner/ (script afbc-wb-job.sh, HANDOFF.md with checks 0-6 and the verdict rules).
Command: `bash harness/research/afbc-wb/runner/afbc-wb-job.sh j53`
What: bit-exact check of the cedrus AFBC capture without the GPU (job 51: this Mali-G31 has no AFBC). Each frame is
shown 1:1 on the DE33 VI plane (FBD decompresses AFBC) and captured with the DE33 writeback connector (jobs 40-42 PASS);
the AFBC decode (AS12/AS01) is compared with the linear decode (NV12/P010) of the same stream, same plane setup.
Pass criteria on synthetic lossless 1024x768 streams (HEVC 8/10-bit, VP9 P0/P2): linear decode == source md5s, AFBC
captures pixel-identical to the linear ones away from chroma-tile edges (check 3). 4K real streams are informational.
Kernel: the NEWEST cumulative tag (c38 = test-cumulative 76bd27766, Image md5 f7fc82bd55173cf0ddd56a15ff9a72d6, or
later); must contain the DE33 writeback commit 30706dcc8; installed and restored by the script (install-kernel.sh /
restore-kernel.sh). No kernel change for this job.
Client: harness/afbc-wb/out/afbc-wb (built 2026-11-06, sha256 a0129b60ff8e704d538000c8a6698cf5dc069033b30aadcd765634ff88540a1f); streams in
kernel-check/vdec-serve/afbc-wb/ (mkstreams.sh). The script ships both when the board copy differs.
Display: HDMI-A-1 forced on at 1024x768@60, no sink; mode missing = NOT TESTED, never FAIL.
Results: harness/research/afbc-wb/logs/runner-j53/ (results.txt holds the check values). Commit the text logs only,
never files/*/dump/*.cap.
Summary: as listed in HANDOFF.md "Summary must list". Submitted by the afbc-wb agent, 2026-11-06.
