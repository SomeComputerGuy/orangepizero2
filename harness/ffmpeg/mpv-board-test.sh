#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Board test of the packaged FFmpeg/mpv (+opiz2) debs: install them the way the desktop image does (file: repo +
# pin 1001), play the 4K/1080p regress streams with mpv (hwdec, null and DRM/EGL video outputs), then remove
# everything again so the board's image is unchanged. Caller holds the board lock.
# Usage: harness/ffmpeg/mpv-board-test.sh <outdir> [keep]
set -uo pipefail
H=$(cd "$(dirname "$0")/../.." && pwd); SSH=$H/harness/ssh.sh; O=$(realpath -m "${1:?outdir}"); mkdir -p "$O"
D=$H/out/debs-media; U=http://10.56.0.1:8644
log() { echo "[$(date +%T)] $*" | tee -a "$O/mpv.log"; }
irq() { $SSH -n "awk '/1c0e000.video-codec/{print \$2+\$3+\$4+\$5}' /proc/interrupts"; }
tar cf - -C "$D" . | $SSH 'rm -rf /opt/opiz2-media; mkdir -p /opt/opiz2-media; tar xf - -C /opt/opiz2-media'
$SSH 'echo "deb [trusted=yes] file:/opt/opiz2-media ./" > /etc/apt/sources.list.d/opiz2-media.list
printf "Package: *\nPin: origin \"\"\nPin-Priority: 1001\n" > /etc/apt/preferences.d/opiz2-media.pref
apt-get -q update >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get -y -q install --no-install-recommends mpv ffmpeg 2>&1 | tail -2
dpkg-query -W -f "\${Package} \${Version}\n" mpv ffmpeg libavcodec62 libavutil60 libmpv2 2>/dev/null' | tee -a "$O/mpv.log"
$SSH -n 'mpv --version | head -1; ffmpeg -hide_banner -hwaccels | tail -n +2 | tr "\n" " "; echo' | tee -a "$O/mpv.log"
for r in vdec/h264-high-2160p30.mkv vdec/hevc-main-2160p60.mkv vdec/vp9-p0-2160p60.webm gen/vp8-1080p60.webm gen/mpeg2-mphl-1080i30.m2v; do
	n=$(basename "$r"); $SSH -n "curl -sS -o /dev/shm/m.in $U/$r"
	for mode in "auto-safe null" "v4l2request null" "v4l2request gpu-drm"; do
		set -- $mode; hw=$1; vo=$2; extra="--vo=null"
		[ "$vo" = gpu-drm ] && extra="--vo=gpu --gpu-context=drm"
		i0=$(irq); t0=$(date +%s.%N)
		$SSH -n "timeout 120 mpv --no-config --really-quiet --msg-level=vd=v,vo=warn,cplayer=warn --hwdec=$hw $extra --ao=null --untimed --no-audio /dev/shm/m.in 2>&1 | grep -iE 'hardware decoding|hwdec|error|fail' | sort -u | head -4; echo rc=\${PIPESTATUS[0]}" > "$O/$n.$hw.$vo.txt" 2>&1
		t1=$(date +%s.%N); i1=$(irq)
		log "$n hwdec=$hw vo=$vo irqs=$((i1-i0)) wall=$(printf '%.1f' "$(echo "$t1 - $t0" | bc)")s $(tr '\n' ' ' < "$O/$n.$hw.$vo.txt")"
	done
done
# realtime 4K playback (timed, display): frame drops
$SSH -n "curl -sS -o /dev/shm/m.in $U/vdec/hevc-main-2160p60.mkv"
$SSH -n "timeout 60 mpv --no-config --hwdec=v4l2request --vo=gpu --gpu-context=drm --ao=null --no-audio --frames=600 --term-status-msg='' /dev/shm/m.in 2>&1 | grep -iE 'dropped|hardware|error' | sort -u | head -5" | tee -a "$O/mpv.log"
$SSH -n 'rm -f /dev/shm/m.in; dmesg | grep -iE "cedrus|panfrost|timed out|oops" | tail -4' | tee -a "$O/mpv.log"
if [ "${2:-}" != keep ]; then
	$SSH 'DEBIAN_FRONTEND=noninteractive apt-get -y -q purge mpv ffmpeg >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get -y -q autoremove --purge >/dev/null 2>&1
rm -rf /opt/opiz2-media /etc/apt/sources.list.d/opiz2-media.list /etc/apt/preferences.d/opiz2-media.pref; apt-get -q update >/dev/null 2>&1
dpkg -l | grep -cE "^ii  (libavcodec|ffmpeg|mpv|libmpv)" ; df -h / | tail -1' | tee -a "$O/mpv.log"
fi
log MPV-DONE
