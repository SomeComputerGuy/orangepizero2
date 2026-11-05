#!/bin/sh
# SPDX-License-Identifier: MIT
# Board side: OPi5 backport checks (impl-opi5-backports.md).
#   bp-board.sh state OUT        snapshot cpufreq/devfreq/clk/USB/SPI NOR/v4l2-compliance into OUT/
#   bp-board.sh cycles N OUT     N x "rtcwake -m mem -s 5" (deep), per-cycle line in OUT/cycles.txt,
#                                200 MB tmpfs hash before/after; run detached (systemd-run)
set -u
cmd=$1
state() { o=$1; mkdir -p "$o"
	uname -rv > "$o/uname.txt"
	for p in /sys/devices/system/cpu/cpufreq/policy*; do
		echo "$p gov=$(cat $p/scaling_governor) cur=$(cat $p/scaling_cur_freq) hw=$(cat $p/cpuinfo_cur_freq 2>/dev/null) min=$(cat $p/scaling_min_freq) max=$(cat $p/scaling_max_freq)"
		cat $p/stats/time_in_state 2>/dev/null | tr '\n' ' '; echo; done > "$o/cpufreq.txt"
	for d in /sys/class/devfreq/*; do echo "$d gov=$(cat $d/governor) cur=$(cat $d/cur_freq) target=$(cat $d/target_freq) min=$(cat $d/min_freq) max=$(cat $d/max_freq) trans=$(cat $d/trans_stat 2>/dev/null | tail -1)"; done > "$o/devfreq.txt"
	cat /sys/kernel/debug/clk/clk_summary > "$o/clk_summary.txt" 2>/dev/null
	lsusb -t > "$o/lsusb.txt" 2>&1; lsusb >> "$o/lsusb.txt" 2>&1
	for u in /sys/bus/usb/devices/usb*; do echo "$u $(cat $u/product) rt=$(cat $u/power/runtime_status)"; done >> "$o/lsusb.txt"
	m=$(grep -l . /sys/class/mtd/mtd*/name 2>/dev/null | head -1)
	{ cat /proc/mtd; for d in /dev/mtd[0-9]; do [ -c $d ] && echo "$d $(dd if=$d bs=64k 2>/dev/null | sha256sum | cut -c1-16) $(dd if=$d bs=64k 2>/dev/null | wc -c)"; done; } > "$o/spinor.txt" 2>&1
	: > "$o/v4l2c.txt"
	for v in /dev/video*; do drv=$(v4l2-ctl -d $v -D 2>/dev/null | awk -F: '/Driver name/{gsub(/ /,"",$2);print $2; exit}')
		[ "$drv" = cedrus ] || continue
		echo "=== $v" >> "$o/v4l2c.txt"; timeout 120 v4l2-compliance -d $v >> "$o/v4l2c.txt" 2>&1
	done
	grep -E '^=== |Total for|fail:' "$o/v4l2c.txt" > "$o/v4l2c-summary.txt"
	dmesg > "$o/dmesg.txt"
}
cycles() { n=$1; o=$2; mkdir -p "$o"; f=$o/cycles.txt; : > "$f"
	echo deep > /sys/power/mem_sleep
	mkdir -p /run/bpt; mountpoint -q /run/bpt || mount -t tmpfs -o size=220m tmpfs /run/bpt
	head -c 200M /dev/urandom > /run/bpt/blob; h0=$(sha256sum /run/bpt/blob | cut -c1-16); echo "hash0 $h0" >> "$f"
	g=$(ls -d /sys/class/devfreq/* | head -1); p=/sys/devices/system/cpu/cpufreq/policy0
	for i in $(seq 1 $n); do
		e0=$(dmesg -l err,warn | wc -l); t0=$(date +%s.%N)
		rtcwake -m mem -s 5 > /dev/null 2>&1; rc=$?
		t1=$(date +%s.%N); sleep 2
		e1=$(dmesg -l err,warn | wc -l)
		echo "$i rc=$rc dt=$(awk "BEGIN{printf \"%.1f\", $t1 - $t0}") cpu=$(cat $p/scaling_cur_freq)/$(cat $p/cpuinfo_cur_freq 2>/dev/null) gpu=$(cat $g/cur_freq) gpugov=$(cat $g/governor) newerr=$((e1 - e0)) wake=$(cat /sys/power/suspend_stats/success 2>/dev/null)/$(cat /sys/power/suspend_stats/fail 2>/dev/null)" >> "$f"
		sleep 3
	done
	h1=$(sha256sum /run/bpt/blob | cut -c1-16); echo "hash1 $h1 $( [ "$h0" = "$h1" ] && echo SAME || echo DIFF)" >> "$f"
	rm -f /run/bpt/blob; umount /run/bpt
	echo DONE >> "$f"
}
case $cmd in state) state "$2" ;; cycles) cycles "$2" "$3" ;; esac
