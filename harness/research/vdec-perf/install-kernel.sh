#!/bin/bash
# Install a test kernel + matching modules on the board with the one-shot fallback armed.
# Usage: install-kernel.sh <tag>   (uses kernel-check/vdec-serve/Image.<tag> and modules-<tag>.tgz)
set -e
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SV=$H/kernel-check/vdec-serve; t=$1
SSH=$H/harness/ssh.sh
# fallback service (if the image lacks it)
base64 -w0 $H/harness/research/vdec/vdec-fallback.sh | $SSH 'base64 -d > /usr/local/sbin/vdec-fallback.sh; chmod +x /usr/local/sbin/vdec-fallback.sh'
base64 -w0 $SV/vdec-fallback.service | $SSH 'base64 -d > /etc/systemd/system/vdec-fallback.service; systemctl daemon-reload; systemctl enable vdec-fallback.service 2>&1 | tail -1'
$S/ship.sh $SV/Image.$t /root/stage/Image.$t
$S/ship.sh $SV/modules-$t.tgz /root/stage/modules-$t.tgz
$SSH "set -e; cur=\$(readlink /boot/Image); kv=\$(uname -r); echo running \$kv Image=\$cur
rm -rf /lib/modules/7.3.1.good; if [ \$kv = 7.3.1 ] && [ -d /lib/modules/7.3.1 ]; then cp -a /lib/modules/7.3.1 /lib/modules/7.3.1.good; fi
cp /root/stage/Image.$t /boot/vmlinuz-7.3.1-vdec-$t
rm -rf /lib/modules/7.3.1; tar xzf /root/stage/modules-$t.tgz -C /lib/modules/; depmod 7.3.1
echo \$cur > /boot/vdec-trial; ln -sfn vmlinuz-7.3.1-vdec-$t /boot/Image; sync; echo armed fallback to \$cur"
