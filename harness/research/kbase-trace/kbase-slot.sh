#!/bin/bash
# Board slot for the Arm kbase + libmali g24p0 reference traces (GLES 3.2 GS/tess), on the IMAGE kernel.
# Nothing is installed into the system: bifrost_kbase.ko, the blob and the tools live in /root/armblob and the
# panfrost<->kbase switch is a runtime unbind/bind, so any reboot (or the 15 s systemd watchdog after a hang)
# comes back on panfrost.
# Usage: kbase-slot.sh stage|load|info|probe|trace [tests]|cmd '<shell>'|fetch|restore
set -e
H=/home/aruni/orangepizero2; T=$H/harness/research/kbase-trace; A=$H/harness/research/arm-blob
KO=$H/kernel-check/kbase-trial/src/drivers/gpu/arm/bifrost/bifrost_kbase.ko
SSH=$H/harness/ssh.sh
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
B=root@10.56.0.107; R=/root/armblob
ENV="LD_LIBRARY_PATH=$R/lib"
case $1 in
stage) $SSH -n "mkdir -p $R/lib $R/out; uname -a; dpkg-query -W -f='\${Version}\n' linux-image-edge-sunxi64"
       scp -q "${K[@]}" $KO $T/kbtrace.so $T/gles32probe $B:$R/
       scp -q "${K[@]}" $A/dl/libmali-bifrost-g31-g24p0-gbm.so $B:$R/lib/libmali.so.1
       $SSH -n "cd $R/lib; for l in libEGL.so.1 libGLESv2.so.2 libGLESv1_CM.so.1 libgbm.so.1 libOpenCL.so.1; do ln -sf libmali.so.1 \$l; done; ls -la $R $R/lib; modinfo -F vermagic $R/bifrost_kbase.ko" ;;
load)  $SSH -n "set -x; fuser -v /dev/dri/renderD128 2>&1 | tail -3; dmesg -C
         echo 1800000.gpu > /sys/bus/platform/drivers/panfrost/unbind; sleep 1
         insmod $R/bifrost_kbase.ko; sleep 2; dmesg | tail -40; ls -la /dev/mali0; ls /sys/class/misc/mali0/device/ 2>/dev/null | head -40" ;;
info)  $SSH -n "cat /sys/class/misc/mali0/device/gpuinfo 2>/dev/null; cat /sys/class/misc/mali0/device/power_policy; cat /sys/kernel/debug/clk/gpu0/clk_rate 2>/dev/null; cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | grep -i -A2 dcdc" ;;
probe) $SSH -n "rm -rf $R/out/probe; mkdir -p $R/out/probe; cd $R/out/probe; $ENV timeout 120 $R/gles32probe $R/out/probe ${2:-} ; echo rc=\$?; cat info.txt; dmesg | tail -15" ;;
trace) shift; $SSH -n "rm -rf $R/out/trace; mkdir -p $R/out/trace; cd $R/out/trace; $ENV KBTRACE_OUT=$R/out/trace/kbtrace.bin LD_PRELOAD=$R/kbtrace.so timeout 300 $R/gles32probe $R/out/trace $* ; echo rc=\$?; ls -la; tail -25 info.txt; dmesg | tail -5" ;;
cmd)   $SSH -n "cd $R; $ENV $2" ;;
fetch) mkdir -p $A/traces/${2:-run}; scp -q -r "${K[@]}" $B:$R/out/. $A/traces/${2:-run}/; ls -la $A/traces/${2:-run} ;;
restore) $SSH -n "set -x; rmmod bifrost_kbase; sleep 1; echo 1800000.gpu > /sys/bus/platform/drivers/panfrost/bind; sleep 2; ls -la /dev/dri; dmesg | grep -i panfrost | tail -5; cat /sys/class/devfreq/1800000.gpu/cur_freq" ;;
*) echo "usage: $0 stage|load|info|probe|trace [tests]|cmd '<shell>'|fetch [name]|restore"; exit 1 ;;
esac
