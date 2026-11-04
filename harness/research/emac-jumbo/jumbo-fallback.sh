#!/bin/sh
# One-shot boot fallback for the EMAC jumbo trial kernel (installed as /usr/local/sbin/jumbo-fallback.sh).
# Armed by /boot/jumbo-trial. If /run/jumbo-ok does not appear within 300 s of boot, restore the image
# kernel (/boot/Image and /boot/uInitrd symlinks back to the -edge-sunxi64 files) and its modules, then reboot.
[ -f /boot/jumbo-trial ] || exit 0
sleep 300
[ -f /run/jumbo-ok ] && exit 0
echo "jumbo-fallback: no confirmation, restoring image kernel" > /dev/kmsg
ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image
ln -sfn uInitrd-7.3.1-edge-sunxi64 /boot/uInitrd
if [ -d /lib/modules/7.3.1-edge-sunxi64.good ]; then
	rm -rf /lib/modules/7.3.1-edge-sunxi64
	cp -a /lib/modules/7.3.1-edge-sunxi64.good /lib/modules/7.3.1-edge-sunxi64
fi
rm -f /boot/jumbo-trial; sync
systemctl reboot
