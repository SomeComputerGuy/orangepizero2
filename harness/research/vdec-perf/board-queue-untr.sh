#!/bin/bash
# Untranslated-VE opt-in test. MODE=A: default DT (VE behind the IOMMU). MODE=B: overlay vdec-untranslated with a large
# CMA: peak CMA use and fps per pipeline configuration. MODE=C: overlay with the chosen CMA size: md5 of all codecs and a
# memory-pressure run.
cd /root/vdec-streams || exit 1
V=/root/vp; DM="python3 -I $V/devmem.py"; TL=$V/ve-timeline.sh; A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2
F="$V/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"; FD="$F -hwaccel_output_format drm_prime"
curl -sS $U/avs2dec-q -o $A; chmod +x $A; curl -sS $U/cctv4k-10bit.avs2 -o /tmp/cc.avs2; curl -sS $U/main-2160p-ra.avs2 -o /tmp/m8.avs2
mi() { awk -v k="$1:" '$1==k {print int($2/1024)}' /proc/meminfo; }
echo "MODE=$MODE kernel $(uname -rv) cmdline: $(grep -o 'cma=[^ ]*\|iommu[^ ]*' /proc/cmdline | tr '\n' ' ') CmaTotal $(mi CmaTotal) MB CmaFree $(mi CmaFree) MB MemAvailable $(mi MemAvailable) MB"
echo "iommu bypass $($DM 0x030f0030) enable $($DM 0x030f0020); VE iommus in live DT: [$(od -An -tx1 /proc/device-tree/soc/video-codec@1c0e000/iommus 2>/dev/null | tr -d ' \n')]; $(dmesg | grep -m2 -i '1c0e000.video-codec.*iommu\|cedrus.*registered' | tr '\n' ' ')"
cmapeak() { # cmapeak <label> <cmd...>: run under ve-timeline, sample CmaFree, print fps and peak CMA use
  lbl=$1; shift; base=$(mi CmaFree); : > /tmp/cma.min; ( m=$base; while :; do f=$(mi CmaFree); [ $f -lt $m ] && m=$f && echo $m > /tmp/cma.min; sleep 0.1; done ) & sp=$!
  t=$($TL "$@" | tr '\n' ' '); kill $sp; wait $sp 2>/dev/null; m=$(cat /tmp/cma.min); [ -z "$m" ] && m=$base
  echo "[$lbl] cma-peak $((base - m)) MB (free before $base) | $(echo "$t" | sed -e 's/| setup.*fps:/| fps:/' -e 's/ | idle share.*//')"
}
md5s() {
  for t in vp9-p2-2160p60.webm hevc-main10-2160p60.mkv; do r=$(V4L2REQUEST_PIXFMT=P010 $F -i $t -pix_fmt p010le -f md5 - 2>&1 | tail -1); ref=$(cut -d= -f2 $t.p010le.md5)
    res=FAIL; [ "${r#MD5=}" = "$ref" ] && res=PASS; echo "[$MODE md5 $t P010] $res ${r#MD5=}"; done
  r=$($A /tmp/m8.avs2 2>/dev/null | tail -1 | awk '{print $NF}'); res=FAIL; [ "$r" = 3a3d5d7eb9a6f548042e160d9e461388 ] && res=PASS; echo "[$MODE md5 avs2-8bit-2160p] $res $r"
  r=$($A /tmp/cc.avs2 2>/dev/null | tail -1 | awk '{print $NF}'); res=FAIL; [ "$r" = be9985dea38abffc850d73024165c990 ] && res=PASS; echo "[$MODE md5 avs2-10bit-cctv4k P010] $res $r"
}
case $MODE in
A) md5s
   cmapeak "A vp9p2 P010 default" env V4L2REQUEST_PIXFMT=P010 $FD -i vp9-p2-2160p60.webm -f null - ;;
B) for th in 1 2 3 0; do cmapeak "B vp9p2 P010 threads=$th" env V4L2REQUEST_PIXFMT=P010 $FD -threads $th -i vp9-p2-2160p60.webm -f null -; done
   for th in 1 2 0; do cmapeak "B h265m10 P010 threads=$th" env V4L2REQUEST_PIXFMT=P010 $FD -threads $th -i hevc-main10-2160p60.mkv -f null -; done
   cmapeak "B avs2-10bit P010 depth2" env AVS2_NOOUT=1 $A /tmp/cc.avs2
   cmapeak "B vp9p2 AFBC default" env V4L2REQUEST_PIXFMT=AS01 $FD -i vp9-p2-2160p60.webm -f null -
   cmapeak "B gst vp9p2" gst-launch-1.0 -q filesrc location=vp9-p2-2160p60.webm ! matroskademux ! vp9parse ! v4l2slvp9dec ! fakevideosink sync=false
   md5s ;;
C) md5s
   cmapeak "C vp9p2 P010 threads=${TH:-0}" env V4L2REQUEST_PIXFMT=P010 $FD -threads ${TH:-0} -i vp9-p2-2160p60.webm -f null -
   d0=$(dmesg | wc -l); av=$(mi MemAvailable); echo "pressure: allocating $((av - 48)) MB of anonymous memory (MemAvailable $av MB) during decode"
   python3 -I -c "
import time,sys
n=int(sys.argv[1]); b=[]
for i in range(n): b.append(bytearray(1<<20))
time.sleep(40)" $((av - 48)) & pp=$!; sleep 8
   cmapeak "C-pressure vp9p2 P010 threads=${TH:-0}" env V4L2REQUEST_PIXFMT=P010 $FD -threads ${TH:-0} -i vp9-p2-2160p60.webm -f null -
   r=$(V4L2REQUEST_PIXFMT=P010 $F -threads ${TH:-0} -i vp9-p2-2160p60.webm -pix_fmt p010le -f md5 - 2>&1 | tail -1); echo "[C-pressure md5 vp9] ${r#MD5=} (ref $(cut -d= -f2 vp9-p2-2160p60.webm.p010le.md5))"
   wait $pp; echo "pressure done, MemAvailable $(mi MemAvailable) MB"
   dmesg | tail -n +$((d0 + 1)) | grep -iE 'alloc|oom|out of memory|slub|cma|fail|killed' | head -8 | sed 's/^/[dmesg-pressure] /'
   echo "[dmesg-pressure] $(dmesg | tail -n +$((d0 + 1)) | grep -ciE 'alloc|oom|out of memory|slub|cma|fail|killed') matching lines" ;;
esac
rm -f /tmp/cc.avs2 /tmp/m8.avs2
dmesg | grep -iE 'cedrus|iommu.*fault|timed out|dma alloc|cma_alloc' | tail -5 | sed 's/^/[dmesg] /'
echo "uptime $(cut -d' ' -f1 /proc/uptime) cedrus-timeouts $(dmesg | grep -c 'timed out')"; echo ROUND-DONE
