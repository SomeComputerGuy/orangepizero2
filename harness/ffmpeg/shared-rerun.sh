#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Board rerun of every v4l2-request hwaccel with one FFmpeg binary (shared OPi5/OPiZ2 set). Caller holds the lock.
# Usage: harness/ffmpeg/shared-rerun.sh <ffmpeg-aarch64-binary> <outdir>
# md5: H.264/HEVC/VP9/VP8/MBAFF (regress.list), VC-1 (vc1.list) + SMM0005 against the patched software decoder
# (board, same binary, no hwaccel: Jernej's 0201/0202 change the SW reference, FATE ref = 0310);
# IDCT envelope: MPEG-1/2/4/H.263/Spark (raw.list, 60 frames); AVS/AVS+ (avs-board-test.sh); AVS2
# (board-avs2-ffmpeg.sh + cmp-avs2-ffmpeg.py); 4K decode rate (-benchmark, DRM_PRIME, no download).
set -uo pipefail
H=$(cd "$(dirname "$0")/../.." && pwd); SSH=$H/harness/ssh.sh; BIN=$(realpath "${1:?binary}"); O=$(realpath -m "${2:?outdir}")
mkdir -p "$O"; LD=$H/harness/research/legacy-dec; BD=$H/kernel-check/ffmpeg-deb/board
log() { echo "[$(date +%T)] $*" | tee -a "$O/rerun.log"; }
log "kernel $($SSH -n 'uname -r; uname -v' | tr '\n' ' ')"
for d in /root/opiz2ff /root/ffavs /root/ffavs2; do $SSH "mkdir -p $d; cat > $d/ffmpeg.new && chmod +x $d/ffmpeg.new && mv $d/ffmpeg.new $d/ffmpeg" < "$BIN"; done
log "binary $(md5sum < "$BIN" | cut -c1-32) shipped; hwaccels: $($SSH -n '/root/opiz2ff/ffmpeg -hide_banner -hwaccels' | tail -n +2 | tr '\n' ' ')"
cd "$BD"
log "md5 regress"; BFF=/root/opiz2ff/ffmpeg timeout 1800 "$LD/run-md5.sh" regress.list "$O/regress" > /dev/null 2>&1
cut -f1,3-6 "$O/regress/summary.tsv" | tee -a "$O/rerun.log"
log "IDCT envelope"; FRAMES=60 BFF=/root/opiz2ff/ffmpeg timeout 2400 "$LD/run-raw.sh" raw.list "$O/raw" > /dev/null 2>&1
cat "$O/raw/raw.tsv" | cut -c1-220 | tee -a "$O/rerun.log"
log "VC-1"; BFF=/root/opiz2ff/ffmpeg timeout 1200 "$LD/run-md5.sh" "$LD/lists/vc1.list" "$O/vc1" > /dev/null 2>&1
cut -f1,3-8 "$O/vc1/summary.tsv" | tee -a "$O/rerun.log"
log "SMM0005 vs patched SW decoder (board)"
FF="/root/opiz2ff/ffmpeg -nostdin -hide_banner -loglevel warning"; U=http://10.56.0.1:8644/vc1/SMM0005.rcv
$SSH -n "$FF -f vc1test -i $U -fps_mode passthrough -noautoscale -pix_fmt nv12 -f framemd5 -" > "$O/smm0005.swpatched.framemd5" 2> "$O/smm0005.sw.err"
python3 -I "$LD/cmp-framemd5.py" "$O/smm0005.swpatched.framemd5" "$O/vc1/wmv3-SMM0005.hw.framemd5" | tee -a "$O/rerun.log"
log "AVS/AVS+"; timeout 1800 "$H/harness/ffmpeg/avs-board-test.sh" "$O/avs" > /dev/null 2>&1; cat "$O/avs/summary.tsv" | tee -a "$O/rerun.log"
log "AVS2"; base64 -w0 "$H/harness/ffmpeg/board-avs2-ffmpeg.sh" | $SSH 'base64 -d > /root/ffavs2/board-avs2-ffmpeg.sh'
S="BasketballPass_416x240_50_ai BasketballPass_416x240_50_ld BasketballPass_416x240_50_ra BQMall_832x480_60_ra BQSquare_416x240_60_ai BQSquare_416x240_60_ld BQSquare_416x240_60_ra ParkScene_1920x1080_24_ra PartyScene_832x480_50_ra RaceHorses_416x240_30_ai RaceHorses_416x240_30_ld RaceHorses_416x240_30_ra main-1080p-ra main-1080p-ldp main-1080p-tid main-1080p-lf main-2160p-ra cctv4k-10bit"
$SSH -n "rm -rf /root/ffavs2/out-c; timeout 3000 sh /root/ffavs2/board-avs2-ffmpeg.sh /root/ffavs2/out-c $S" > "$O/avs2-board.log" 2>&1
mkdir -p "$O/avs2"; $SSH -n "cd /root/ffavs2/out-c && tar cf - ." | tar xf - -C "$O/avs2"
python3 -I "$H/harness/ffmpeg/cmp-avs2-ffmpeg.py" "$O/avs2" "$O/avs2-board.log" | tee -a "$O/rerun.log"
log "4K rate (DRM_PRIME, -benchmark)"
for r in vdec/h264-high-2160p30.mkv vdec/hevc-main-2160p60.mkv vdec/vp9-p0-2160p60.webm; do
	b=$($SSH -n "curl -sS -o /dev/shm/r.in http://10.56.0.1:8644/$r && /root/opiz2ff/ffmpeg -nostdin -hide_banner -nostats -benchmark -hwaccel v4l2request -hwaccel_output_format drm_prime -i /dev/shm/r.in -an -f null - 2>&1 | grep -oE 'frame= *[0-9]+|rtime=[0-9.]+s' | tr '\n' ' '; rm -f /dev/shm/r.in")
	log "$r $b"
done
$SSH -n "dmesg | grep -iE 'cedrus|timed out|oops|bug:' | tail -5" | tee -a "$O/rerun.log"
log "RERUN-DONE"
