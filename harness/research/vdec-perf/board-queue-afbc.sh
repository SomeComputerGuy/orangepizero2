#!/bin/bash
# AFBC bit-exactness round (board, cumulative kernel c3): decode H.265 8-bit into the VE's native 8-bit AFBC capture (AS12,
# validation of the checker against the NV12 reference), then VP9 Profile 2, H.265 Main10 and AVS2 10-bit 4K into the
# 10-bit AFBC capture (AS01). The raw capture buffers are streamed through a FIFO into afbc-gpu-check, which decodes them
# on the Mali-G31 (panfrost, strict AFBC(YUV) dma-buf import) and md5s every frame against the P010/NV12 framemd5
# references (vdec-perf/afbc/). Results in /root/afbc/*.txt; the first mismatching frame of each case in /root/afbc/dump.
cd /root/vdec-streams || exit 1
U=http://10.56.0.1:8643/afbc; A=/root/afbc; D=$A/dump; FIFO=/tmp/afbc.fifo; mkdir -p $A $D
rm -f /root/afbc/dump/* /root/afbc/*.txt   # no stale results from an earlier round
F="$A/ffmpeg-afbc -hide_banner -nostats -loglevel error -hwaccel v4l2request -hwaccel_output_format drm_prime"
for f in ffmpeg-afbc avs2dec-afbc afbc-gpu-check hevc-main-2160p60.mkv.nv12.framemd5 vp9-p2-2160p60.webm.p010le.framemd5 \
         hevc-main10-2160p60.mkv.p010le.framemd5 vp9-p0-2160p60.webm.nv12.framemd5 cctv4k-10bit.p010.framemd5; do
  curl -sS -m 300 -o $A/$f $U/$f || { echo "fetch $f failed"; exit 1; }; done
chmod +x $A/ffmpeg-afbc $A/avs2dec-afbc $A/afbc-gpu-check
for f in hevc-main-2160p60.mkv vp9-p0-2160p60.webm vp9-p2-2160p60.webm hevc-main10-2160p60.mkv; do
  [ -s $f ] || curl -sS -m 900 -o $f $U/$f; done
curl -sS -m 300 -o /tmp/cc.avs2 $U/cctv4k-10bit.avs2
[ -f /root/opiz2-mesa/main/env.sh ] || { echo "[env] BLOCKED: Mesa fork missing (/root/opiz2-mesa/main/env.sh); system Mesa cannot import AFBC YUV"; exit 3; }
. /root/opiz2-mesa/main/env.sh
echo "kernel $(uname -rv) ve-clk $(cat /sys/kernel/debug/clk/ve/clk_rate 2>/dev/null) mesa $(ls /root/opiz2-mesa/main/lib/libgallium* 2>/dev/null | head -1) uptime $(cut -d" " -f1 /proc/uptime)"
df -h /tmp /root | tail -2 | sed 's/^/[df] /'; free -m | head -2 | tail -1 | sed 's/^/[mem] /'
echo "== GL smoke test"; $A/afbc-gpu-check -v /dev/null > $A/probe.txt 2>&1
grep -E 'GL_RENDERER|^EGL |^done|afbc-gpu-check:|^probe' $A/probe.txt | sed 's/^/[gl] /'
# job 49: every import failed with EGL_BAD_MATCH, i.e. panfrost listed no plane count for the modifier. The probe reads
# the GPU's AFBC_FEATURES (Mesa pan_query_afbc(): nonzero = AFBC omitted from this G31) and the EGL modifier lists.
# run <name> <ref> <layout> <max-frames|0> <decoder command...>  (the decoder writes the dump to $FIFO)
run() {
  local n=$1 ref=$2 lay=$3 max=$4 t0 ck rc crc; shift 4
  # CASES="<names>": run only these (the hevc8q validation and its diagnostics always run)
  if [ -n "${CASES:-}" ]; then case $n in hevc8q|diag-*) ;; *) [[ " $CASES " == *" $n "* ]] || return 0;; esac; fi
  rm -f $FIFO; mkfifo $FIFO; t0=$(date +%s)
  timeout 2700 $A/afbc-gpu-check -r $A/$ref -l $lay -m $max -D $D "${CKOPT[@]}" $FIFO > $A/$n.check.txt 2>&1 & ck=$!
  V4L2REQUEST_DUMP=$FIFO V4L2REQUEST_DUMP_MAX=$max timeout 2700 "$@" > $A/$n.dec.txt 2>&1; rc=$?
  # the checker drains the FIFO after the decoder exits; if the decoder never opened it, the checker sits in open()
  for i in $(seq 1 180); do kill -0 $ck 2>/dev/null || break; sleep 1; done; kill $ck 2>/dev/null
  wait $ck; crc=$?
  echo "[$n] dec rc $rc check rc $crc $(( $(date +%s) - t0 )) s | $(grep -E '^done' $A/$n.check.txt) | $(grep -E '^input|^import' $A/$n.check.txt | tr '\n' ' ')"
  grep -E 'FAIL|afbc-gpu-check:|rror|^hdr|wrote|^import-failed|^probe: YU' $A/$n.check.txt | head -16 | sed "s/^/[$n] /"
  grep -v '^frame' $A/$n.dec.txt | tail -3 | sed "s/^/[$n dec] /"
  rm -f $FIFO
}
frames() { local f=$1; [ "$f" = 0 ] && echo 100000 || echo $f; }
CKOPT=(-H)
echo "== quick validation: H.265 8-bit AS12 vs NV12 reference, 60 frames"
run hevc8q hevc-main-2160p60.mkv.nv12.framemd5 nv12 60 env V4L2REQUEST_PIXFMT=AS12 $F -i hevc-main-2160p60.mkv -frames:v 60 -f null -
if grep -q 'gpu-afbc no' $A/probe.txt; then   # hevc8q above kept the raw header block (dump/frame-0.afbc-head)
  echo "afbc: NOT TESTABLE on the GPU: this Mali-G31 has no AFBC (AFBC_FEATURES != 0), Mesa rejects every AFBC import"
  ls -la $D | sed 's/^/[dump] /'; echo ROUND-DONE; exit 0
fi
tq=$(grep -oE '[0-9.]+ s \(gpu' $A/hevc8q.check.txt | cut -d' ' -f1); ok=$(grep -c '60 compared, 60 matched' $A/hevc8q.check.txt)
per=$(python3 -c "print(int(float('${tq:-9999}')*1000/60))"); echo "quick: ok=$ok per-frame ${per} ms"
if [ "$ok" != 1 ]; then
  echo "== quick validation failed: diagnostics (3 frames each)"
  CKOPT=(-H -v); run diag-split hevc-main-2160p60.mkv.nv12.framemd5 nv12 3 env V4L2REQUEST_PIXFMT=AS12 $F -i hevc-main-2160p60.mkv -frames:v 3 -f null -
  CKOPT=(-H -M 0800000000000041); run diag-nosplit hevc-main-2160p60.mkv.nv12.framemd5 nv12 3 env V4L2REQUEST_PIXFMT=AS12 $F -i hevc-main-2160p60.mkv -frames:v 3 -f null -
  CKOPT=(-H -e); run diag-ext hevc-main-2160p60.mkv.nv12.framemd5 nv12 3 env V4L2REQUEST_PIXFMT=AS12 $F -i hevc-main-2160p60.mkv -frames:v 3 -f null -
  CKOPT=(-H -l i420); run diag-i420 hevc-main-2160p60.mkv.nv12.framemd5 i420 3 env V4L2REQUEST_PIXFMT=AS12 $F -i hevc-main-2160p60.mkv -frames:v 3 -f null -
  MAX=60
else
  # budget ~40 min for the five full runs: 600 frames each when the GPU check keeps up, fewer otherwise
  MAX=$(( ${AFBC_BUDGET_MS:-480000} / (per > 0 ? per : 1) )); [ $MAX -ge 600 ] && MAX=0; [ $MAX -gt 0 ] && [ $MAX -lt 60 ] && MAX=60
fi
CKOPT=()
echo "== 10-bit AFBC (AS01) vs P010 references, max frames ${MAX} (0 = all)"
run vp9p2 vp9-p2-2160p60.webm.p010le.framemd5 p010le $MAX env V4L2REQUEST_PIXFMT=AS01 $F -i vp9-p2-2160p60.webm -frames:v $(frames $MAX) -f null -
run hevc10 hevc-main10-2160p60.mkv.p010le.framemd5 p010le $MAX env V4L2REQUEST_PIXFMT=AS01 $F -i hevc-main10-2160p60.mkv -frames:v $(frames $MAX) -f null -
run avs2 cctv4k-10bit.p010.framemd5 yuv420p10le $MAX env AVS2_CAP=AFBC $A/avs2dec-afbc -o $FIFO -c $(frames $MAX) /tmp/cc.avs2
echo "== 8-bit AFBC (AS12) vs NV12 references, max frames ${MAX}"
run hevc8 hevc-main-2160p60.mkv.nv12.framemd5 nv12 $MAX env V4L2REQUEST_PIXFMT=AS12 $F -i hevc-main-2160p60.mkv -frames:v $(frames $MAX) -f null -
run vp9p0 vp9-p0-2160p60.webm.nv12.framemd5 nv12 $MAX env V4L2REQUEST_PIXFMT=AS12 $F -i vp9-p0-2160p60.webm -frames:v $(frames $MAX) -f null -
rm -f /tmp/cc.avs2 $FIFO
ls -la $D | sed 's/^/[dump] /'
dmesg | grep -iE 'cedrus|panfrost|iommu|fault|timed out' | tail -6 | sed 's/^/[dmesg] /'
echo "uptime $(cut -d" " -f1 /proc/uptime) cedrus-timeouts $(dmesg | grep -c "timed out")"
echo ROUND-DONE
