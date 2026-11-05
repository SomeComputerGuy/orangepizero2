#!/bin/bash
# Round 4 session on cumulative kernel <tag>: install (fallback armed), run board-queue-r4.sh (parts A, B), reboot with
# iommu.passthrough=1 cma=640M (armbianEnv extraargs, backed up), run part C, restore armbianEnv + image kernel, verify.
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; T=${1:?tag}; O=$S/logs/queue-r4
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
mkdir -p $O
waitup() { for i in $(seq 1 150); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
reboot_() { $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15; waitup; }
restore() {
  $SSH -n '[ -f /boot/armbianEnv.txt.vdec ] && mv /boot/armbianEnv.txt.vdec /boot/armbianEnv.txt; ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync'
  reboot_ && $SSH -n 'echo restored: $(uname -rv) $(readlink /boot/Image) cmdline-iommu: $(grep -o "iommu[^ ]*\|cma[^ ]*" /proc/cmdline | tr "\n" " ")' | tee -a $O/round.txt
}
$H/harness/board-lock.sh acquire vdec-queue || exit 1
trap '$H/harness/board-lock.sh release vdec-queue' EXIT
$SSH -n 'uname -r; readlink /boot/Image; grep -n extraargs /boot/armbianEnv.txt; free -m | sed -n 2p' | tee $O/board-info.txt
[ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || { echo "board not on the image kernel, stop"; exit 1; }
$S/install-kernel.sh $T 2>&1 | tail -3 | tee -a $O/board-info.txt
if ! reboot_; then echo "trial did not come up" | tee -a $O/round.txt; exit 1; fi
$SSH -n 'uname -rv; touch /run/vdec-ok' | tee -a $O/board-info.txt
scp -q "${K[@]}" $S/ve-timeline.sh $S/board-queue-r4.sh root@10.56.0.107:/root/vp/
$SSH -n "chmod +x /root/vp/ve-timeline.sh; timeout 3000 bash /root/vp/board-queue-r4.sh" 2>&1 | tee $O/round.txt
# passthrough boot of the same trial kernel; the fallback is one-shot, so re-arm it
$SSH -n 'set -e; cp /boot/armbianEnv.txt /boot/armbianEnv.txt.vdec
if grep -q "^extraargs=" /boot/armbianEnv.txt; then sed -i "s/^extraargs=\(.*\)$/extraargs=\1 iommu.passthrough=1 cma=640M/" /boot/armbianEnv.txt; else echo "extraargs=iommu.passthrough=1 cma=640M" >> /boot/armbianEnv.txt; fi
grep extraargs /boot/armbianEnv.txt; echo vmlinuz-7.3.1-edge-sunxi64 > /boot/vdec-trial; systemctl is-enabled vdec-fallback.service' 2>&1 | tee -a $O/round.txt
if reboot_; then
  $SSH -n 'touch /run/vdec-ok; cat /proc/cmdline' | tee -a $O/round.txt
  $SSH -n "PART=C timeout 2400 bash /root/vp/board-queue-r4.sh" 2>&1 | tee -a $O/round.txt
else echo "passthrough boot did not come up" | tee -a $O/round.txt; fi
restore
