#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner package: MPEG-1 as V4L2_PIX_FMT_MPEG1_SLICE ('MG1S') on cedrus, shared FFmpeg 0304/0309.  run-job.sh [chunks]
# Self-contained (pattern of harness/vp9-vectors/run-job.sh): board lock with a fresh owner name per acquire; chunk
# "stock" runs on the stock image kernel (coded formats, software fallback of the MG1S hwaccel, v4l2-compliance
# baseline); then the newest cumulative kernel (kernel-check/cumulative-kernels.txt; it must contain the MG1S commit
# $FIX, else BLOCKED) is installed with the vdec fallback armed and the chunks fmts compliance md5 dpic raw mpeg2 run,
# each under a timeout; results are written on the host as they are produced; the stock kernel is restored and the
# lock released at the end and before every hand-over. Resumable: chunks in $OUT/state are skipped.
# Exit 0 = all chunks ran (pass/fail: check-results.sh, see HANDOFF.md); 2 = blocked ($OUT/BLOCKED); 1 = setup error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/mpeg1-mg1s; VP=$H/harness/research/vdec-perf; LD=$H/harness/research/legacy-dec
SSH=$H/harness/ssh.sh; SERVE=$H/kernel-check/legacy-serve; U=http://10.56.0.1:8644
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
FIX=8140b4eeb241ea13b872edbe93dadac618de2130   # armbian-build fix/sunxi-cedrus-mpeg1-mg1s (MG1S uAPI + cedrus)
BIN=$H/kernel-check/ffmpeg-deb/build-mg1s/ffmpeg; export BFF=/root/mg1s/ffmpeg   # static FFmpeg, shared set final 908ab79544
CHUNKS=${*:-stock fmts compliance md5 dpic raw mpeg2}
OUT=$S/logs/runner; mkdir -p $OUT; touch $OUT/state; rm -f $OUT/BLOCKED
CK=$H/kernel-check/cumulative-kernels.txt; TL=$(tail -1 $CK); T=$(cut -d' ' -f1 <<< "$TL"); SHA=$(cut -d' ' -f3 <<< "$TL")
git -C $H/wt-cumulative merge-base --is-ancestor $FIX $SHA 2>/dev/null || {
  echo "newest cumulative kernel $T ($SHA) does not contain fix/sunxi-cedrus-mpeg1-mg1s $FIX" | tee $OUT/BLOCKED; exit 2; }
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
[ -x $BIN ] || { echo "board FFmpeg missing: $BIN (harness/mpeg1-mg1s/build-ffmpeg.sh)"; exit 1; }
for f in mpeg2/ccm1.mpg mpeg2/tcela-18.bits mpeg2/tcela-16.bits mpeg2/tcela-15.bits gen/mpeg1-1080p30.m1v; do [ -s $SERVE/$f ] || { echo "stream missing: $SERVE/$f"; exit 1; }; done
OWN=""; CDEV=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-mg1s-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image' 2>/dev/null)" = vmlinuz-7.3.1-edge-sunxi64 ]; }
restore() { on_stock && [ "$($SSH -n 'uname -v' 2>/dev/null)" = "$STOCKV" ] && return 0
  $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
serve() { # 8643: kernel/binary shipping (vdec-serve); 8644: the test streams (legacy-serve)
  curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ || { log "starting the HTTP server on 10.56.0.1:8643 (kernel-check/vdec-serve)"
    (cd $H/kernel-check/vdec-serve && nohup python3 -m http.server --bind 10.56.0.1 8643 > $OUT/http-8643.log 2>&1 &); sleep 2; }
  curl -s -m 5 -o /dev/null $U/ || { log "starting the HTTP server on 10.56.0.1:8644 (kernel-check/legacy-serve)"
    (cd $SERVE && nohup python3 -m http.server --bind 10.56.0.1 8644 > $OUT/http-8644.log 2>&1 &); sleep 2; }
  curl -s -m 5 -o /dev/null http://10.56.0.1:8643/ && curl -s -m 5 -o /dev/null $U/mpeg2/ccm1.mpg; }
irq() { $SSH -n "awk '/1c0e000.video-codec/{print \$2+\$3+\$4+\$5}' /proc/interrupts"; }
cedrus_dev() { CDEV=$($SSH -n 'for v in /dev/video*; do v4l2-ctl -d $v -D 2>/dev/null | grep -q "Driver name *: *cedrus" && { echo $v; break; }; done'); [ -n "$CDEV" ]; }
ship_ff() { $SSH -n 'mkdir -p /root/mg1s'; $VP/ship.sh $BIN /root/mg1s/ffmpeg 2>&1 | tail -1 | tee -a $OUT/runner.log
  $SSH -n "chmod +x $BFF; $BFF -hide_banner -hwaccels" > $OUT/ff-hwaccels.txt 2>&1
  grep -q v4l2request $OUT/ff-hwaccels.txt || blocked "board FFmpeg has no v4l2request hwaccel (ff-hwaccels.txt)"; }
fmts() { # coded formats of every video node, MG1S frame sizes on cedrus
  $SSH -n 'for v in /dev/video*; do n=${v#/dev/}; d=$(v4l2-ctl -d $v -D 2>/dev/null | awk -F: "/Driver name/{gsub(/ /,\"\",\$2);print \$2;exit}")
    echo "== $v $(cat /sys/class/video4linux/$n/name) driver=$d"; v4l2-ctl -d $v --list-formats-out 2>&1 | grep -E "\[[0-9]+\]"; done' > $OUT/fmts-$1.txt 2>&1
  $SSH -n "v4l2-ctl -d $CDEV --list-framesizes MG1S 2>&1; echo '-- MG2S'; v4l2-ctl -d $CDEV --list-framesizes MG2S 2>&1" > $OUT/framesizes-$1.txt 2>&1; }
compliance() { $SSH -n "timeout 600 v4l2-compliance -d $CDEV" > $OUT/compliance-$1.txt 2>&1
  $SSH -n "test -x /root/v4l2c/v4l2-compliance && timeout 600 /root/v4l2c/v4l2-compliance -d $CDEV" > $OUT/compliance-$1-patched.txt 2>&1
  log "compliance $1: $(grep -h 'Total for' $OUT/compliance-$1.txt | tail -1)"; }
swfb() { # MPEG-1 with -hwaccel v4l2request but no hw output format: FFmpeg falls back to software when the hwaccel cannot
  # initialise. Compare with pure software (same binary) and count cedrus IRQs: same=1 irqs=0 means software only.
  local tsv=$OUT/swfb-$1.tsv; : > $tsv
  while read -r tag rel opts; do [ -z "$tag" ] && continue
    i0=$(irq); a=$($SSH -n "timeout 600 $BFF -nostdin -hide_banner -loglevel verbose -hwaccel v4l2request $opts -i $U/$rel -fps_mode passthrough -pix_fmt yuv420p -f rawvideo - 2>/root/mg1s/swfb.err | md5sum | cut -d' ' -f1")
    i1=$(irq); $SSH -n 'cat /root/mg1s/swfb.err' > $OUT/swfb-$1-$tag.err 2>&1
    b=$($SSH -n "timeout 600 $BFF -nostdin -hide_banner -loglevel warning $opts -i $U/$rel -fps_mode passthrough -pix_fmt yuv420p -f rawvideo - 2>/dev/null | md5sum | cut -d' ' -f1")
    printf '%s\thwaccel_md5=%s\tsw_md5=%s\tsame=%s\tirqs=%s\n' "$tag" "$a" "$b" "$([ "$a" = "$b" ] && echo 1 || echo 0)" "$((i1-i0))" | tee -a $tsv
  done < $S/lists/mg1s-swfb.list; }
dpic() { # tcela-18: 31 D-pictures, 720x480; exact reference = legacy-dec/m1-dpic.py (flat DC blocks, IDCT-independent)
  python3 -I $LD/m1-dpic.py $SERVE/mpeg2/tcela-18.bits > $OUT/dpic-ref.nv12 2> $OUT/dpic-ref.err
  i0=$(irq)
  $SSH -n "timeout 600 $BFF -nostdin -hide_banner -loglevel verbose -hwaccel v4l2request -hwaccel_output_format drm_prime -f mpegvideo -i $U/mpeg2/tcela-18.bits -fps_mode passthrough -vf hwdownload,format=nv12 -f rawvideo -" > $OUT/dpic-hw.nv12 2> $OUT/dpic.err; rc=$?
  i1=$(irq); r=$(python3 -I $LD/cmp-raw.py 720 480 $OUT/dpic-ref.nv12 $OUT/dpic-hw.nv12)
  printf 'm1-tcela-18\tmpeg2/tcela-18.bits\t720x480\trc=%s\tirqs=%s\tvs-dpic-ref: %s\n' "$rc" "$((i1-i0))" "$r" | tee $OUT/dpic.txt
  grep -h 'D-pictures are' $OUT/dpic.err | head -1 | tee -a $OUT/dpic.txt; rm -f $OUT/dpic-hw.nv12 $OUT/dpic-ref.nv12; }
boot_trial() {
  on_stock || blocked "board not on the stock image kernel at start ($($SSH -n 'readlink /boot/Image'))"
  $VP/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  { echo "cumulative $TL"; $SSH -n 'uname -rv'; } > $OUT/kernel.txt
  cedrus_dev || blocked "no cedrus video node on $T"
  $SSH -n "test -x $BFF" || ship_ff; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
run_chunk() { local c=$1 t0=$(date +%s)
  case $c in
    stock) fmts stock; swfb stock; compliance stock ;;
    fmts) fmts test ;;
    compliance) compliance test ;;
    md5) timeout 900 bash $LD/run-md5.sh $S/lists/mg1s-md5.list $OUT/md5 > $OUT/md5.out 2>&1; cat $OUT/md5/summary.tsv | tee -a $OUT/runner.log ;;
    dpic) dpic ;;
    raw) timeout 1500 bash $LD/run-raw.sh $S/lists/mg1s-raw.list $OUT/raw > $OUT/raw.out 2>&1; cut -c1-200 $OUT/raw/raw.tsv | tee -a $OUT/runner.log ;;
    mpeg2) timeout 900 bash $LD/run-md5.sh $S/lists/mg1s-mpeg2.list $OUT/mpeg2 > $OUT/mpeg2.out 2>&1; cat $OUT/mpeg2/summary.tsv | tee -a $OUT/runner.log ;;
  esac
  $SSH -n 'dmesg | grep -iE "cedrus|timed out|iommu|fault|oops|bug:|warning|alloc fail" | tail -40' > $OUT/dmesg-$c.txt 2>&1
  echo $c >> $OUT/state; log "chunk $c done in $(( $(date +%s) - t0 )) s"; }
