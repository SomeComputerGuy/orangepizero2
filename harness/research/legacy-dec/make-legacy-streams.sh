#!/bin/bash
# Generate the legacy-codec throughput/feature streams on the host (FFmpeg 8.1 + libxvid/libvpx/libx264),
# with software-decode references (NV12 framemd5 + whole-stream md5). Usage: make-legacy-streams.sh <outdir>
set -e; O=${1:?outdir}; mkdir -p "$O"; cd "$O"
N=300   # 5 s at 60 fps
SRC="-f lavfi -i testsrc2=size=1920x1080:rate=60,noise=alls=10:allf=t+u"
SRCI="-f lavfi -i testsrc2=size=1920x1080:rate=30,noise=alls=10:allf=t+u"
e() { out=$1; shift; [ -s "$out" ] || ffmpeg -hide_banner -loglevel error -y "$@" -frames:v $N "$out"; }
# MPEG-2 MP@HL progressive 1080p60, B-frames, 40 Mbit/s (HL max 80)
e mpeg2-mphl-1080p60.m2v $SRC -c:v mpeg2video -profile:v 4 -level:v 4 -b:v 40M -maxrate 80M -bufsize 9781248 -g 15 -bf 2
# MPEG-2 MP@HL 1080i (frame pictures, interlaced DCT + field MC), 30 frames/s = 60 fields/s
e mpeg2-mphl-1080i30.m2v $SRCI -c:v mpeg2video -profile:v 4 -level:v 4 -b:v 40M -maxrate 80M -bufsize 9781248 -g 15 -bf 2 -flags +ildct+ilme -top 1
# MPEG-1 1080p (for the record: no userspace path to the MG2S engine for MPEG-1)
e mpeg1-1080p30.m1v $SRCI -c:v mpeg1video -b:v 30M -g 15 -bf 2
# MPEG-4 SP (no B, no qpel) and ASP variants, FFmpeg encoder
e mpeg4-sp-1080p60.avi $SRC -c:v mpeg4 -b:v 30M -g 30 -bf 0 -flags +mv4
e mpeg4-asp-bf-qpel-1080p60.avi $SRC -c:v mpeg4 -b:v 30M -g 30 -bf 2 -flags +mv4+qpel -mbd rd -trellis 1
e mpeg4-asp-ilace-1080i30.avi $SRCI -c:v mpeg4 -b:v 30M -g 30 -bf 2 -flags +ildct+ilme -top 1
# Xvid (libxvid): B-frames; B + qpel; B + GMC; B + qpel + GMC
e xvid-bf-1080p60.avi $SRC -c:v libxvid -b:v 30M -g 30 -bf 2
e xvid-qpel-1080p60.avi $SRC -c:v libxvid -b:v 30M -g 30 -bf 2 -flags +qpel
e xvid-gmc-1080p60.avi $SRC -c:v libxvid -b:v 30M -g 30 -bf 2 -gmc 1
e xvid-qpel-gmc-1080p60.avi $SRC -c:v libxvid -b:v 30M -g 30 -bf 2 -flags +qpel -gmc 1
# Xvid GMC with real global motion: a pan (translation) and a rotation+zoom (affine)
e xvid-gmc-pan-1080p60.avi -f lavfi -i "testsrc2=size=2560x1440:rate=60,crop=1920:1080:x='t*90':y='t*40',noise=alls=6:allf=t+u" -c:v libxvid -b:v 30M -g 60 -bf 2 -gmc 1
e xvid-gmc-rot-1080p60.avi -f lavfi -i "testsrc2=size=1920x1080:rate=60,rotate=a='t*0.08':c=gray,scale=w='trunc(1920*(1+0.04*t)/2)*2':h='trunc(1080*(1+0.04*t)/2)*2':eval=frame,crop=1920:1080,noise=alls=6:allf=t+u" -c:v libxvid -b:v 30M -g 60 -bf 2 -gmc 1 -flags +qpel
# H.263 baseline: largest baseline source format is 16CIF 1408x1152 (1080p is not expressible in H.263 BP)
e h263-bp-16cif.h263 -f lavfi -i testsrc2=size=1408x1152:rate=60,noise=alls=10:allf=t+u -c:v h263 -b:v 20M -g 30
e h263-bp-4cif.h263 -f lavfi -i testsrc2=size=704x576:rate=60,noise=alls=10:allf=t+u -c:v h263 -b:v 8M -g 30
# Sorenson Spark (FLV1) 1080p60
e flv1-spark-1080p60.flv $SRC -c:v flv -b:v 30M -g 30
# VP8 1080p60 with alt-ref frames
e vp8-1080p60.webm $SRC -c:v libvpx -b:v 20M -g 60 -auto-alt-ref 1 -lag-in-frames 16 -deadline good -cpu-used 4 -threads 8
# H.264 High 1080i MBAFF (x264 interlaced = MBAFF), CABAC + 8x8
e h264-high-1080i-mbaff.mkv $SRCI -c:v libx264 -profile:v high -level 4.2 -b:v 30M -flags +ildct -x264opts tff=1 -preset fast
# H.264 High 1080p60 CABAC/8x8 and a CAVLC High variant
e h264-high-1080p60.mkv $SRC -c:v libx264 -profile:v high -level 4.2 -b:v 40M -preset fast
e h264-high-cavlc-1080p60.mkv $SRC -c:v libx264 -profile:v high -level 4.2 -b:v 40M -preset fast -coder 0
sha256sum *.m2v *.m1v *.avi *.h263 *.flv *.webm *.mkv > SHA256SUMS
