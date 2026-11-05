#!/bin/bash
# One board session for queue-depth round <r>: acquire the lock, stage, run board-queue-<r>.sh, fetch, release.
# The lock is released on every exit path (board stays on the image kernel; the round restores all devmem knobs).
H=/home/aruni/orangepizero2; S=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh; R=${1:?round, e.g. r2}; O=$S/logs/queue-$R
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
mkdir -p $O
$H/harness/board-lock.sh acquire vdec-queue || exit 1
trap '$H/harness/board-lock.sh release vdec-queue' EXIT
$SSH -n 'uname -rv; readlink /boot/Image; cat /boot/vdec-trial 2>/dev/null; ls /root/vp /root/avs2 | tr "\n" " "; echo; ls /root/vdec-streams | tr "\n" " "; echo; free -m | head -2' | tee $O/board-info.txt
$SSH -n 'set -e; U=http://10.56.0.1:8643; mkdir -p /root/vp /root/vdec-streams /root/avs2; cd /root/vdec-streams
for f in vp9-p2-2160p60.webm hevc-main10-2160p60.mkv vp9-p2-2160p60.webm.p010le.md5 hevc-main10-2160p60.mkv.p010le.md5; do [ -s $f ] || curl -sS -m 300 -o $f $U/q1/$f; done
cd /root/vp; for f in ffmpeg devmem.py; do [ -s $f ] || curl -sS -m 300 -o $f $U/q1/$f; done; chmod +x ffmpeg
curl -sS -o /root/avs2/avs2dec $U/avs2/avs2dec; chmod +x /root/avs2/avs2dec
sha256sum /root/vp/ffmpeg | cut -c1-16; ls -l /root/vdec-streams | wc -l; v4l2-ctl -d /dev/video0 --list-formats-out 2>&1 | grep -c "AVS2\|VP90\|HEVC"; v4l2-ctl --list-devices 2>&1 | head -12; which gst-launch-1.0 python3' 2>&1 | tee -a $O/board-info.txt
scp -q "${K[@]}" $S/ve-timeline.sh $S/board-queue-$R.sh root@10.56.0.107:/root/vp/
$SSH -n "chmod +x /root/vp/ve-timeline.sh; timeout 5400 bash /root/vp/board-queue-$R.sh" 2>&1 | tee $O/round.txt
scp -q "${K[@]}" root@10.56.0.107:/tmp/f291.yuv $O/board-f291.yuv 2>/dev/null
$SSH -n 'rm -f /tmp/f291.yuv /tmp/vtl.trace; uname -r; readlink /boot/Image' | tee -a $O/round.txt
