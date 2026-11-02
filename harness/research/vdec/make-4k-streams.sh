#!/usr/bin/env bash
# Build-host side (no board): synthesize the 4K/6K throughput streams for the
# Zero2 decode spec check, plus software-decode MD5 references.
# Needs ffmpeg with libx264, libx265, libvpx-vp9 (Ubuntu 26.10 ffmpeg has all three).
# Content: testsrc2 + temporal noise, so the entropy decoder is loaded at a
# realistic bitrate instead of a near-empty stream.
# Usage: make-4k-streams.sh OUTDIR [SECONDS]
set -euo pipefail
out="${1:?outdir}"; secs="${2:-10}"
mkdir -p "$out"; cd "$out"

src() { # $1=WxH $2=fps $3=pix_fmt
	echo "-f lavfi -i testsrc2=size=$1:rate=$2,noise=alls=12:allf=t+u,format=$3 -t $secs"
}

# H.265 Main, 3840x2160@60, ~40 Mbit/s (spec: 4K@60)
[[ -f hevc-main-2160p60.mkv ]] || ffmpeg -hide_banner -loglevel error $(src 3840x2160 60 yuv420p) \
	-c:v libx265 -preset ultrafast -x265-params "bitrate=40000:vbv-maxrate=40000:vbv-bufsize=80000:keyint=60:bframes=3:log-level=error" \
	hevc-main-2160p60.mkv
# H.265 Main10, 3840x2160@60, ~40 Mbit/s (spec: Main10@L5.1 4K@60)
[[ -f hevc-main10-2160p60.mkv ]] || ffmpeg -hide_banner -loglevel error $(src 3840x2160 60 yuv420p10le) \
	-c:v libx265 -profile:v main10 -preset ultrafast -x265-params "bitrate=40000:vbv-maxrate=40000:vbv-bufsize=80000:keyint=60:bframes=3:log-level=error" \
	hevc-main10-2160p60.mkv
# H.265 Main10, 6144x3456@30 (spec: 6K@30; needs the 6K patch, level 6 stream)
[[ -f hevc-main10-6k30.mkv ]] || ffmpeg -hide_banner -loglevel error $(src 6144x3456 30 yuv420p10le) \
	-c:v libx265 -profile:v main10 -preset ultrafast -x265-params "bitrate=60000:vbv-maxrate=60000:vbv-bufsize=120000:keyint=30:bframes=3:log-level=error" \
	hevc-main10-6k30.mkv
# VP9 Profile 2 (10-bit 4:2:0), 3840x2160@60, ~40 Mbit/s (spec: 4K@60)
[[ -f vp9-p2-2160p60.webm ]] || ffmpeg -hide_banner -loglevel error $(src 3840x2160 60 yuv420p10le) \
	-c:v libvpx-vp9 -profile:v 2 -b:v 40M -maxrate 40M -bufsize 80M -g 60 -deadline realtime -cpu-used 8 -row-mt 1 -tile-columns 2 \
	vp9-p2-2160p60.webm
# VP9 Profile 0, 3840x2160@60 (8-bit path at 4K)
[[ -f vp9-p0-2160p60.webm ]] || ffmpeg -hide_banner -loglevel error $(src 3840x2160 60 yuv420p) \
	-c:v libvpx-vp9 -profile:v 0 -b:v 40M -maxrate 40M -bufsize 80M -g 60 -deadline realtime -cpu-used 8 -row-mt 1 -tile-columns 2 \
	vp9-p0-2160p60.webm
# H.264 High, 3840x2160@30, ~40 Mbit/s (spec: 4K@30)
[[ -f h264-high-2160p30.mkv ]] || ffmpeg -hide_banner -loglevel error $(src 3840x2160 30 yuv420p) \
	-c:v libx264 -profile:v high -preset ultrafast -b:v 40M -maxrate 40M -bufsize 80M -g 30 -bf 3 \
	h264-high-2160p30.mkv

# Software references: one MD5 per frame, in the pixel format the HW path must match
for f in *.mkv *.webm; do
	case "$f" in *main10*|*p2*) pf=yuv420p10le;; *) pf=yuv420p;; esac
	[[ -f "$f.framemd5" ]] || ffmpeg -hide_banner -loglevel error -i "$f" -pix_fmt "$pf" -f framemd5 "$f.framemd5"
	[[ -f "$f.md5" ]] || ffmpeg -hide_banner -loglevel error -i "$f" -pix_fmt "$pf" -f md5 "$f.md5"
done
ls -la
