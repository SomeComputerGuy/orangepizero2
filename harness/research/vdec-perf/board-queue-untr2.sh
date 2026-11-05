#!/bin/bash
# Untranslated VE (overlay, cma=640M): exact CMA use per pipeline from the cma trace events (allocs - releases), fps, md5,
# and the cause of the CMA -EBUSY failures (busy retries, failed isolation pfn + its kpageflags, migration failures).
cd /root/vdec-streams || exit 1
V=/root/vp; TL=$V/ve-timeline.sh; A=/root/avs2/avs2dec-q; U=http://10.56.0.1:8643/avs2; mkdir -p /root/avs2
F="$V/ffmpeg -hide_banner -nostats -loglevel error -hwaccel v4l2request"; FD="$F -hwaccel_output_format drm_prime"
curl -sS --fail $U/avs2dec-q -o $A && chmod +x $A || { echo "avs2dec-q download failed"; exit 1; }
curl -sS --fail $U/cctv4k-10bit.avs2 -o /root/avs2/cc.avs2 && curl -sS --fail $U/main-2160p-ra.avs2 -o /root/avs2/m8.avs2 || exit 1
mi() { awk -v k="$1:" '$1==k {print int($2/1024)}' /proc/meminfo; }
echo "kernel $(uname -rv) cmdline: $(grep -o 'cma=[^ ]*' /proc/cmdline) CmaTotal $(mi CmaTotal) CmaFree $(mi CmaFree) MemFree $(mi MemFree) MemAvailable $(mi MemAvailable) Cached $(mi Cached) Shmem $(mi Shmem)"
echo "bypass $(python3 -I $V/devmem.py 0x030f0030); VE iommus [$(od -An -tx1 /proc/device-tree/soc/video-codec@1c0e000/iommus 2>/dev/null | tr -d ' \n')]"
I=/sys/kernel/tracing/instances/cmaq; mkdir -p $I; EV="cma/cma_alloc_finish cma/cma_release cma/cma_alloc_busy_retry page_isolation/test_pages_isolated migrate/mm_migrate_pages"
for e in $EV; do [ -e $I/events/$e/enable ] || echo "missing event $e"; done
ton() { echo 0 > $I/tracing_on; echo > $I/trace; echo 8192 > $I/buffer_size_kb; for e in $EV; do echo 1 > $I/events/$e/enable 2>/dev/null; done; echo 1 > $I/tracing_on; }
toff() { echo 0 > $I/tracing_on; cat $I/trace > /tmp/tr; for e in $EV; do echo 0 > $I/events/$e/enable 2>/dev/null; done; }
kpf() { python3 -I -c "
import struct,sys
names='LOCKED ERROR REFERENCED UPTODATE DIRTY LRU ACTIVE SLAB WRITEBACK RECLAIM BUDDY MMAP ANON SWAPCACHE SWAPBACKED COMPOUND_HEAD COMPOUND_TAIL HUGE UNEVICTABLE HWPOISON NOPAGE KSM THP OFFLINE ZERO_PAGE IDLE PGTABLE'.split()
for a in sys.argv[1:]:
  p=int(a,16); f=open('/proc/kpageflags','rb'); f.seek(8*p); fl=struct.unpack('<Q',f.read(8))[0]
  c=open('/proc/kpagecount','rb'); c.seek(8*p); n=struct.unpack('<Q',c.read(8))[0]
  print('  pfn %s count %d flags 0x%x %s' % (a,n,fl,' '.join(x for i,x in enumerate(names) if fl>>i&1)))" "$@"; }
summ() { # summ <label>: exact CMA peak, failures and their cause from /tmp/tr
  awk -v l="$1" '
    /cma_alloc_finish:/ { match($0,/count=[0-9]+/); c=substr($0,RSTART+6,RLENGTH-6); match($0,/errorno=-?[0-9]+/); e=substr($0,RSTART+8,RLENGTH-8)
      if (e==0) { u+=c; if (u>m) m=u; na++ } else { nf++; if (c>fc) fc=c; fe=e } }
    /cma_release:/ { match($0,/count=[0-9]+/); u-=substr($0,RSTART+6,RLENGTH-6) }
    /cma_alloc_busy_retry:/ { nb++ }
    /test_pages_isolated:/ && /ret=fail/ { ni++ }
    /mm_migrate_pages:/ { match($0,/nr_failed=[0-9]+/); mf+=substr($0,RSTART+10,RLENGTH-10); match($0,/nr_succeeded=[0-9]+/); ms+=substr($0,RSTART+13,RLENGTH-13)
      if ($0 ~ /nr_failed=[1-9]/) { match($0,/reason=[a-z_]+/); r[substr($0,RSTART+7,RLENGTH-7)]++ } }
    END { printf "[%s] cma exact-peak %.1f MB (%d allocs) | failed allocs %d (largest %.1f MB, errno %s) busy-retries %d isolation-fails %d | migrate ok %d failed %d", l, m*4/1024, na, nf, fc*4/1024, fe, nb, ni, ms, mf
      for (k in r) printf " %s:%d", k, r[k]; print "" }' /tmp/tr
  p=$(awk '/test_pages_isolated:/ && /ret=fail/ { match($0,/fin_pfn=0x[0-9a-f]+/); print substr($0,RSTART+10,RLENGTH-10) }' /tmp/tr | sort -u | head -6)
  [ -n "$p" ] && { echo "  isolation-fail pfns (flags read after the run):"; kpf $p; }
  grep -m3 "nr_failed=[1-9]" /tmp/tr | sed 's/^ */  /' | cut -c1-200
}
case1() { lbl=$1; shift; d0=$(dmesg | wc -l); ton; t=$($TL "$@" | tr '\n' ' '); toff
  echo "$(summ "$lbl") | $(echo "$t" | sed -e 's/| setup.*fps:/| fps:/' -e 's/ | idle share.*//')"; }
md5r() { lbl=$1; ref=$2; shift 2; ton; r=$("$@" 2>&1 | tail -1); toff; r=${r#MD5=}; r=${r##* }; res=FAIL; [ "$r" = "$ref" ] && res=PASS
  echo "[md5 $lbl] $res $r"; echo "  $(summ "md5 $lbl")"; }
vp=$(cut -d= -f2 vp9-p2-2160p60.webm.p010le.md5); hv=$(cut -d= -f2 hevc-main10-2160p60.mkv.p010le.md5)
for th in 1 2 0; do case1 "vp9p2 P010 threads=$th" env V4L2REQUEST_PIXFMT=P010 $FD -threads $th -i vp9-p2-2160p60.webm -f null -; done
for th in 1 2 0; do case1 "h265m10 P010 threads=$th" env V4L2REQUEST_PIXFMT=P010 $FD -threads $th -i hevc-main10-2160p60.mkv -f null -; done
case1 "avs2-10bit P010 nooutput" env AVS2_NOOUT=1 $A /root/avs2/cc.avs2
case1 "vp9p2 AFBC" env V4L2REQUEST_PIXFMT=AS01 $FD -i vp9-p2-2160p60.webm -f null -
echo "pagetypeinfo CMA: $(grep -E 'Node +0, zone +DMA32?, type +CMA' /proc/pagetypeinfo | head -1 | tr -s ' ')"
echo "meminfo: CmaFree $(mi CmaFree) MemFree $(mi MemFree) Cached $(mi Cached) Shmem $(mi Shmem) Dirty $(mi Dirty) Writeback $(mi Writeback)"
md5r vp9p2-P010 $vp env V4L2REQUEST_PIXFMT=P010 $F -i vp9-p2-2160p60.webm -pix_fmt p010le -f md5 -
md5r h265m10-P010 $hv env V4L2REQUEST_PIXFMT=P010 $F -i hevc-main10-2160p60.mkv -pix_fmt p010le -f md5 -
md5r avs2-8bit 3a3d5d7eb9a6f548042e160d9e461388 $A /root/avs2/m8.avs2
md5r avs2-10bit be9985dea38abffc850d73024165c990 $A /root/avs2/cc.avs2
md5r avs2-10bit-again be9985dea38abffc850d73024165c990 $A /root/avs2/cc.avs2
rmdir $I 2>/dev/null; rm -f /root/avs2/cc.avs2 /root/avs2/m8.avs2
dmesg | grep -iE 'cma|dma alloc|timed out|slub|page allocation failure' | tail -8 | sed 's/^/[dmesg] /'
echo "cma-fail-lines $(dmesg | grep -c 'alloc failed') timeouts $(dmesg | grep -c 'timed out')"; echo ROUND-DONE
