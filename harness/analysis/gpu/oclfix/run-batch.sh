#!/bin/bash
# host: acquire the board, run one batch script under a systemd unit, wait, print summary, release.
# usage: run-batch.sh <batch.sh> <unit>
cd /home/aruni/orangepizero2; B=$1; U=$2
harness/board-lock.sh acquire opencl-fixes ${LOCKWAIT:-7200} || exit 1
[ -n "$DEPLOY" ] && MESA_ENV=/home/aruni/orangepizero2/mesa-work/tools/env-cl.sh mesa-work/tools/deploy.sh build-cl cl
. harness/ssh-opts.sh; scp -q "${BOARD_SSH_OPTS[@]}" mesa-work/oclfix/tests/*.py mesa-work/oclfix/tests/*.sh root@10.56.0.107:/root/opiz2-mesa/
harness/ssh.sh "systemd-run --unit=$U --collect -p MemoryMax=${MEMMAX:-700M} ${PROPS} ${SETENV:+--setenv=$SETENV} ${SETENV2:+--setenv=$SETENV2} sh /root/opiz2-mesa/$(basename $B) >/dev/null 2>&1"
sleep 5; while harness/ssh.sh "systemctl is-active -q $U"; do sleep 30; done
harness/ssh.sh "journalctl -u $U -o cat --since -3h | tail -20"
harness/board-lock.sh release opencl-fixes
