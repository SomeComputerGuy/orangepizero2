#!/bin/sh
# Companion to vdec-fallback.sh for the DE33 trial (installed as
# /usr/local/sbin/de33-fallback.sh). Armed by /boot/de33-trial. If /run/vdec-ok
# does not appear within 280 s of boot, restore the saved DTB and armbianEnv.txt;
# vdec-fallback.sh restores Image/modules and reboots at 300 s.
[ -f /boot/de33-trial ] || exit 0
sleep 280
[ -f /run/vdec-ok ] && { rm -f /boot/de33-trial; sync; exit 0; }
echo "de33-fallback: no ssh confirmation, restoring DTB and armbianEnv.txt" > /dev/kmsg
while read -r saved orig; do [ -f "$saved" ] && cp "$saved" "$orig"; done < /boot/de33-trial
rm -f /boot/de33-trial; sync
