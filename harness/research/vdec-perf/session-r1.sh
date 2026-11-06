#!/bin/bash
# One board session for queue-depth round 1: acquire the lock, stage, run board-queue-r1.sh, fetch, release.
# The lock is released on every exit path (board stays on the image kernel; the round restores all devmem knobs).
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; O=$S/logs/queue-r1
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
mkdir -p $O
{ out=$($H/harness/board-lock.sh acquire vdec-r1) || exit 1; echo "$out"; case $out in *"already held"*) echo "lock already held under this owner, stop"; exit 1;; esac; }
trap '$H/harness/board-lock.sh release vdec-r1' EXIT
$SSH -n 'uname -rv; readlink /boot/Image; cat /boot/vdec-trial 2>/dev/null; ls /root/vp /root/avs2 | tr "\n" " "; echo; ls /root/vdec-streams | tr "\n" " "; echo; free -m | head -2' | tee $O/board-info.txt
$SSH -n 'set -e; U=http://10.56.0.1:8643; mkdir -p /root/vp /root/vdec-streams /root/avs2; cd /root/vdec-streams
for f in vp9-p2-2160p60.webm hevc-main10-2160p60.mkv vp9-p2-2160p60.webm.p010le.md5 hevc-main10-2160p60.mkv.p010le.md5; do [ -s $f ] || curl -sS -m 300 -o $f $U/q1/$f; done
cd /root/vp; for f in ffmpeg devmem.py; do [ -s $f ] || curl -sS -m 300 -o $f $U/q1/$f; done; chmod +x ffmpeg
curl -sS -o /root/avs2/avs2dec $U/avs2/avs2dec; chmod +x /root/avs2/avs2dec
sha256sum /root/vp/ffmpeg | cut -c1-16; ls -l /root/vdec-streams | wc -l; v4l2-ctl -d /dev/video0 --list-formats-out 2>&1 | grep -c "AVS2\|VP90\|HEVC"; v4l2-ctl --list-devices 2>&1 | head -12; which gst-launch-1.0 python3' 2>&1 | tee -a $O/board-info.txt
scp -q "${K[@]}" $S/ve-timeline.sh $S/board-queue-r1.sh root@10.56.0.107:/root/vp/
$SSH -n 'chmod +x /root/vp/ve-timeline.sh; timeout 5400 bash /root/vp/board-queue-r1.sh' 2>&1 | tee $O/round.txt
scp -q "${K[@]}" root@10.56.0.107:/tmp/f291.yuv $O/board-f291.yuv 2>/dev/null
$SSH -n 'rm -f /tmp/f291.yuv /tmp/vtl.trace; uname -r; readlink /boot/Image' | tee -a $O/round.txt
