#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner job: board test of v4l2sljpegdec at odd picture sizes and across resolution changes
# (build/gst-jpeg/bundle-oddsize). Takes the board lock (owner gst-jpeg-oddsize), ships the bundle to
# /root/gstjpeg-oddsize, runs board-test.sh (every gst run under timeout 60, ~6 min in all; capped at
# 1800 s), copies the results to build/gst-jpeg/results-oddsize/, releases the lock, then runs compare.py
# on the host (needs ffmpeg and python3-numpy). No kernel change: runs on the booted kernel (kernel.txt).
set -u
H=/home/aruni/orangepizero2; B=$H/build/gst-jpeg/bundle-oddsize; R=$H/build/gst-jpeg/results-oddsize; SSH=$H/harness/ssh.sh
[ -d "$B/plugins" ] && [ -x "$B/board-test.sh" ] && [ -f "$B/vec/cases.txt" ] && [ -x "$B/jpegtest" ] || { echo "bundle missing: $B"; exit 2; }
rm -rf "${R:?}"; mkdir -p "$R"
$H/harness/board-lock.sh acquire gst-jpeg-oddsize 3600 || exit 3
trap '$H/harness/board-lock.sh release gst-jpeg-oddsize' EXIT
$SSH 'uname -v; uname -r' > "$R/kernel.txt" 2>&1
$SSH 'rm -rf /root/gstjpeg-oddsize; mkdir -p /root/gstjpeg-oddsize'
tar -C "$B" -cf - . | $SSH 'tar -C /root/gstjpeg-oddsize -xf -'
timeout -k 30 1800 $SSH 'sh /root/gstjpeg-oddsize/board-test.sh /root/gstjpeg-oddsize' > "$R/board-test.stdout" 2>&1
echo "board-test rc=$?" >> "$R/board-test.stdout"
$SSH 'tar -C /root/gstjpeg-oddsize -cf - out' > "$R/out.tar"
$SSH 'rm -rf /root/gstjpeg-oddsize'
$H/harness/board-lock.sh release gst-jpeg-oddsize; trap - EXIT
tar -C "$R" -xf "$R/out.tar" && rm -f "$R/out.tar"
python3 -I $H/harness/gst-jpeg/oddsize/compare.py "$R/out" "$B/vec" > "$R/compare.txt" 2>&1
cat "$R/compare.txt"
echo "done: $R"
