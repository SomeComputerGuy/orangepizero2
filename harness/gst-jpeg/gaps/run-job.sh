#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner job: board test of the v4l2sljpegdec caps gaps (build/gst-jpeg/bundle-gaps).
# Takes the board lock (owner gst-jpeg-gaps), ships the bundle to /root/gstjpeg-gaps, runs board-test.sh
# (every gst run under timeout 60, ~5 min in all; capped at 1800 s), copies the results to
# build/gst-jpeg/results-gaps/, releases the lock, then runs compare.py on the host.
# No kernel change: runs on the booted kernel (recorded in kernel.txt).
set -u
H=/home/aruni/orangepizero2; B=$H/build/gst-jpeg/bundle-gaps; R=$H/build/gst-jpeg/results-gaps; SSH=$H/harness/ssh.sh
[ -d "$B/plugins" ] && [ -x "$B/board-test.sh" ] && [ -f "$B/vec/cases.txt" ] || { echo "bundle missing: $B"; exit 2; }
rm -rf "${R:?}"; mkdir -p "$R"
$H/harness/board-lock.sh acquire gst-jpeg-gaps 3600 || exit 3
trap '$H/harness/board-lock.sh release gst-jpeg-gaps' EXIT
$SSH 'uname -v; uname -r' > "$R/kernel.txt" 2>&1
$SSH 'rm -rf /root/gstjpeg-gaps; mkdir -p /root/gstjpeg-gaps'
tar -C "$B" -cf - . | $SSH 'tar -C /root/gstjpeg-gaps -xf -'
timeout -k 30 1800 $SSH 'sh /root/gstjpeg-gaps/board-test.sh /root/gstjpeg-gaps' > "$R/board-test.stdout" 2>&1
echo "board-test rc=$?" >> "$R/board-test.stdout"
$SSH 'tar -C /root/gstjpeg-gaps -cf - out' > "$R/out.tar"
$SSH 'rm -rf /root/gstjpeg-gaps'
$H/harness/board-lock.sh release gst-jpeg-gaps; trap - EXIT
tar -C "$R" -xf "$R/out.tar" && rm -f "$R/out.tar"
python3 -I $H/harness/gst-jpeg/gaps/compare.py "$R/out" "$B/vec" > "$R/compare.txt" 2>&1
cat "$R/compare.txt"
echo "done: $R"
