#!/bin/bash
# Host side, one board slot on a cumulative kernel: cedrus v4l2-compliance (stock + patched),
# control G/TRY/S sweep, and the AVS2 test1 "frame processing timed out" reproduction.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/ssh.sh; D=$H/harness/research/cedrus-compliance
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
scp -q "${K[@]}" $D/ctrltry root@10.56.0.107:/root/
$S "mkdir -p /root/avs2"; scp -q "${K[@]}" $H/kernel-check/vdec-serve/avs2/avs2dec root@10.56.0.107:/root/avs2/avs2dec
$D/build-v4l2c-board.sh "$1"
$S 'uname -rv; echo "== ctrltry"; /root/ctrltry /dev/video0 | grep -v "^ok"
echo "== stock"; v4l2-compliance -d /dev/video0 > /root/v4l2c-stock.txt 2>&1; grep -E "fail:|Total|Detected" /root/v4l2c-stock.txt
echo "== patched"; /root/v4l2c/v4l2-compliance -d /dev/video0 > /root/v4l2c-patched.txt 2>&1; grep -E "fail:|Total|Detected" /root/v4l2c-patched.txt
for v in /dev/video*; do d=$(v4l2-ctl -d $v -D | awk -F: "/Driver name/{gsub(/ /,\"\",\$2);print \$2;exit}"); echo "== $v $d (patched)"; /root/v4l2c/v4l2-compliance -d $v 2>&1 | grep -E "fail:|Total"; done
echo "== AVS2 test1 timeouts"; ls -la /root/avs2/avs2dec; n0=$(dmesg | grep -c "frame processing timed out")
t0=$(date +%s); curl -sS http://10.56.0.1:8643/avs2/test1.avs2 | timeout 90 /root/avs2/avs2dec -f - > /root/t1.txt 2>&1; echo "rc=$? $(( $(date +%s) - t0 ))s frames=$(grep -c "^frame" /root/t1.txt) timeouts=$(( $(dmesg | grep -c "frame processing timed out") - n0 ))"; grep -m3 -i "error" /root/t1.txt
n0=$(dmesg | grep -c "frame processing timed out"); curl -sS http://10.56.0.1:8643/avs2/BQSquare_416x240_60_ra.avs2 | timeout 120 /root/avs2/avs2dec -f - > /root/t2.txt 2>&1; echo "control BQSquare_ra rc=$? frames=$(grep -c "^frame" /root/t2.txt) timeouts=$(( $(dmesg | grep -c "frame processing timed out") - n0 ))"
dmesg | grep -iE "iommu|page fault" | tail -3'
