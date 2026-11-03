#!/bin/bash
# Ship a host file to the board over HTTP in <512 KiB pieces (end0 bulk TCP stalls at 512 KiB).
# Usage: ship.sh <local file> <board path>
set -e
f=$1; dst=$2; H=/home/aruni/orangepizero2; SV=$H/kernel-check/vdec-serve
n=$(basename "$f"); d=$SV/ship/$n; rm -rf "$d"; mkdir -p "$d"
if [ -n "$NOXZ" ]; then cp "$f" "$d/x"; DEC=cat; else xz -T0 -6 -c "$f" > "$d/x"; DEC="xz -d"; fi; (cd "$d" && split -b 400k -d -a 3 x p. && rm x)
cnt=$(ls "$d" | wc -l); sha=$(sha256sum "$f" | cut -d' ' -f1)
timeout 900 $H/harness/ssh.sh "set -e; t=\$(mktemp -d /root/ship.XXXX); cd \$t; for i in \$(seq 0 $((cnt-1))); do p=\$(printf p.%03d \$i); for try in 1 2 3; do curl -sS -m 30 -o \$p http://10.56.0.1:8643/ship/$n/\$p && break; done; done; cat p.* | $DEC > x; echo \"$sha  x\" | sha256sum -c --quiet; mkdir -p \$(dirname $dst); mv x $dst; cd /; rm -rf \$t; echo shipped $dst $sha"
