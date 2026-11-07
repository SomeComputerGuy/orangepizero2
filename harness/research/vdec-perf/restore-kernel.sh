#!/bin/bash
# Put the board back on the stock image kernel: Image symlink, Zero2 DTB (.stock), modules (<release>.good), fallback
# disarmed; then reboot unless NOREBOOT=1. The counterpart of install-kernel.sh. Usage: restore-kernel.sh
# The stock kernel is the image's own: the newest /boot/vmlinuz-*-edge-sunxi64 (7.3.1 before the 2026-11-06 image,
# 7.3.3 since), never a trial vmlinuz-*-vdec-*.
# Prints one line "restore: Image=<link> dtb=<link>"; the caller waits for the board and logs uname afterwards.
H=/home/aruni/orangepizero2; SSH=$H/harness/ssh.sh
DTB=sun50i-h616-orangepi-zero2.dtb; DTBDIR=/boot/dtb/allwinner
$SSH -n "STOCK=\$(cd /boot && ls -1 vmlinuz-*-edge-sunxi64 2>/dev/null | sort -V | tail -1)
[ -n \"\$STOCK\" ] || { echo 'restore: no /boot/vmlinuz-*-edge-sunxi64 on the board, nothing changed'; exit 1; }
ln -sfn \$STOCK /boot/Image; rm -f /boot/vdec-trial
d=$DTBDIR/$DTB; if [ -f \$d.stock ] && [ -L \$d ]; then ln -sfn $DTB.stock \$d; fi
for g in /lib/modules/*.good; do [ -d \$g ] || continue; rm -rf \${g%.good}; mv \$g \${g%.good}; done
sync; echo restore: Image=\$(readlink /boot/Image) dtb=\$(readlink \$d 2>/dev/null || echo file)
[ -n \"${NOREBOOT:-}\" ] || (sleep 2; systemctl reboot) >/dev/null 2>&1 &"
