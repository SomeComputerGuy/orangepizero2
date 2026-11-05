#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board: decode the AVS2 reference streams with FFmpeg (native avs2 decoder + v4l2request hwaccel),
# one per-frame md5 list (yuv420p, output order) and one whole-stream md5 each, plus a VE-only rate run.
# Usage (on the board): board-avs2-ffmpeg.sh [outdir] [stream...]
U=http://10.56.0.1:8643/avs2; F=/root/ffavs2/ffmpeg; O=${1:-/root/ffavs2/out}; mkdir -p "$O"; shift 2>/dev/null
FF="$F -hide_banner -nostats -loglevel error -hwaccel v4l2request"
S=${*:-"BasketballPass_416x240_50_ai BasketballPass_416x240_50_ld BasketballPass_416x240_50_ra \
	BQMall_832x480_60_ra BQSquare_416x240_60_ai BQSquare_416x240_60_ld BQSquare_416x240_60_ra \
	ParkScene_1920x1080_24_ra PartyScene_832x480_50_ra RaceHorses_416x240_30_ai \
	RaceHorses_416x240_30_ld RaceHorses_416x240_30_ra \
	main-1080p-ra main-1080p-ldp main-1080p-tid main-1080p-lf main-2160p-ra"}
echo "kernel $(uname -r) $(uname -v)"
for s in $S; do
	pix=yuv420p; case $s in *10bit*) pix=yuv420p10le;; esac
	curl -sS -o /dev/shm/in.avs2 "$U/$s.avs2" || { echo "$s: download failed"; continue; }
	$FF -i /dev/shm/in.avs2 -fps_mode passthrough -pix_fmt $pix -f framemd5 - > "$O/$s.framemd5" 2> "$O/$s.err"
	rc=$?
	m=$($FF -i /dev/shm/in.avs2 -fps_mode passthrough -pix_fmt $pix -f md5 - 2>> "$O/$s.err" | tail -1)
	# rate: DRM_PRIME frames dropped, no download; rtime from -benchmark
	b=$($F -hide_banner -nostats -loglevel info -benchmark -hwaccel v4l2request -hwaccel_output_format drm_prime \
		-i /dev/shm/in.avs2 -f null - 2>&1 | grep -o 'rtime=[0-9.]*s' | tail -1)
	n=$(grep -c '^0,' "$O/$s.framemd5")
	echo "$s rc=$rc frames=$n $m $b"
done
rm -f /dev/shm/in.avs2
dmesg | grep -iE 'cedrus|iommu|timed out|oom' | tail -5
echo FF-AVS2-DONE
