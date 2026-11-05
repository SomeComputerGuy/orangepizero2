#!/bin/bash
# AVS2 picture-size fix (cedrus PIC_SIZE rounded up to 8): test1.avs2 (854x480, LCU 32, 2096 pictures) must decode
# bit-exact against davs2 without a single VE timeout; regression of the other AVS2 streams.
cd /root || exit 1
A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2
mkdir -p /root/avs2; curl -sS --fail $U/avs2dec-q -o $A && chmod +x $A || { echo "avs2dec-q download failed"; exit 1; }
to() { dmesg | grep -c "timed out"; }
echo "kernel $(uname -rv) timeouts-at-start $(to)"
t() { # t <stream> <expected md5>
  curl -sS $U/$1 -o /tmp/s.avs2; t0=$(to); s=$(date +%s.%N)
  r=$(timeout 600 $A /tmp/s.avs2 2>/tmp/s.err | tail -1); rc=$?
  m=$(echo "$r" | awk '{print $NF}'); res=FAIL; [ "$m" = "$2" ] && res=PASS
  echo "[$1] $res $m rc=$rc $(printf %.1f $(echo "$(date +%s.%N) - $s" | bc))s new-timeouts $(( $(to) - t0 )) errors $(grep -c error /tmp/s.err) | $r"
}
t test1.avs2 $(curl -sS $U/test1.avs2.md5 | cut -c1-32)
t main-2160p-ra.avs2 3a3d5d7eb9a6f548042e160d9e461388
t cctv4k-10bit.avs2 be9985dea38abffc850d73024165c990
t main-1080p-ra.avs2 $(curl -sS $U/main-1080p-ra.avs2.md5 | cut -c1-32)
t BQSquare_416x240_60_ra.avs2 $(curl -sS $U/BQSquare_416x240_60_ra.avs2.md5 2>/dev/null | cut -c1-32)
rm -f /tmp/s.avs2 /tmp/s.err
echo "timeouts-at-end $(to)"; echo ROUND-DONE
