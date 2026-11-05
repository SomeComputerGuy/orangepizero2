#!/bin/bash
# AFBC bit-exactness board session (pattern of vdec-perf/session-trial.sh, own lock owner): acquire the board lock,
# install cumulative kernel <tag> with the fallback armed (unless already booted), run board-queue-afbc.sh, fetch the
# results and any mismatch dumps, restore the image kernel, release. Usage: session-afbc.sh <tag>
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; T=${1:?tag}; O=$S/logs/queue-afbc
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OWN=afbc-check2; mkdir -p $O
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
restore() { $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  waitup && $SSH -n 'echo restored: $(uname -rv) $(readlink /boot/Image)' | tee -a $O/round.txt; }
{ out=$($H/harness/board-lock.sh acquire $OWN) || exit 1; echo "$out"; case $out in *"already held"*) exit 1;; esac; }
trap '$H/harness/board-lock.sh release '$OWN EXIT
date '+%F %T start' | tee $O/board-info.txt
$SSH -n 'uname -r; readlink /boot/Image' | tee -a $O/board-info.txt
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
$SSH -n 'uname -rv; touch /run/vdec-ok; ls /dev/video0 /dev/dri/renderD128' | tee -a $O/board-info.txt
scp -q "${K[@]}" $S/board-queue-afbc.sh root@10.56.0.107:/root/vp/
$SSH -n "timeout 3400 bash /root/vp/board-queue-afbc.sh" 2>&1 | tee $O/round.txt
scp -q "${K[@]}" 'root@10.56.0.107:/root/afbc/*.txt' $O/ 2>/dev/null
mkdir -p $H/kernel-check/afbc-dumps && scp -q "${K[@]}" 'root@10.56.0.107:/root/afbc/dump/*' $H/kernel-check/afbc-dumps/ 2>/dev/null
restore
date '+%F %T end' | tee -a $O/board-info.txt
