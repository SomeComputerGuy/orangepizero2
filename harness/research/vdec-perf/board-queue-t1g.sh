#!/bin/bash
# test1.avs2: all differing frames vs davs2, and where in the picture frames 380-384 / 888-896 differ (per plane, per LCU).
A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2; mkdir -p /root/avs2
curl -sS --fail $U/avs2dec-q -o $A && chmod +x $A || { echo "avs2dec-q download failed"; exit 1; }
for f in test1.avs2 test1.framemd5 test1-ref-sel.yuv; do curl -sS --fail $U/$f -o /root/avs2/$f || exit 1; done
echo "kernel $(uname -rv) timeouts $(dmesg | grep -c 'timed out')"
$A -f /root/avs2/test1.avs2 2>/dev/null | awk '/^frame/ {print $2, $6}' > /root/avs2/t1.got
paste -d' ' /root/avs2/t1.got /root/avs2/test1.framemd5 | awk '$2!=$4 {printf "%s ", $1} END {print ""}' | sed 's/^/[differing frames] /'
AVS2_DUMP=380,381,382,383,384,888,889,890,892,896 $A -o /root/avs2/t1-sel.yuv /root/avs2/test1.avs2 > /dev/null 2>&1
python3 -I - /root/avs2/t1-sel.yuv /root/avs2/test1-ref-sel.yuv <<'PY'
import sys
W,H=854,480; n=W*H*3//2; a=open(sys.argv[1],'rb').read(); b=open(sys.argv[2],'rb').read()
print('sizes', len(a), len(b))
for k,fr in enumerate((380,381,382,383,384,888,889,890,892,896)):
  x=a[k*n:(k+1)*n]; y=b[k*n:(k+1)*n]
  if x==y: print('frame %d identical' % fr); continue
  out=[]
  for name,off,w,h,s in (('Y',0,W,H,1),('U',W*H,(W+1)//2,H//2,2),('V',W*H+((W+1)//2)*(H//2),(W+1)//2,H//2,2)):
    cnt=0; mx=0; x0=y0=10**9; x1=y1=-1; lcus={}
    for r in range(h):
      ra=x[off+r*w:off+(r+1)*w]; rb=y[off+r*w:off+(r+1)*w]
      if ra==rb: continue
      for c in range(w):
        d=abs(ra[c]-rb[c])
        if d:
          cnt+=1; mx=max(mx,d); x0=min(x0,c); x1=max(x1,c); y0=min(y0,r); y1=max(y1,r)
          L=(c*s//32, r*s//32); lcus[L]=lcus.get(L,0)+1
    if cnt: out.append('%s %d px max %d box x %d-%d y %d-%d lcus(col,row) %s' % (name,cnt,mx,x0,x1,y0,y1,sorted(lcus)[:12]))
  print('frame %d: ' % fr + ' | '.join(out))
PY
echo "timeouts $(dmesg | grep -c 'timed out')"; rm -f /root/avs2/t1-sel.yuv /root/avs2/test1-ref-sel.yuv; echo ROUND-DONE
