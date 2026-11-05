#!/bin/bash
# test1.avs2 (854x480) per-frame md5 against davs2 and a 3-frame dump for a plane-by-plane diff.
A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2; mkdir -p /root/avs2
curl -sS --fail $U/avs2dec-q -o $A && chmod +x $A || { echo "avs2dec-q download failed"; exit 1; }
curl -sS --fail $U/test1.avs2 -o /tmp/t1.avs2 && curl -sS --fail $U/test1.framemd5 -o /tmp/t1.ref || exit 1
echo "kernel $(uname -rv) timeouts $(dmesg | grep -c 'timed out')"
$A -v -c 3 -o /root/t1-3.yuv /tmp/t1.avs2 2>&1 | grep -iE "sequence|format|bytesperline|sizeimage|width|height" | head -8
$A -f /tmp/t1.avs2 2>/dev/null | awk '/^frame/ {print $2, $6}' > /tmp/t1.got
echo "frames got $(wc -l < /tmp/t1.got) ref $(wc -l < /tmp/t1.ref) differing $(paste -d' ' /tmp/t1.got /tmp/t1.ref | awk '$2!=$4' | wc -l)"
paste -d' ' /tmp/t1.got /tmp/t1.ref | awk '$2!=$4 {print "[diff] frame", $1, $2, "ref", $4}' | head -10
ls -l /root/t1-3.yuv; echo "timeouts $(dmesg | grep -c 'timed out')"; echo ROUND-DONE
