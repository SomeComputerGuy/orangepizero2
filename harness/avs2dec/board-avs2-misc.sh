#!/bin/bash
# Board: AVS2 A9 (interleaved with H.265 in another process) and A10 (error paths).
U=http://10.56.0.1:8643/avs2; B=/root/avs2/avs2dec; O=/root/avs2/misc; mkdir -p $O
F="/root/vp/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"
echo "== A9: PartyScene AVS2 (x3, back to back) while H.265 Main10 P010 decodes in another process"
( cd /root/vdec-streams; V4L2REQUEST_PIXFMT=P010 $F -i hevc-main10-2160p60.mkv -frames:v 300 -pix_fmt p010le -f framemd5 - > $O/a9-hevc.framemd5 2>&1; echo "hevc rc=$?" ) &
# VP9 in parallel dropped: 3 concurrent 4K decoders plus other board users ran the board out of memory
for i in 1 2 3; do curl -sS $U/PartyScene_832x480_50_ra.avs2 | $B -f - > $O/a9-avs2-$i.txt 2>&1; echo "avs2 run $i rc=$? $(tail -1 $O/a9-avs2-$i.txt)"; done
wait
echo "== A10: truncated stream"
curl -sS $U/err-trunc.avs2 | timeout 120 $B -f - > $O/a10-trunc.txt 2>&1; echo "rc=$? $(tail -1 $O/a10-trunc.txt)"
echo "== A10: corrupted slice data"
curl -sS $U/err-corrupt.avs2 | timeout 120 $B -f - > $O/a10-corrupt.txt 2>&1; echo "rc=$? $(tail -1 $O/a10-corrupt.txt)"
echo "== A10: clean decode afterwards"
curl -sS $U/BQMall_832x480_60_ra.avs2 | timeout 120 $B -f - > $O/a10-after.txt 2>&1; echo "rc=$? $(tail -1 $O/a10-after.txt)"
dmesg | grep -iE 'cedrus|iommu|fault|timed out|oom' | tail -8
echo MISC-DONE
