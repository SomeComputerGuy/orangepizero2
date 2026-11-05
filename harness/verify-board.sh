#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Board-side regression check for the Orange Pi Zero2 image. Runs on the host:
#   harness/verify-board.sh            # all checks except suspend
#   SUSPEND=1 harness/verify-board.sh  # also an s2idle + RTC wake round trip
# Prints one line per check: PASS/FAIL/INFO <name>: <detail>
set -uo pipefail
cd "$(dirname "$0")/.."
exec harness/ssh.sh "SUSPEND=${SUSPEND:-0} bash -s" <<'REMOTE'
r() { printf '%-4s %-22s %s\n' "$1" "$2" "$3"; }
ok() { if eval "$2"; then r PASS "$1" "$3"; else r FAIL "$1" "$3"; fi; }
d=$(dmesg)
r INFO kernel "$(uname -r), up $(cut -d. -f1 /proc/uptime)s"
n=$(grep -c 'using dummy regulator' <<<"$d"); ok dummy-regulators "[ $n -le 1 ]" "$n ($(grep -o 'supply [a-z-]* not found' <<<"$d" | sort -u | tr '\n' ' '))"
n=$(grep -c 'blend mode not setup' <<<"$d"); ok drm-blend-warnings "[ $n -eq 0 ]" "$n"
n=$(grep -c 'WCN_ERR' <<<"$d"); ok wcn-errors "[ $n -eq 0 ]" "$n"
ok mmc-aliases "[ -e /proc/device-tree/aliases/mmc0 ] && [ -e /proc/device-tree/aliases/mmc1 ]" "$(ls /proc/device-tree/aliases | tr '\n' ' ')"
ok sd-is-mmcblk0 "[ \"\$(readlink -f /dev/disk/by-path/platform-4020000.mmc)\" = /dev/mmcblk0 ]" "$(readlink -f /dev/disk/by-path/platform-4020000.mmc)"
z=$(grep -l cpu /sys/class/thermal/thermal_zone*/type | head -1 | xargs dirname)
t=$(cat $z/trip_point_*_temp | tr '\n' ' '); cd0=$(ls -d $z/cdev* 2>/dev/null | wc -l)
ok cpu-thermal-trips "grep -q 85000 <<<'$t' && [ $cd0 -ge 1 ]" "trips: $t cdevs: $cd0 now: $(($(cat $z/temp)/1000))C"
g=$(ls -d /sys/class/devfreq/*gpu* 2>/dev/null | head -1)
ok gpu-devfreq "[ -n '$g' ]" "${g:+$(cat $g/available_frequencies) gov=$(cat $g/governor) cur=$(cat $g/cur_freq)}"
ok cpufreq "[ -e /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies ]" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies 2>/dev/null)"
v=$(grep -l cedrus /sys/class/video4linux/*/name 2>/dev/null | head -1); ok cedrus "[ -n '$v' ]" "$v $(grep -c 'cedrus.*iommu\|1c0e000.*iommu' <<<"$d") iommu-lines"
r INFO hwmon "$(cat /sys/class/hwmon/*/name | tr '\n' ' ')"
ok ethernet "ip -br -4 a show end0 | grep -q 10.56" "$(ethtool end0 2>/dev/null | grep -E 'Speed' | xargs)"
ok rsb-axp "grep -q 'AXP20X driver loaded' <<<\"\$d\"" "$(grep -o 'AXP[0-9]* found' <<<"$d")"
ip link set wlan0 up 2>/dev/null; sleep 2; s=$(iw dev wlan0 scan 2>/dev/null || (sleep 3; iw dev wlan0 scan)); n24=$(grep -cE 'freq: 24[0-9]{2}' <<<"$s"); n5=$(grep -cE 'freq: 5[0-9]{3}' <<<"$s")
ok wifi-scan "[ $n24 -gt 0 ] && [ $n5 -gt 0 ]" "2.4GHz: $n24 BSS, 5GHz: $n5 BSS"
r INFO wifi-regdomain "$(iw reg get | grep -E '^(global|phy|country)' | tr '\n' ' ')"
ok bluetooth "hciconfig hci0 2>/dev/null | grep -q 'UP RUNNING'" "$(systemctl is-active aw859a-bluetooth aw859a-wifi | tr '\n' ' ')"
f=$(systemctl --failed --no-legend | awk '{print $2}' | tr '\n' ' '); ok failed-units "[ -z '$f' ]" "$f"
w=$(journalctl -b -p warning --no-pager -q | grep -cE 'tmpfiles.*file flags|EXTRA_OPTS|ConfigurationDirectory'); ok bsp-journal-warnings "[ $w -eq 0 ]" "$w"
ok fstab-sd-wear "findmnt -no OPTIONS / | grep -q noatime && findmnt -no FSTYPE /var/spool/cups | grep -q tmpfs" "$(findmnt -no OPTIONS /)"
# minimal image: systemd-networkd shows the client ID. Server image (NetworkManager): the merged NM
# config must carry ipv4.dhcp-client-id=mac and end0 must hold the static lease, which the harness DHCP
# server only hands to client ID 01:<MAC>.
if systemctl is-active -q NetworkManager; then
  ok dhcp-client-id-mac "NetworkManager --print-config | grep -qx 'ipv4.dhcp-client-id=mac' && ip -br -4 a show end0 | grep -q '10.56.0.107/'" "NetworkManager"
