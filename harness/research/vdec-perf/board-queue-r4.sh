#!/bin/bash
# Round 4 (board, cumulative kernel c3, VE 624 MHz default): why VP9 Profile 2 P010 stays below 60 fps.
# Part A: VE timeline + IOMMU PMU (micro-TLB hit rate per master) for VP9 P010/AFBC on the 4-tile stream and on
#         1- and 4-tile re-encodes of the same 120 frames, plus H.265 Main10 P010 as the control.
# Part B: IOMMU knobs one at a time (TLB prefetch, write buffer, out-of-order for the VE masters), restored after each.
# With PART=C (after a reboot with iommu.passthrough=1): the same rate runs without translation.
cd /root/vdec-streams || exit 1
V=/root/vp; DM="python3 -I $V/devmem.py"; TL=$V/ve-timeline.sh; U=http://10.56.0.1:8643/q1
F="$V/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"; FD="$F -hwaccel_output_format drm_prime"
for f in vp9p2-tc0.webm vp9p2-tc2.webm vp9p2-tc0.webm.p010le.md5 vp9p2-tc2.webm.p010le.md5; do [ -s $f ] || curl -sS -m 300 -o $f $U/$f; done
echo "kernel $(uname -rv) cmdline: $(tr ' ' '\n' < /proc/cmdline | grep -E 'iommu|cma' | tr '\n' ' ') $(grep -i cmatotal /proc/meminfo)"
echo "clk $(cat /sys/kernel/debug/clk/ve/clk_rate) iommu 0x30 bypass $($DM 0x030f0030) 0x40 gate $($DM 0x030f0040) 0x44 wbuf $($DM 0x030f0044) 0x48 ooo $($DM 0x030f0048) 0x4c 4kb $($DM 0x030f004c) 0x60 tlb $($DM 0x030f0060) 0x70 pref $($DM 0x030f0070)"
pmu() { # pmu <label> <cmd...>: timeline + IOMMU PMU for masters 2 (VE1, reference reads) and 3 (VE, writes)
  lbl=$1; shift
  if [ "$PART" != C ]; then $DM 0x030f0200 0; $DM 0x030f0210 1; sleep 0.01; $DM 0x030f0210 0; $DM 0x030f0200 1; fi
  t=$($TL "$@" | tr '\n' ' ')
  io=""
  if [ "$PART" != C ]; then $DM 0x030f0200 0
    for m in 2 3; do b=$((0x030f0230+0x10*m)); a=$(( $($DM $b) + ($($DM $((b+4))) << 32) )); h=$(( $($DM $((b+8))) + ($($DM $((b+12))) << 32) ))
      l=$(( $($DM $((0x030f0300+0x10*m))) + ($($DM $((0x030f0304+0x10*m))) << 32) ))
      [ $a -gt 0 ] && io="$io m$m acc=$a hit=$((100*h/a))% lat/acc=$((l/a))"; done; fi
  echo "[$lbl] $t |$io"
}
vp9() { # vp9 <label> <file> <fourcc> [extra ffmpeg args]
  pmu "$1" env V4L2REQUEST_PIXFMT=$3 $FD $4 -i $2 -f null -
}
setA() {
  vp9 "$1 vp9-4tile-orig P010" vp9-p2-2160p60.webm P010
  vp9 "$1 vp9-tc0 P010" vp9p2-tc0.webm P010
  vp9 "$1 vp9-tc2 P010" vp9p2-tc2.webm P010
  vp9 "$1 vp9-tc0 AFBC" vp9p2-tc0.webm AS01
  vp9 "$1 vp9-tc2 AFBC" vp9p2-tc2.webm AS01
  pmu "$1 h265m10 P010" env V4L2REQUEST_PIXFMT=P010 $FD -i hevc-main10-2160p60.mkv -f null -
}
md5c() { for t in "$@"; do r=$(V4L2REQUEST_PIXFMT=P010 $F -i $t -pix_fmt p010le -f md5 - 2>&1 | tail -1); ref=$(cut -d= -f2 $t.p010le.md5)
  res=FAIL; [ "${r#MD5=}" = "$ref" ] && res=PASS; echo "[md5 $LBL $t P010] $res ${r#MD5=}"; done; }
if [ "$PART" = C ]; then
  setA pt
  vp9 "pt vp9-4tile-orig P010 threads1" vp9-p2-2160p60.webm P010 "-threads 1"
  LBL=pt md5c vp9-p2-2160p60.webm vp9p2-tc0.webm
else
  setA base
  LBL=base md5c vp9p2-tc0.webm vp9p2-tc2.webm
  knob() { # knob <label> <reg> <value>
    o=$($DM $2); $DM $2 $3; echo "knob $1: $2 $o -> $($DM $2)"
    vp9 "$1 vp9-4tile-orig P010" vp9-p2-2160p60.webm P010
    vp9 "$1 vp9-tc0 P010" vp9p2-tc0.webm P010
    LBL=$1 md5c vp9-p2-2160p60.webm
    $DM $2 $o; echo "restored $2 $($DM $2)"
  }
  knob pref-all 0x030f0070 0x7f
  knob wbuf3-off 0x030f0044 $(( $($DM 0x030f0044) & ~0x8 ))
  knob ooo23-off 0x030f0048 $(( $($DM 0x030f0048) & ~0xc ))
fi
dmesg | grep -iE 'cedrus|iommu|fault|timed out|dma alloc' | tail -6 | sed 's/^/[dmesg] /'
echo "uptime $(cut -d" " -f1 /proc/uptime) cedrus-timeouts $(dmesg | grep -c "timed out")"
echo ROUND-DONE
