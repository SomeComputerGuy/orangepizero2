#!/bin/bash
# Install a test kernel + matching modules + matching Zero2 DTB on the board with the one-shot fallback armed.
# Usage: install-kernel.sh <tag>   (uses kernel-check/vdec-serve/Image.<tag>, modules-<tag>.tgz and, when present,
#                                   sun50i-h616-orangepi-zero2.dtb.<tag>; cumul-build.sh stages all three)
# DTB: the stock /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb is kept once as <name>.stock and the path becomes a
# symlink (U-Boot follows symlinks, as it does for /boot/Image) to <name>.vdec-<tag>. Restore with restore-kernel.sh
# (Image, DTB, modules); the fallback service re-points the DTB to .stock on every boot of a non-trial Image as well.
# Found by runner jobs 21/26 (2026-11-06): new DT nodes (g2d@1480000, writeback@10000) never reached the board because
# only the Image and the modules were installed.
set -e
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SV=$H/kernel-check/vdec-serve; t=$1
SSH=$H/harness/ssh.sh
DTB=sun50i-h616-orangepi-zero2.dtb; DTBDIR=/boot/dtb/allwinner
# Cumulative tags (c<N>) always install the newest one (AGENT-RULES "Builds"), also for sessions queued earlier.
if [[ $t =~ ^c[0-9]+$ ]]; then n=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)
  [ "$n" != "$t" ] && echo "install-kernel: $t -> newest cumulative tag $n"; t=$n; fi
# fallback service (if the image lacks it)
base64 -w0 $H/harness/research/vdec/vdec-fallback.sh | $SSH 'base64 -d > /usr/local/sbin/vdec-fallback.sh; chmod +x /usr/local/sbin/vdec-fallback.sh'
base64 -w0 $SV/vdec-fallback.service | $SSH 'base64 -d > /etc/systemd/system/vdec-fallback.service; systemctl daemon-reload; systemctl enable vdec-fallback.service 2>&1 | tail -1'
$S/ship.sh $SV/Image.$t /root/stage/Image.$t
$S/ship.sh $SV/modules-$t.tgz /root/stage/modules-$t.tgz
dtbcmd="echo 'no DTB for $t in kernel-check/vdec-serve: stock DTB kept'"
if [ -s $SV/$DTB.$t ]; then
  NOXZ=1 $S/ship.sh $SV/$DTB.$t /root/stage/$DTB.$t
  dtbcmd="d=$DTBDIR/$DTB; if [ -f \$d ] && [ ! -L \$d ]; then mv \$d \$d.stock; fi
  if [ -f \$d.stock ]; then cp /root/stage/$DTB.$t \$d.vdec-$t; ln -sfn $DTB.vdec-$t \$d; echo dtb \$(readlink \$d) md5 \$(md5sum < \$d | cut -c1-32)
  else echo 'DTB: no .stock copy and the path is not a regular file: DTB left alone'; fi"
fi
$SSH "set -e; cur=\$(readlink /boot/Image); kv=\$(uname -r); echo running \$kv Image=\$cur
rm -rf /lib/modules/7.3.1.good; if [ \$kv = 7.3.1 ] && [ -d /lib/modules/7.3.1 ]; then cp -a /lib/modules/7.3.1 /lib/modules/7.3.1.good; fi
cp /root/stage/Image.$t /boot/vmlinuz-7.3.1-vdec-$t
rm -rf /lib/modules/7.3.1; tar xzf /root/stage/modules-$t.tgz -C /lib/modules/; depmod 7.3.1
$dtbcmd
echo \$cur > /boot/vdec-trial; ln -sfn vmlinuz-7.3.1-vdec-$t /boot/Image; sync; echo armed fallback to \$cur"
