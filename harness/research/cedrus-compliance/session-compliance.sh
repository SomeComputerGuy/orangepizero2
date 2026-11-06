#!/bin/bash
# Host side, one board slot on a cumulative kernel already installed and confirmed:
# control G/TRY/S sweep + stock and patched v4l2-compliance on every video node, results copied
# to c-board/<tag>/. Usage: session-compliance.sh <tag> <patched-src.tgz>
set -u
H=/home/aruni/orangepizero2; S=$H/harness/ssh.sh; D=$H/harness/research/cedrus-compliance
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
scp -q "${K[@]}" $D/ctrltry root@10.56.0.107:/root/
$D/build-v4l2c-board.sh "$2"
$S 'mkdir -p /root/cres; cd /root/cres; uname -rv | tee uname.txt
echo "== ctrltry"; /root/ctrltry /dev/video0 > ctrltry.txt 2>&1; grep -v "^ok" ctrltry.txt
for v in /dev/video*; do n=${v#/dev/}; d=$(v4l2-ctl -d $v -D | awk -F: "/Driver name/{gsub(/ /,\"\",\$2);print \$2;exit}")
  v4l2-compliance -d $v > stock-$n.txt 2>&1; /root/v4l2c/v4l2-compliance -d $v > patched-$n.txt 2>&1
  for k in stock patched; do echo "== $v $d $k"; grep -E "Detected|fail:|warn:|Total" $k-$n.txt; done; done'
mkdir -p $D/c-board/$1; $S 'tar cz -C /root/cres .' | tar xz -C $D/c-board/$1; ls $D/c-board/$1
