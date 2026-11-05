#!/bin/bash
# Board session with a trial kernel: acquire, install <tag> (fallback armed), reboot, confirm, run board-queue-<r>.sh,
# restore the image kernel, reboot, verify, release. Usage: session-trial.sh <tag> <round>
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; T=${1:?tag}; R=${2:?round}; O=$S/logs/queue-$R
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
mkdir -p $O
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
restore() { $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  waitup && $SSH -n 'echo restored: $(uname -rv) $(readlink /boot/Image)' | tee -a $O/round.txt; }
$H/harness/board-lock.sh acquire vdec-queue || exit 1
trap '$H/harness/board-lock.sh release vdec-queue' EXIT
$SSH -n 'uname -r; readlink /boot/Image' | tee $O/board-info.txt
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32)
have=$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')
if [ "$have" = "$want" ]; then
  echo "$T already booted (Image md5 $want), skipping the install" | tee -a $O/board-info.txt
else
  [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || { echo "board not on the image kernel, stop"; exit 1; }
  $S/install-kernel.sh $T 2>&1 | tail -3 | tee -a $O/board-info.txt
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  if ! waitup; then echo "trial did not come up; the fallback reverts on the next boot" | tee -a $O/round.txt; exit 1; fi
fi
$SSH -n 'uname -rv; touch /run/vdec-ok; ls /dev/video0' | tee -a $O/board-info.txt
scp -q "${K[@]}" $S/ve-timeline.sh $S/board-queue-$R.sh root@10.56.0.107:/root/vp/
$SSH -n "chmod +x /root/vp/ve-timeline.sh; MHZ=${MHZ:-600} timeout 3600 bash /root/vp/board-queue-$R.sh" 2>&1 | tee $O/round.txt
restore
