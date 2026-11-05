#!/bin/bash
# host: Images Kernel 3D (no timeout) as one long idle-board slot, after chunks.sh; one 3D image type per unit,
# acquired only when the lock is free with an empty queue (re-checked before each type), resumable per type.
cd /home/aruni/orangepizero2; T=mesa-work/oclfix/tests; O=mesa-work/oclfix/chunks; mkdir -p $O
until [ -f $O/all.done ]; do sleep 300; done
idle() { [ "$(harness/board-lock.sh status)" = free ]; }
for i in 1 2 3; do
  [ -f $O/k3d$i.done ] && continue
  until idle; do sleep 120; done
  LOCKWAIT=600 SETENV=IDX=$i SETENV2=LISTF=cl-3d.txt $T/run-chunk.sh $T/chunk-clsplit.sh oclfix-k3d$i > $O/k3d$i.txt 2>&1 \
    && grep -q CHUNK-DONE $O/k3d$i.txt && touch $O/k3d$i.done
done
echo K3D-DONE > $O/k3d.done
