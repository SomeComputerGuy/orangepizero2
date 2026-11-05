#!/bin/sh
# SPDX-License-Identifier: MIT
# Board side: DI300 V4L2_CID_DEINTERLACING_MODE / private-control regression set (2026-11-05 alignment with
# the OPi5 IEP2 convention). Runs in DIR (vectors + binaries copied there) and writes OUT/.
#   std-ctrl-test.sh old DIR   previous kernel + previous di300test (indices, IDs at USER_BASE + 0x1100)
#   std-ctrl-test.sh new DIR   new kernel + new di300test/di300err (names, IDs at USER_BASE + 0x1260)
# Each output file gets an md5 in OUT/md5.txt; harness/di300test/std-ctrl-compare.sh compares old and new.
set -u
kind=$1; DIR=$2; OUT=$DIR/out-$kind
cd "$DIR" || exit 2
rm -rf "$OUT"; mkdir -p "$OUT"
T=./di300test.$kind
run() { # name args...: one di300test run, output to OUT/name.yuv, log to OUT/name.log
	n=$1; shift
	timeout 120 $T "$@" -o "$OUT/$n.yuv" > "$OUT/$n.log" 2>&1; echo "rc=$?" >> "$OUT/$n.log"
	tail -2 "$OUT/$n.log" | head -1 | sed "s/^/$n: /"
}
uname -rv
DEV=$(for d in /sys/class/video4linux/video*; do grep -q di300 $d/name && echo /dev/${d##*/}; done | head -1)
echo "DI300 node: $DEV"
for v in m576 m576b m1080 m1080b; do
	case $v in m576*) D="-W 720 -H 576";; *) D="-W 1920 -H 1080";; esac
	case $v in *b) B=-b;; *) B=;; esac
	for m in field frame bob weave; do run "$v.$m" $D $B -f i420 -m $m -i $v.in.yuv; done
	[ "$kind" = new ] && run "$v.bobfield" $D $B -f i420 -m bobfield -i $v.in.yuv
done
# private controls: TNR (fixed/adaptive/levels, TNR-only), FMD statistics and per-job weave
D="-W 720 -H 576"
run tnr.field.fixed $D -f i420 -F yv12 -m field -t fixed -i m576n.in.yuv
run tnr.field.adapt0 $D -f i420 -F yv12 -m field -t adaptive -l 0 -i m576n.in.yuv
run tnr.field.adapt2 $D -f i420 -F yv12 -m field -t adaptive -l 2 -i m576n.in.yuv
run tnr.frame.fixed40 $D -f i420 -F yv12 -m frame -t fixed -s 40 -i m576n.in.yuv
run tnr.only $D -f i420 -F yv12 -m tnr -t fixed -i m576n.in.yuv
for w in 0 1 2; do run fmd.w$w -W 720 -H 480 -f i420 -m field -z -v -w $w,$((w | 8)) -i tc.in.yuv; done
grep -h '^fmd ' "$OUT/fmd.w0.log" > "$OUT/fmd.stats.txt"
if [ "$kind" = new ]; then
	# timestamps and kept fields of the new item
	run keep.bobfield $D -f i420 -m bobfield -c keep -v -n 6 -i m576.in.yuv
	run keep.bobfield.b $D -b -f i420 -m bobfield -c keep -v -n 6 -i m576b.in.yuv
	# progressive pass-through in every item (TNR-only filters instead)
	for m in field frame bob bobfield weave; do
		run prog.$m $D -p -f nv12 -m $m -c weave -i m576.nv12.yuv
		run prog.$m.tnr $D -p -f i420 -F i420 -m $m -t fixed -c weave -i m576n.in.yuv
	done
	# method changes while streaming (same rate: ok, the rest of the stream equals a fresh one; rate: EBUSY)
	for p in field:bobfield bobfield:field frame:bob bob:weave weave:frame frame:weave; do
		a=${p%:*}; b=${p#*:}
		run sw.$a.$b $D -f i420 -m $a -S $b@10 -i m576.in.yuv
		run fresh.$b.k10 $D -f i420 -m $b -k 10 -i m576.in.yuv
	done
	run sw.tnr.frame.bob $D -f i420 -F yv12 -m frame -t fixed -S bob@10 -i m576n.in.yuv
	run fresh.tnr.bob.k10 $D -f i420 -F yv12 -m bob -t fixed -k 10 -i m576n.in.yuv
	run sw.tnr.bob.frame $D -f i420 -F yv12 -m bob -t fixed -S frame@10 -i m576n.in.yuv
	run fresh.tnr.frame.k10 $D -f i420 -F yv12 -m frame -t fixed -k 10 -i m576n.in.yuv
	run sw.field.frame $D -f i420 -m field -S frame@10 -i m576.in.yuv
	run sw.frame.tnr $D -f i420 -m frame -S tnr@10 -i m576.in.yuv
	timeout 60 ./di300err "$DEV" > "$OUT/di300err.log" 2>&1
	tail -1 "$OUT/di300err.log" | sed 's/^/di300err: /'
fi
v4l2-ctl -d "$DEV" -L > "$OUT/ctrls.txt" 2>&1
timeout 600 v4l2-compliance -d "$DEV" -s > "$OUT/compliance.log" 2>&1
grep -E '^Total|FAIL' "$OUT/compliance.log" | sed 's/^/compliance: /'
(cd "$OUT" && md5sum *.yuv *.txt > md5.txt)
dmesg | grep -iE 'di300|deinterlace|Page fault|timed out' | tail -5
