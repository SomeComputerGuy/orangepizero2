# Job 24-gst-mpeg1-2 (DEV, ~15-20 min incl. two reboots)
Package: harness/gst-mpeg1/HANDOFF.md (command `bash harness/gst-mpeg1/run-job.sh`, checks 0-9 there).
Rerun of 12-gst-mpeg1 (checks 2-8 passed: MPEG-1 MG1S in hardware works). Check 9 matched "default" for "fault"
(fixed: word match). Check 1 (software fallback on the stock kernel) failed for real: the board image has no software
MPEG-1 decoder at all ("Missing element: MPEG-1 Video decoder"); the fix adds gstreamer1.0-libav to every image variant
(userpatches/config-opiz2-printserver.conf) and needs an image rebuild + reflash. Until the board runs that image the
check prints `NOT-TESTABLE` and the VERDICT is `INCOMPLETE (...)`: report both verbatim, not as FAIL.
Kernel: stock image kernel for phase stock, then the newest cumulative kernel (must contain 8140b4eeb, else BLOCKED,
"not ready"), restored at the end. Results: build/gst-mpeg1/results/ (job 12's kept as results-job12/).
Submitted 2026-11-06 by the runner-failures agent.
