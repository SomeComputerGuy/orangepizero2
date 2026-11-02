#!/bin/sh
# One-shot boot fallback for experimental kernels (installed as /usr/local/sbin/vdec-fallback.sh).
# Armed by /boot/vdec-trial (contains the last good kernel file name). If /run/vdec-ok does not
# appear within 300 s of boot, restore /boot/Image and /lib/modules/7.3.1 and reboot.
[ -f /boot/vdec-trial ] || exit 0
good=$(cat /boot/vdec-trial)
sleep 300
[ -f /run/vdec-ok ] && { rm -f /boot/vdec-trial; sync; exit 0; }
echo "vdec-fallback: no ssh confirmation, restoring $good" > /dev/kmsg
ln -sfn "$good" /boot/Image
if [ -d /lib/modules/7.3.1.good ]; then rm -rf /lib/modules/7.3.1; cp -a /lib/modules/7.3.1.good /lib/modules/7.3.1; fi
rm -f /boot/vdec-trial; sync
systemctl reboot
