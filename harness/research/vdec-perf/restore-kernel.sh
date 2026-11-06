#!/bin/bash
# Put the board back on the stock image kernel: Image symlink, Zero2 DTB (.stock), modules (7.3.1.good), fallback
# disarmed; then reboot unless NOREBOOT=1. The counterpart of install-kernel.sh. Usage: restore-kernel.sh
# Prints one line "restore: Image=<link> dtb=<link>"; the caller waits for the board and logs uname afterwards.
H=/home/aruni/orangepizero2; SSH=$H/harness/ssh.sh
STOCK=vmlinuz-7.3.1-edge-sunxi64; DTB=sun50i-h616-orangepi-zero2.dtb; DTBDIR=/boot/dtb/allwinner
$SSH -n "ln -sfn $STOCK /boot/Image; rm -f /boot/vdec-trial
d=$DTBDIR/$DTB; if [ -f \$d.stock ] && [ -L \$d ]; then ln -sfn $DTB.stock \$d; fi
if [ -d /lib/modules/7.3.1.good ]; then rm -rf /lib/modules/7.3.1; mv /lib/modules/7.3.1.good /lib/modules/7.3.1; fi
sync; echo restore: Image=\$(readlink /boot/Image) dtb=\$(readlink \$d 2>/dev/null || echo file)
[ -n \"${NOREBOOT:-}\" ] || (sleep 2; systemctl reboot) >/dev/null 2>&1 &"
