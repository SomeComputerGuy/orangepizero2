#!/bin/bash
# One board slot for the JPEG greyscale/4:1:1 probe and the DI fix check,
# on top of the 4321861ff image (trial kernel "jpegtrial": image series +
# DI fixes + JPEG FORCE_420 vendor rule + TRIAL probe parameters).
# Usage: jpeg-slot.sh install|confirm|stage|probe|tests|restore
#  install : [TAG=jpegfix] trial-install Image.$TAG (default jpegtrial) + modules (one-shot fallback armed), reboot
#  confirm : after boot: check kernel and parameters, touch /run/vdec-ok (disarms the fallback)
#  stage   : copy jpegtest, probe.sh, run.sh, probe vectors, J vectors and the DI tools
#  probe   : run probe.sh, fetch kernel-check/jpeg-probe/out, print analyze-probe.py
#  greyprobe: [TAG=greytrial kernel] run probe-grey.sh, fetch kernel-check/jpeg-probe/grey-out, analyze
#  tests   : [PROBE=bits] J1-J13 (run.sh + check.sh) with that variant, D2 2048x1280 4:2:2, D6 TNR, D7 conversions
#  restore : point /boot/Image back to the image kernel, reboot
set -e
H=/home/aruni/orangepizero2; J=$H/harness/jpegtest; SSH=$H/harness/ssh.sh
PV=$H/kernel-check/jpeg-probe; JV=$H/kernel-check/jpeg-vectors; DI=$H/kernel-check/board-di
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
B=root@10.56.0.107
case $1 in
install) $SSH -n "set -e; test -L /boot/Image; readlink /boot/Image > /root/jpeg-good-kernel; cat /root/jpeg-good-kernel; uname -a"
         $H/harness/research/vdec-perf/install-kernel.sh ${TAG:-jpegtrial}
         $SSH -n "cat /boot/vdec-trial; readlink /boot/Image; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &" ;;
confirm) $SSH -n "uname -rv; touch /run/vdec-ok; ls /sys/module/*/parameters/jpeg_probe /sys/module/*/parameters/jpeg_grey 2>/dev/null || echo no-probe-params; dmesg | grep -i -m3 'cedrus\|di300'; ls /dev/video*" ;;
stage)   $SSH -n "mkdir -p /root/jprobe /root/jpeg /root/di"
         scp -q "${K[@]}" $J/jpegtest $J/probe.sh $J/probe-grey.sh $PV/*.jpg $B:/root/jprobe/
         scp -q "${K[@]}" $J/jpegtest $J/run.sh $JV/*.jpg $JV/cases.txt $B:/root/jpeg/
         scp -q "${K[@]}" $H/harness/di300test/di300test $H/harness/di300test/di300err \
             $DI/m576.in.yuv $DI/m576n.in.yuv $DI/m576.nv12.yuv $DI/m576.nv16.yuv $DI/m576.nv21.yuv \
             $DI/m576.yv12.yuv $DI/m576.422p.yuv $DI/m2048.nv16.yuv $DI/m2048.nv61.yuv $DI/m2048.422p.yuv $B:/root/di/
         $SSH -n "ls /root/jprobe /root/jpeg | wc -l; ls /root/di" ;;
probe)   $SSH -n "rm -rf /root/jprobe/out; sh /root/jprobe/probe.sh /root/jprobe" | tee $PV/probe-run.txt
         rm -rf $PV/out; scp -q -r "${K[@]}" $B:/root/jprobe/out $PV/
         python3 -I $J/analyze-probe.py $PV $PV/out | tee $PV/probe-summary.txt ;;
greyprobe) $SSH -n "rm -rf /root/jprobe/out; sh /root/jprobe/probe-grey.sh /root/jprobe" | tee $PV/grey-run.txt
         rm -rf $PV/grey-out; scp -q -r "${K[@]}" $B:/root/jprobe/out $PV/grey-out
         python3 -I $J/analyze-probe.py $PV $PV/grey-out | tee $PV/grey-summary.txt ;;
tests)   $SSH -n "P=\$(ls /sys/module/*/parameters/jpeg_probe 2>/dev/null); [ -n \"\$P\" ] && echo ${PROBE:-0} > \$P; rm -rf /root/jpeg/out-nv12; sh /root/jpeg/run.sh /root/jpeg nv12 >/dev/null 2>&1; cat /root/jpeg/out-nv12/results.txt /root/jpeg/out-nv12/perf.txt"
         rm -rf $JV/out-nv12; scp -q -r "${K[@]}" $B:/root/jpeg/out-nv12 $JV/
         bash $J/check.sh $JV nv12 | tee $JV/check-trial.txt
         $SSH -n "cd /root/di; dmesg -C; D='-W 720 -H 576'
           echo '== D2 2048x1280 4:2:2'; for f in nv16 nv61 422p; do timeout 60 ./di300test -W 2048 -H 1280 -f \$f -m weave -c weave -i m2048.\$f.yuv 2>&1 | tail -1; done; dmesg | grep -c 'Page fault' || true
           echo '== D6 TNR'; for t in fixed adaptive; do timeout 60 ./di300test \$D -f i420 -F yv12 -m field -t \$t -i m576n.in.yuv -o /tmp/tnr.\$t.yuv 2>&1 | tail -1; done
           timeout 60 ./di300test \$D -f i420 -F yv12 -m field -t off -i m576n.in.yuv -o /tmp/tnr.off.yuv 2>&1 | tail -1
           timeout 60 ./di300test \$D -f i420 -F yv12 -m tnr -t fixed -i m576n.in.yuv -o /tmp/tnr.only.yuv 2>&1 | tail -1
           echo '== D7'; for p in 'nv12 yv12' 'nv12 i420' 'nv21 yv12' 'nv16 422p' 'nv61 422p'; do set -- \$p; timeout 60 ./di300test \$D -f \$1 -F \$2 -m weave -i m576.\$1.yuv -o /tmp/c.\$1.\$2.yuv 2>&1 | tail -1; done
           v4l2-ctl -d /dev/video1 --set-fmt-video-out=width=720,height=576,pixelformat=YU12 --try-fmt-video=pixelformat=NV12 2>&1 | grep -i 'pixel format' | tail -1
           timeout 30 ./di300err; dmesg | grep -iE 'di300|deinterlace|timed out|Page fault' | tail -5"
         mkdir -p $DI/trial; scp -q "${K[@]}" "$B:/tmp/tnr.*.yuv" "$B:/tmp/c.*.yuv" $DI/trial/ ;;
restore) $SSH -n "set -e; g=\$(cat /root/jpeg-good-kernel); [ -e /boot/\$g ]; ln -sfn \$g /boot/Image; rm -f /boot/vdec-trial; readlink /boot/Image; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &" ;;
*) echo "usage: $0 install|confirm|stage|probe|tests|restore"; exit 1 ;;
esac
