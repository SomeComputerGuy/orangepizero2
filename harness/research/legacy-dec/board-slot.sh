#!/bin/bash
# Usage: board-slot.sh install|confirm|tests|restore
#  install : trial-install Image.legacy1 + modules (fallback armed, modules backup in 7.3.1.good, image DTB kept), reboot
#  confirm : after boot: check kernel, touch /run/vdec-ok (disarms fallback), stage the mpeg1 ffmpeg as /root/vp/ffmpeg-m1
#  tests   : MPEG-1 ISO (md5+raw), MPEG-2 1080 recheck (raw), frame-24 GMC dump, ISO MPEG-4 ASP/SP (md5+raw), all with ffmpeg-m1
#  restore : point /boot/Image back to the image kernel, restore modules, reboot
set -e
H=/home/aruni/orangepizero2; D=$H/harness/research/legacy-dec; R=$H/kernel-check/legacy-results; SSH=$H/harness/ssh.sh
case $1 in
install) $SSH -n "set -e; test -L /boot/Image; readlink /boot/Image > /root/legacy-good-kernel; cat /root/legacy-good-kernel; uname -a; sha256sum /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb | tee /root/legacy-good-dtb.sha"; $H/harness/research/vdec-perf/install-kernel.sh ${TAG:-legacy1}
         $SSH -n "cat /boot/vdec-trial; readlink /boot/Image; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &" ;;
confirm) $SSH -n "uname -v; touch /run/vdec-ok; dmesg | grep -i -m3 cedrus; cat /boot/vdec-trial 2>/dev/null; ls /dev/video*"
         $H/harness/research/vdec-perf/ship.sh $H/kernel-check/ffmpeg-afbc/install-mpeg1/opt/ffv4l2/bin/ffmpeg /root/vp/ffmpeg-m1
         $SSH -n "chmod +x /root/vp/ffmpeg-m1; /root/vp/ffmpeg-m1 -hide_banner -hwaccels | tail -3" ;;
tests)   export BFF=/root/vp/ffmpeg-m1
         bash $D/run-md5.sh $D/lists/mpeg1.list $R/mpeg1
         bash $D/run-raw.sh $D/lists/mpeg1.list $R/mpeg1-raw
         FRAMES=60 bash $D/run-raw.sh $D/lists/mpeg2-1080.list $R/mpeg2-1080-raw
         bash $D/gmc-f24.sh $R/gmc-f24
         RESUME=1 bash $D/run-md5.sh $D/lists/mpeg4asp.list $R/mpeg4asp
         bash $D/run-raw.sh $D/lists/mpeg4asp.list $R/mpeg4asp-raw
         bash $D/run-raw.sh $D/lists/mpeg4sp.list $R/mpeg4sp-raw2 ;;
restore) $SSH -n "set -e; g=\$(cat /root/legacy-good-kernel); [ -f /boot/\$g ]; ln -sfn \$g /boot/Image
         if [ -d /lib/modules/7.3.1.good ]; then rm -rf /lib/modules/7.3.1; cp -a /lib/modules/7.3.1.good /lib/modules/7.3.1; fi
         rm -f /boot/vdec-trial; sha256sum -c /root/legacy-good-dtb.sha; readlink /boot/Image; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &" ;;
esac
