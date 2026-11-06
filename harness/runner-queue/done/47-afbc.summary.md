# 47-afbc summary
Verdict: BLOCKED (afbc blocked: Mesa fork missing on the board). Not a FAIL.
Kernel: 7.3.1 c38, `#38 SMP PREEMPT Fri Nov  6 10:29:47 UTC 2026` (Image md5 f7fc82bd55173cf0ddd56a15ff9a72d6); stock kernel restored (#17).
Start 2026-11-06 13:59:57, end 14:04:45. Script exit 0, 0 of 5 chunks done (vp9p2 hevc10 avs2 hevc8 vp9p0 all ended without ROUND-DONE).
Every chunk-<case>.txt contains exactly: `[env] BLOCKED: Mesa fork missing (/root/opiz2-mesa/main/env.sh); system Mesa cannot import AFBC YUV`
Checks: GL_RENDERER / quick ok=1 / F,C,M per case: NOT TESTED (all 5 cases). Mismatch table: none.
dmesg: dmesg-<case>.txt are 13-line boot logs; only "fault/oops" matches are the word "default". No faults/OOPS.
Results: harness/research/vdec-perf/logs/runner-afbc/
Needed: Mesa fork deployed to /root/opiz2-mesa/main on the board (env.sh).
