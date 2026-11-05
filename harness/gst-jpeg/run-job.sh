#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner job: board test of the v4l2sljpegdec dev build (build/gst-jpeg/bundle).
# Takes the board lock (owner gst-jpeg-run), ships the bundle to /root/gstjpeg, runs board-test.sh
# (every gst run under timeout 60), copies results to build/gst-jpeg/results/, releases the lock,
# then runs compare.py on the host. No kernel change: runs on the booted kernel (recorded).
set -u
H=/home/aruni/orangepizero2; B=$H/build/gst-jpeg/bundle; R=$H/build/gst-jpeg/results; SSH=$H/harness/ssh.sh
[ -d "$B/plugins" ] && [ -x "$B/board-test.sh" ] || { echo "bundle missing: $B"; exit 2; }
rm -rf "${R:?}"; mkdir -p "$R"
$H/harness/board-lock.sh acquire gst-jpeg-run 14400 || exit 3
trap '$H/harness/board-lock.sh release gst-jpeg-run' EXIT
$SSH 'uname -v; uname -r' > "$R/kernel.txt" 2>&1
$SSH 'rm -rf /root/gstjpeg; mkdir -p /root/gstjpeg'
tar -C "$B" -cf - . | $SSH 'tar -C /root/gstjpeg -xf -'
timeout -k 30 2700 $SSH 'sh /root/gstjpeg/board-test.sh /root/gstjpeg' > "$R/board-test.stdout" 2>&1
echo "board-test rc=$?" >> "$R/board-test.stdout"
$SSH 'tar -C /root/gstjpeg -cf - out' > "$R/out.tar"
$SSH 'rm -rf /root/gstjpeg'
$H/harness/board-lock.sh release gst-jpeg-run; trap - EXIT
tar -C "$R" -xf "$R/out.tar" && rm -f "$R/out.tar"
python3 -I $H/harness/gst-jpeg/compare.py "$R/out" > "$R/compare.txt" 2>&1
echo "done: $R"