log "job mpeg1-mg1s start, kernel $T ($SHA, Image md5 $want), FFmpeg $(md5sum < $BIN | cut -c1-32), chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
serve || { echo "HTTP servers on 10.56.0.1:8643/8644 not reachable" > $OUT/BLOCKED; exit 2; }
trap 'release' EXIT
acquire
on_stock || blocked "board not on the stock image kernel at start ($($SSH -n 'readlink /boot/Image'))"
STOCKV=$($SSH -n 'uname -v'); echo "stock $($SSH -n 'uname -rv')" > $OUT/kernel-stock.txt
cedrus_dev || blocked "no cedrus video node on the stock kernel"
if ! grep -qx stock $OUT/state && grep -qw stock <<< "$CHUNKS"; then ship_ff; log "chunk stock start (on the stock kernel $STOCKV)"; run_chunk stock; fi
booted=0
for c in $CHUNKS; do
  [ $c = stock ] && continue; grep -qx "$c" $OUT/state && continue
  if [ $booted = 1 ] && others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; booted=0; fi
  [ $booted = 1 ] || { boot_trial; booted=1; }
  log "chunk $c start"; run_chunk $c
done
restore; release
bash $S/check-results.sh $OUT > $OUT/check.txt 2>&1; log "check-results: $(tail -1 $OUT/check.txt)"
log "job end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