else
  ok dhcp-client-id-mac "networkctl status end0 --no-pager | grep -q 'Client ID: 02:00'" "systemd-networkd"
fi
# GStreamer must autoplug the software jpegdec, not v4l2jpegdec (cannot drive cedrus; impl-di-jpeg-avs.md 7.6).
# ssh sessions get /etc/environment through pam_env, like a login.
if command -v gst-launch-1.0 >/dev/null; then
  gst-launch-1.0 -q videotestsrc num-buffers=1 ! video/x-raw,width=64,height=48 ! jpegenc ! filesink location=/tmp/vb.jpg >/dev/null 2>&1
  jd=$(timeout 30 gst-launch-1.0 -v filesrc location=/tmp/vb.jpg ! jpegparse ! decodebin ! fakesink 2>&1 | grep -oE '(v4l2)?jpegdec[0-9]+' | sort -u | tr '\n' ' '); rm -f /tmp/vb.jpg
  ok gst-jpeg-autoplug "grep -qx 'GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL' /etc/environment && systemctl show -p DefaultEnvironment | grep -q v4l2jpegdec:MARGINAL && grep -q '^jpegdec' <<<'$jd'" "decoder: $jd"
fi
r INFO eth-mtu "end0 mtu $(cat /sys/class/net/end0/mtu) (max $(ip -d link show end0 | grep -o 'maxmtu [0-9]*' | cut -d' ' -f2))"
ok cups "systemctl is-active -q cups && lpstat -r | grep -q running" "$(cupsd -v 2>/dev/null | head -1)"
ok scan-stack "command -v scanimage >/dev/null && [ -e /usr/lib/aarch64-linux-gnu/sane/libsane-airscan.so.1 ] && [ -e /usr/lib/aarch64-linux-gnu/sane/libsane-hpaio.so.1 ] && grep -qE '^\s*interface\s*=\s*all' /etc/ipp-usb/ipp-usb.conf && systemctl is-enabled -q saned.socket && systemctl is-active -q saned.socket" "$(scanimage -V 2>/dev/null | head -1)"
ok watchdog "[ -e /dev/watchdog0 ]" "$(systemctl show -p RuntimeWatchdogUSec --value)"
ok hwrng "grep -q . /sys/class/misc/hw_random/rng_current" "$(cat /sys/class/misc/hw_random/rng_current)"
r INFO kernel-warnings "$(dmesg -l err,warn | wc -l) err/warn lines: $(dmesg -l err,warn | cut -c16- | sed -E 's/0x[0-9a-f]+|\b[0-9a-f]{16}\b//g' | sort | uniq -c | sort -rn | head -6 | sed 's/^ *//' | tr '\n' '|')"
if [ "$SUSPEND" = 1 ]; then
  t0=$(date +%s); rtcwake -m freeze -s 10 >/dev/null 2>&1; rc=$?; dt=$(( $(date +%s) - t0 ))
  ok s2idle "[ $rc -eq 0 ] && [ $dt -lt 30 ]" "rc=$rc ${dt}s; wifi after: $(ip -br link show wlan0 | awk '{print $2}')"
fi
REMOTE
