#!/bin/bash
# Untranslated-VE CMA diagnosis session (untr2) on cumulative kernel <tag> (must include feat/sunxi-h616-vdec-untranslated).
# A: default DT. B: overlay vdec-untranslated + cma=640M (sizing). C: overlay + the measured CMA size (md5 + memory
# pressure). armbianEnv.txt is backed up and restored, the overlay file removed, the image kernel restored.
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; T=${1:?tag}; O=$S/logs/queue-untr2
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
OWN=vdec-untr2; mkdir -p $O; : > $O/round.txt
[[ $T =~ ^c[0-9]+$ ]] && T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)
waitup() { for i in $(seq 1 150); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
reboot_() { $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15; waitup; }
arm() { $SSH -n 'echo vmlinuz-7.3.1-edge-sunxi64 > /boot/vdec-trial; sync'; }
run() { $SSH -n "touch /run/vdec-ok; MODE=$1 TH=${2:-0} timeout 2400 bash /root/vp/board-queue-untr2.sh" 2>&1 | tee -a $O/round.txt; }
env_set() { # env_set <cma size>: overlay on, cma=<size>
  $SSH -n "set -e; [ -f /boot/armbianEnv.txt.vdec ] || cp /boot/armbianEnv.txt /boot/armbianEnv.txt.vdec; cp /boot/armbianEnv.txt.vdec /boot/armbianEnv.txt
    E=/boot/armbianEnv.txt; d=\$(dirname \$(readlink -f /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb))/overlay
    curl -sS -o \$d/sun50i-h616-vdec-untranslated.dtbo http://10.56.0.1:8643/sun50i-h616-vdec-untranslated.dtbo
    if grep -q '^overlays=' \$E; then sed -i 's/^overlays=\(.*\)\$/overlays=\1 vdec-untranslated/' \$E; else echo 'overlays=vdec-untranslated' >> \$E; fi
    if grep -q '^extraargs=' \$E; then sed -i 's/^extraargs=\(.*\)\$/extraargs=\1 cma=$1/' \$E; else echo 'extraargs=cma=$1' >> \$E; fi
    grep -E '^(overlay_prefix|overlays|extraargs)=' \$E; ls -l \$d/sun50i-h616-vdec-untranslated.dtbo" 2>&1 | tee -a $O/round.txt; }
restore() {
  $SSH -n 'd=$(dirname $(readlink -f /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb))/overlay; rm -f $d/sun50i-h616-vdec-untranslated.dtbo
    [ -f /boot/armbianEnv.txt.vdec ] && mv /boot/armbianEnv.txt.vdec /boot/armbianEnv.txt; ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync'
  reboot_ && $SSH -n 'echo restored: $(uname -rv) $(readlink /boot/Image) cmdline-cma: $(grep -o "cma=[^ ]*" /proc/cmdline) overlays: $(grep ^overlays= /boot/armbianEnv.txt)' | tee -a $O/round.txt; }
{ out=$($H/harness/board-lock.sh acquire $OWN) || exit 1; echo "$out"; case $out in *"already held"*) echo "lock already held by $OWN, stop"; exit 1;; esac; }
trap '$H/harness/board-lock.sh release '$OWN EXIT
$SSH -n 'uname -r; readlink /boot/Image; grep -E "^(overlay_prefix|overlays|extraargs)=" /boot/armbianEnv.txt' | tee $O/board-info.txt
[ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || { echo "board not on the image kernel, stop"; exit 1; }
echo "tag $T" | tee -a $O/board-info.txt
$S/install-kernel.sh $T 2>&1 | tail -3 | tee -a $O/board-info.txt
reboot_ || { echo "trial did not come up" | tee -a $O/round.txt; exit 1; }
scp -q "${K[@]}" $S/ve-timeline.sh $S/board-queue-untr2.sh root@10.56.0.107:/root/vp/
env_set 640M; arm
if reboot_; then run D; else echo "overlay boot did not come up" | tee -a $O/round.txt; fi
restore
