#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner package: job vp9-upsize (DEV, ~10 min): the VP9 inter-frame UPSIZE vector vp90-2-22-svc_1280x720_3 plus the
# 26 downsize vectors (chunk u1) and a 25-vector profile-0 regression subset (chunk u2), on the newest cumulative
# kernel, which must contain the upsize fix (armbian-build fix/sunxi-cedrus-vp9-inter-upsize = UPSIZE_SHA); else
# BLOCKED without touching the board. Everything else is run-job.sh (board lock, trial kernel with fallback, bundle,
# pre-flight, stall watchdog, results copied off, stock kernel restored) with OUT=logs/upsize and JOB=upsize.
# Exit 0 = both chunks ran (pass/fail: check-results.py logs/upsize upsize, HANDOFF-upsize.md); 2 = blocked; 1 = setup.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/vp9-vectors
UPSIZE_SHA=7897dec0864e755260c0ff9db3895cb99fd1f9d7
export OUT=$S/logs/upsize JOB=upsize; mkdir -p "$OUT"; rm -f "$OUT/BLOCKED"
TL=$(tail -1 $H/kernel-check/cumulative-kernels.txt); KSHA=$(cut -d' ' -f3 <<< "$TL")
if ! git -C $H/wt-cumulative merge-base --is-ancestor $UPSIZE_SHA "$KSHA" 2>/dev/null; then
	echo "newest cumulative kernel ($TL) does not contain the upsize fix ${UPSIZE_SHA:0:9} (fix/sunxi-cedrus-vp9-inter-upsize): merge + cumul-build it first" | tee "$OUT/BLOCKED"
	exit 2
fi
echo "kernel $TL contains the upsize fix ${UPSIZE_SHA:0:9}" | tee "$OUT/fix.txt"
exec bash $S/run-job.sh u1 u2
