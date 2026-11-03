#!/bin/sh
# On-board DE33 Stage A checks (runs as root on the Zero2). No sink is needed:
# with drm.edid_firmware + video=...D the TCON scans out and the DE fetches,
# so flip timing, IN_FORMATS, IOMMU behaviour and decode-under-scanout load are
# measurable; picture quality is not.
#
# usage: board-de33.sh <outdir> [probe|full]
#   probe: §3.0 bandwidth probe (works on the image kernel too)
#   full:  probe + static checks + pattern/AFBC playback runs (Stage A kernel)
# Expects /root/afbc/afbc-kms-play, /root/vp/ffmpeg (static v4l2request
# FFmpeg) and streams under $STREAMS (local dir or http://host:port/dir).
set -u
OUT=${1:?outdir}; WHAT=${2:-full}
P=/root/afbc/afbc-kms-play
FF=${FF:-/root/vp/ffmpeg}
STREAMS=${STREAMS:-/root/vdec-streams}
N=${N:-600}
mkdir -p "$OUT"; cd "$OUT" || exit 1
log() { echo "== $*" | tee -a summary.txt; }
T=/sys/kernel/tracing

# VE busy time per job, as harness/research/vdec-perf/ve-busy-cmd.sh
ve_on() { echo 0 > $T/tracing_on; echo > $T/trace; echo function > $T/current_tracer
	  echo 'cedrus_device_run cedrus_irq' > $T/set_ftrace_filter; echo 1 > $T/tracing_on; }
ve_off() { echo 0 > $T/tracing_on
	awk '/cedrus_device_run/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+:$/){t=$i+0}; st=t}
	     /cedrus_irq/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+:$/){t=$i+0}; if(st){b+=t-st;n++;st=0}}
	     END{if(n) printf "VE jobs=%d busy=%.2fs avg=%.2fms => VE-bound fps %.1f\n",n,b,b/n*1000,n/b}' $T/trace
	echo nop > $T/current_tracer; echo > $T/set_ftrace_filter; }

dmesg > dmesg-start.txt
uname -a | tee -a summary.txt
cat /proc/cmdline | tee -a summary.txt
log "connectors"
for c in /sys/class/drm/card*-*; do echo "$c $(cat $c/status) $(head -c 200 $c/modes | tr '\n' ' ')"; done | tee -a summary.txt
$P --list > in-formats.txt 2>&1

# --- §3.0 probe: full-screen 4K XRGB8888 on the primary (fbcon) plane while
# the VE decodes AFBC10 4K (V4L2REQUEST_PIXFMT=AS01) into /dev/null.
PRIM=$(awk '/type primary/ {print $2; exit}' in-formats.txt)
log "probe: XR24 3840x2160 on primary plane $PRIM + AS01 decode"
$P --pattern XR24 -m 3840x2160@60 -p "$PRIM" -n 1500 -o probe-xr24.csv > probe-xr24.txt 2>&1 &
pp=$!
sleep 3
ve_on
V4L2REQUEST_PIXFMT=AS01 $FF -hide_banner -loglevel error -hwaccel v4l2request \
	-hwaccel_output_format drm_prime -i "$STREAMS/hevc-main10-2160p60.mkv" -f null - \
	> probe-ffmpeg.txt 2>&1
ve_off | tee -a summary.txt
wait $pp
cat probe-xr24.txt | tee -a summary.txt
log "baseline: AS01 decode without scanout load"
ve_on
V4L2REQUEST_PIXFMT=AS01 $FF -hide_banner -loglevel error -hwaccel v4l2request \
	-hwaccel_output_format drm_prime -i "$STREAMS/hevc-main10-2160p60.mkv" -f null - \
	> base-ffmpeg.txt 2>&1
ve_off | tee -a summary.txt
[ "$WHAT" = probe ] && { dmesg > dmesg-end.txt; exit 0; }

# --- Stage A static checks
log "IN_FORMATS: planes offering YU10 + AFBC"
grep -B200 'YU10 0x08000000000000' in-formats.txt | grep -E '^plane|YU10' | tee -a summary.txt
grep -c 'NV12 0x0000000000000000' in-formats.txt | sed 's/^/planes with linear NV12: /' | tee -a summary.txt
grep -iE 'iommu|sun50i-planes|sun8i-mixer|sun4i-drm|fault' dmesg-start.txt | tee -a summary.txt

VI=$(awk '/^plane/ {p=$2} /YU10 0x08/ {print p; exit}' in-formats.txt)
log "linear NV12 3840x2160 on VI plane $VI ($N flips)"
$P --pattern NV12 -m 3840x2160@60 -p "$VI" -n $N -o nv12.csv > nv12.txt 2>&1
cat nv12.txt | tee -a summary.txt

log "AFBC10 HEVC Main10 2160p60 ($N frames)"
ve_on
$P -m 3840x2160@60 -n $N -o afbc-hevc.csv "$STREAMS/hevc-main10-2160p60.mkv" > afbc-hevc.txt 2>&1 &
pp=$!
sleep 5
cat /sys/kernel/debug/dri/0/state > state-afbc.txt 2>&1
# FBD (AFBC decompressor) of VI channel 0: DE 0x01000000 + planes 0x100000
# + 0x5000. Read only these words, not the whole (read-unsafe) DE regmap.
for o in $(seq 0 4 92); do
	printf '0x%04x %s\n' $((0x5000 + o)) "$(python3 -I /root/afbc/devmem.py $((0x01105000 + o)))"
done > fbd-regs.txt 2>&1
wait $pp
ve_off | tee -a summary.txt
cat afbc-hevc.txt | tee -a summary.txt
grep -E 'modifier|format=|fb=' state-afbc.txt | head -20 | tee -a summary.txt

log "AFBC10 VP9 Profile 2 2160p60 ($N frames)"
ve_on
$P -m 3840x2160@60 -n $N -o afbc-vp9.csv "$STREAMS/vp9-p2-2160p60.webm" > afbc-vp9.txt 2>&1
ve_off | tee -a summary.txt
cat afbc-vp9.txt | tee -a summary.txt

log "AFBC10 HEVC with the primary plane kept on (OSD case, zpos)"
$P -k -m 3840x2160@60 -n 300 -o afbc-hevc-osd.csv "$STREAMS/hevc-main10-2160p60.mkv" > afbc-hevc-osd.txt 2>&1
cat afbc-hevc-osd.txt | tee -a summary.txt

log "8-bit AFBC (HEVC Main 2160p60, AS12) for the 8-bit decompressor path"
$P -f AS12 -m 3840x2160@60 -n 300 -o afbc8-hevc.csv "$STREAMS/hevc-main-2160p60.mkv" > afbc8-hevc.txt 2>&1
cat afbc8-hevc.txt | tee -a summary.txt

if grep -q Composite /sys/class/drm/card*-*/uevent 2>/dev/null || ls -d /sys/class/drm/card*-Composite-* >/dev/null 2>&1; then
	log "TVE: XR24 720x576 on Composite-1 (mixer1, YUV output)"
	$P --pattern XR24 -c Composite-1 -m 720x576 -n 120 -o tve.csv > tve.txt 2>&1
	cat tve.txt | tee -a summary.txt
else
	log "TVE: no Composite connector (expansion overlay not enabled) - not tested"
fi

dmesg > dmesg-end.txt
log "new kernel messages during the runs"
diff dmesg-start.txt dmesg-end.txt | grep '^>' | grep -viE 'audit' | tail -40 | tee -a summary.txt
