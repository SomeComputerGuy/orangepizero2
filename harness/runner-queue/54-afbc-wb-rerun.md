# Job 54-afbc-wb-rerun (TEST, ~20 min, 10 cases + 2 reboots, resumable between cases, fails fast on Oops/WARN/IOMMU fault)
Package: harness/research/afbc-wb/runner/ (script afbc-wb-job.sh, HANDOFF.md with checks 0-7 and the verdict rules).
Command: `bash harness/research/afbc-wb/runner/afbc-wb-job.sh j54`
What: rerun of job 53 (same package, same streams) on the kernel with the cedrus H.265 AFBC fix. Job 53 showed the
H.265 AFBC surface 4 lines lower than the linear picture; the kernel now reports that offset (V4L2 compose rectangle)
and the client starts the plane window there. New: check 7 (`pic_offset`), informational case real-vp9p0-y4.
Kernel: c39 = test-cumulative d67f25b42, Image md5 b74f1af053066a48ab7ac8a5bae26005 (or a later cumulative tag); must contain 30706dcc8 (DE33
writeback) and 8b1f787fe (cedrus compose fix), checked by the script. Installed and restored by the script.
Client: harness/afbc-wb/out/afbc-wb (rebuilt 2026-11-06 against FFmpeg with the compose support, sha256 10ccf7c0cb028a0228e5d61c05ca3ff1e83e109cf67dffb528a22fc6749b209a);
the script ships it when the board copy differs. Streams: kernel-check/vdec-serve/afbc-wb/ (unchanged).
Display: HDMI-A-1 forced on at 1024x768@60, no sink; mode missing = NOT TESTED, never FAIL.
Results: harness/research/afbc-wb/logs/runner-j54/ (results.txt holds the check values). Commit the text logs only,
never files/*/dump/*.cap.
Summary: as listed in HANDOFF.md "Summary must list". Submitted by the afbc-wb agent, 2026-11-06.
