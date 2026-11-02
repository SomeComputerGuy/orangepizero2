#!/bin/bash
# Board side: per stream, (1) decode-only throughput to fakesink with VE IRQ count,
# (2) bit-exactness: decoder-native output (NV12 / P010_10LE, tightly packed because fdsink
# has no VideoMeta) md5 vs host ffmpeg software decode (-pix_fmt nv12/p010le -f md5).
# Usage: board-bench.sh [STREAMDIR] [names...]
D="${1:-/root/vdec-streams}"; shift || true
irq() { awk '/1c0e000/{s=0;for(i=2;i<=5;i++)s+=$i;print s; exit}' /proc/interrupts; }
pipe_for() {
	case "$1" in
	*hevc*) echo "matroskademux ! h265parse ! v4l2slh265dec";;
	*h264*) echo "matroskademux ! h264parse ! v4l2slh264dec";;
	*vp9*) echo "matroskademux ! vp9parse ! v4l2slvp9dec";;
	esac
}
names=("$@"); [[ ${#names[@]} -gt 0 ]] || names=(hevc-main-2160p60.mkv hevc-main10-2160p60.mkv hevc-main10-6k30.mkv vp9-p0-2160p60.webm vp9-p2-2160p60.webm h264-high-2160p30.mkv)
echo "kernel $(uname -v); ve clk $(cat /sys/kernel/debug/clk/ve/clk_rate 2>/dev/null)"
for n in "${names[@]}"; do
	f="$D/$n"; p="$(pipe_for $n)"
	case $n in *main10*|*p2*) gfmt=P010_10LE; hf=p010le; bpp=2;; *) gfmt=NV12; hf=nv12; bpp=1;; esac
	case $n in *6k*) w=6144; h=3456;; *) w=3840; h=2160;; esac
	frames=$(grep -vc '^#' "$f.framemd5")
	dmesg -C
	i0=$(irq); t0=$(date +%s.%N)
	out=$(gst-launch-1.0 -q filesrc location="$f" ! $p ! fakesink sync=false 2>&1); rc=$?
	t1=$(date +%s.%N); i1=$(irq)
	fps=$(echo "$frames / ($t1 - $t0)" | bc -l)
	printf '%-26s rc=%d frames=%d time=%.2fs fps=%.1f ve_irqs=%d\n' "$n" $rc $frames "$(echo "$t1 - $t0" | bc -l)" "$fps" $((i1-i0))
	[[ $rc -ne 0 ]] && echo "  gst: $(echo "$out" | tail -3 | tr '\n' ' ')"
	[[ -n $NOMD5 ]] && continue
	r=$(gst-launch-1.0 -q filesrc location="$f" ! $p ! video/x-raw,format=$gfmt ! fdsink fd=1 2>/tmp/gst-md5.err | python3 /root/framemd5.py $w $h /root/vdec-out/$n.$hf.framemd5 $bpp ${CHUNK:-})
	ref=$(cut -d= -f2 "$f.$hf.md5" 2>/dev/null)
	res=FAIL; [[ ${r##*md5=} == "$ref" ]] && res=PASS
	echo "  bitexact $hf: $r ref=$ref $res"
	dmesg | grep -iE 'cedrus|iommu|video-codec' | tail -3 | sed 's/^/  dmesg: /'
done
