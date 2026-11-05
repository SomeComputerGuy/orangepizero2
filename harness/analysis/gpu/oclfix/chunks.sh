#!/bin/bash
# host: run the remaining fork CTS as <=20 min chunks, re-queueing for the board lock (FIFO) between chunks
cd /home/aruni/orangepizero2; T=mesa-work/oclfix/tests; O=mesa-work/oclfix/chunks; mkdir -p $O
c() { [ -f $O/$2.done ] && return; LOCKWAIT=86400 SETENV="$3" SETENV2="$4" $T/run-chunk.sh $T/$1 oclfix-$2 > $O/$2.txt 2>&1 && grep -q CHUNK-DONE $O/$2.txt && touch $O/$2.done; }
for i in $(seq $(wc -l < $T/cl-chunks.txt)); do c chunk-cl.sh cl$i IDX=$i PURGE=1; done
for i in $(seq $(wc -l < $T/cl-split.txt)); do c chunk-clsplit.sh clsplit$i IDX=$i; done
for l in gles31-khr-main gles31-main.0 gles31-main.1 gles31-main.2 gles31-main.3 gles31-main.4; do
  MEMMAX=600M PROPS="-p MemorySwapMax=64M -p OOMPolicy=continue" c chunk-gles.sh g-${l//./-} LIST=$l; done
echo ALL-CHUNKS-DONE > $O/all.done
