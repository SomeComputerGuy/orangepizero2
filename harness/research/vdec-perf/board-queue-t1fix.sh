#!/bin/bash
# AVS2 order-count fix (fix/sunxi-avs2-poc-base): test1.avs2 (854x480, LCU 32, 2096 pictures) must be bit-exact against
# davs2 on every frame with no VE timeout; the other AVS2 streams must stay bit-exact. Per-frame md5 list in /root/avs2/out.
cd /root || exit 1
A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2; mkdir -p /root/avs2/out; rm -f /root/avs2/out/*
curl -sS --fail $U/avs2dec-q -o $A && chmod +x $A || { echo "avs2dec-q download failed"; exit 1; }
for f in test1.avs2 test1.framemd5; do curl -sS --fail $U/$f -o /root/avs2/$f || { echo "download failed: $f"; exit 1; }; done
to() { dmesg | grep -c "timed out"; }
echo "kernel $(uname -rv) timeouts $(to)"
$A -p -v /root/avs2/test1.avs2 2>&1 | head -1 | sed 's/^/[seq] /'
# per-frame md5 against davs2 (test1.framemd5: "<frame> <md5>" per line, output order)
$A -f /root/avs2/test1.avs2 2>/root/avs2/out/t1.err | awk '/^frame/ {print $2, $6}' > /root/avs2/out/t1.got
paste -d' ' /root/avs2/out/t1.got /root/avs2/test1.framemd5 | awk '$2!=$4 {n++; printf "%s ", $1} END {print ""; print "[count] frames " NR " differing " n+0}' | sed '1s/^/[differing frames] /'
echo "[test1-perframe] decode errors $(grep -c error /root/avs2/out/t1.err) timeouts $(to)"
t() { # t <stream> <expected whole-stream md5>
  curl -sS --fail $U/$1 -o /tmp/s.avs2 || { echo "[$1] download failed"; return; }; t0=$(to); s=$(date +%s.%N)
  r=$(timeout 600 $A /tmp/s.avs2 2>/tmp/s.err | tail -1); rc=$?
  m=$(echo "$r" | awk '{print $NF}'); res=FAIL; [ "$m" = "$2" ] && res=PASS
  echo "[$1] $res $m rc=$rc $(printf %.1f $(echo "$(date +%s.%N) - $s" | bc))s new-timeouts $(( $(to) - t0 )) errors $(grep -c error /tmp/s.err) | $r"
}
t test1.avs2 $(curl -sS $U/test1.avs2.md5 | cut -c1-32)
t main-2160p-ra.avs2 3a3d5d7eb9a6f548042e160d9e461388
t cctv4k-10bit.avs2 be9985dea38abffc850d73024165c990
t main-1080p-ra.avs2 $(curl -sS $U/main-1080p-ra.avs2.md5 | cut -c1-32)
t BQSquare_416x240_60_ra.avs2 $(curl -sS $U/BQSquare_416x240_60_ra.avs2.md5 | cut -c1-32)
rm -f /tmp/s.avs2 /tmp/s.err /root/avs2/test1.avs2
echo "timeouts $(to)"; echo ROUND-DONE
