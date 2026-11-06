#!/bin/sh
# One-shot boot fallback for experimental kernels (installed as /usr/local/sbin/vdec-fallback.sh).
# Armed by /boot/vdec-trial (contains the last good kernel file name). If /run/vdec-ok does not
# appear within 300 s of boot, restore /boot/Image, the Zero2 DTB and /lib/modules/7.3.1 and reboot.
# The DTB follows the Image (install-kernel.sh): on every boot of a non-trial Image the DTB symlink
# is re-pointed to the .stock copy, for restores that only flipped /boot/Image.
dtb=/boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb
stock_dtb() { if [ -f "$dtb.stock" ] && [ -L "$dtb" ] && [ "$(readlink "$dtb")" != sun50i-h616-orangepi-zero2.dtb.stock ]; then
  ln -sfn sun50i-h616-orangepi-zero2.dtb.stock "$dtb"; sync; echo "vdec-fallback: DTB re-pointed to .stock" > /dev/kmsg; fi; }
case "$(readlink /boot/Image)" in vmlinuz-7.3.1-vdec-*) ;; *) stock_dtb ;; esac
[ -f /boot/vdec-trial ] || exit 0
good=$(cat /boot/vdec-trial)
sleep 300
[ -f /run/vdec-ok ] && { rm -f /boot/vdec-trial; sync; exit 0; }
echo "vdec-fallback: no ssh confirmation, restoring $good" > /dev/kmsg
ln -sfn "$good" /boot/Image
case "$good" in vmlinuz-7.3.1-vdec-*) ;; *) stock_dtb ;; esac
if [ -d /lib/modules/7.3.1.good ]; then rm -rf /lib/modules/7.3.1; cp -a /lib/modules/7.3.1.good /lib/modules/7.3.1; fi
rm -f /boot/vdec-trial; sync
systemctl reboot
