#!/bin/bash
# Usage: locate.sh <serve-rel-path> <first> <last> <idct> [input opts]  -- HW vs SW frames first..last: per frame the
# macroblocks with |diff| > 4 (row,col), bbox, count, and the picture types (host ffprobe).
H=$(cd "$(dirname "$0")/../../.." && pwd); T=$H/kernel-check/legacy-tmp; rel=$1; a=$2; b=$3; idct=$4; shift 4; opts="$*"
wh=$(ffprobe -v error $opts -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$H/kernel-check/legacy-serve/$rel" | head -1)
sel="select='between(n\,$a\,$b)'"
$H/harness/ssh.sh -n "/root/vp/ffmpeg -nostdin -hide_banner -loglevel error -hwaccel v4l2request -hwaccel_output_format drm_prime $opts -i http://10.56.0.1:8644/$rel -vf hwdownload,format=nv12,$sel -fps_mode passthrough -f rawvideo -" > $T/loc.hw
ffmpeg -nostdin -loglevel error -idct $idct $opts -i "$H/kernel-check/legacy-serve/$rel" -vf "select='between(n,$a,$b)'" -fps_mode passthrough -pix_fmt nv12 -f rawvideo - > $T/loc.sw
types=$(ffprobe -v error $opts -show_entries frame=pict_type,interlaced_frame -of csv=p=0 "$H/kernel-check/legacy-serve/$rel" | sed -n "$((a+1)),$((b+1))p" | tr '\n' ' ')
python3 -I - $T/loc.sw $T/loc.hw ${wh/,/ } $a "$types" <<'PY'
import sys, numpy as np
W,H=int(sys.argv[3]),int(sys.argv[4]); a0=int(sys.argv[5]); types=sys.argv[6].split(); fs=W*H*3//2
x=np.fromfile(sys.argv[1],np.uint8).astype(int); y=np.fromfile(sys.argv[2],np.uint8).astype(int)
for n in range(min(x.size,y.size)//fs):
    Y=np.abs(x[n*fs:n*fs+W*H]-y[n*fs:n*fs+W*H]).reshape(H,W); big=np.argwhere(Y>4)
    t=types[n] if n<len(types) else '?'
    if big.size:
        mbs=sorted(set((int(r)//16,int(c)//16) for r,c in big))
        print(a0+n,t,'max',Y.max(),'pix>4',len(big),'MBs',len(mbs),mbs[:6],'bbox y',big[:,0].min(),big[:,0].max(),'x',big[:,1].min(),big[:,1].max())
    else: print(a0+n,t,'max',Y.max())
PY
