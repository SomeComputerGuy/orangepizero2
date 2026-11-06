#!/bin/bash
# Runner package for the H616 G2D V4L2 m2m converter: g2d-job.sh g2d
# Self-contained: board lock (fresh owner name), one chunk "g2d" on the newest cumulative kernel (installed with the
# one-shot fallback armed through harness/research/vdec-perf/install-kernel.sh; it must contain the G2D commit, else
# BLOCKED). On the board: probe lines, IOMMU group, v4l2-compliance (plain + streaming), a matrix of conversions and
# scalings with harness/research/g2d/tool/g2dconv (the board generates the analytic input pattern itself; the host
# generates the same pattern in the destination format as the reference and compares channel by channel with
# tool/g2dcmp.py), and two GStreamer v4l2convert pipelines. Results are copied off; the stock image kernel
# (vmlinuz-7.3.1-edge-sunxi64) is restored at the end and before every lock hand-over. Resumable: re-running skips the
# chunks listed in $OUT/state. Exit 0 = chunk ran (judge with HANDOFF.md "Checks"); 2 = blocked ($OUT/BLOCKED);
# 3 = Oops/WARN/IOMMU fault on the serial log or in dmesg (lines in $OUT/OOPS); 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/g2d; V=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh
J=${1:?job: g2d}
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files $OUT/ref; touch $OUT/state; rm -f $OUT/BLOCKED $OUT/OOPS
case $J in
  g2d) CHUNKS="g2d"; CT=1200; STALL=240 ;;
  *) echo "unknown job $J"; exit 1 ;;
esac
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
FIX=04964f921                        # fix/sunxi-h616-g2d HEAD (armbian-build); the kernel must have it
TOOL=$S/tool/out/g2dconv; HOSTTOOL=$S/tool/out/g2dconv-host; CMP=$S/tool/g2dcmp.py
P=/root/g2d/g2dconv
R=/root/g2dtest                           # board results dir
OOPS='Unable to handle|Oops|WARNING:|workqueue lockup|iommu.*fault|Page fault|hung task'
SER=$H/harness/serial.log
OWN=""
# case name | in fmt | in size | out fmt | out size | colour space | tolerance | border | iterations
CASES="
rgb-copy      XR24 128x96 XR24 128x96 601 0 0 20
rgb-ar24      XR24 128x96 AR24 128x96 601 0 0 5
rgb-ba24      XR24 128x96 BA24 128x96 601 0 0 5
rgb-bx24      XR24 128x96 BX24 128x96 601 0 0 5
rgb-ab24      XR24 128x96 AB24 128x96 601 0 0 5
rgb-xb24      XR24 128x96 XB24 128x96 601 0 0 5
rgb-ra24      XR24 128x96 RA24 128x96 601 0 0 5
rgb-rx24      XR24 128x96 RX24 128x96 601 0 0 5
rgb-rgbp      XR24 128x96 RGBP 128x96 601 8 0 5
rgb-rgb3      XR24 128x96 RGB3 128x96 601 0 0 5
rgb-bgr3      XR24 128x96 BGR3 128x96 601 0 0 5
in-ar24       AR24 128x96 XR24 128x96 601 0 0 5
in-ba24       BA24 128x96 XR24 128x96 601 0 0 5
in-bx24       BX24 128x96 XR24 128x96 601 0 0 5
in-ab24       AB24 128x96 XR24 128x96 601 0 0 5
in-xb24       XB24 128x96 XR24 128x96 601 0 0 5
in-ra24       RA24 128x96 XR24 128x96 601 0 0 5
in-rx24       RX24 128x96 XR24 128x96 601 0 0 5
in-rgbp       RGBP 128x96 XR24 128x96 601 8 0 5
in-rgb3       RGB3 128x96 XR24 128x96 601 0 0 5
in-bgr3       BGR3 128x96 XR24 128x96 601 0 0 5
rgb2nv12      XR24 128x96 NV12 128x96 601 6 0 20
rgb2nv21      XR24 128x96 NV21 128x96 601 6 0 5
rgb2yu12      XR24 128x96 YU12 128x96 601 6 0 5
rgb2yv12      XR24 128x96 YV12 128x96 601 6 0 5
rgb2nv16      XR24 128x96 NV16 128x96 601 6 0 5
rgb2nv61      XR24 128x96 NV61 128x96 601 6 0 5
rgb2422p      XR24 128x96 422P 128x96 601 6 0 5
nv122rgb      NV12 128x96 XR24 128x96 601 6 2 20
nv212rgb      NV21 128x96 XR24 128x96 601 6 2 5
yu122rgb      YU12 128x96 XR24 128x96 601 6 2 5
yv122rgb      YV12 128x96 XR24 128x96 601 6 2 5
nv162rgb      NV16 128x96 XR24 128x96 601 6 2 5
nv612rgb      NV61 128x96 XR24 128x96 601 6 2 5
422p2rgb      422P 128x96 XR24 128x96 601 6 2 5
nv122yu12     NV12 128x96 YU12 128x96 601 6 2 5
nv122nv16     NV12 128x96 NV16 128x96 601 6 2 5
csc709        XR24 128x96 NV12 128x96 709 6 0 5
csc709-back   NV12 128x96 XR24 128x96 709 6 2 5
cscjpeg       XR24 128x96 NV12 128x96 jpeg 6 0 5
cscjpeg-back  NV12 128x96 XR24 128x96 jpeg 6 2 5
scale-down2   XR24 128x96 NV12 64x48 601 8 2 10
scale-up      XR24 128x96 XR24 320x240 601 8 2 10
scale-down8   NV12 1280x720 XR24 160x90 601 10 2 10
scale-down6   XR24 1920x1080 NV12 320x180 601 10 2 10
scale-odd     NV12 640x480 XR24 100x76 601 10 2 10
full-hd       XR24 1920x1080 NV12 1920x1080 601 6 0 10
rgb-copy-hd   XR24 1920x1080 XR24 1920x1080 601 0 0 10
max-size      XR24 2048x2048 NV12 2048x2048 601 6 0 3
"
# gst cases: name | rawvideoparse format nick | V4L2 in fmt | in size | gst out format | V4L2 out fmt | out size | tolerance | border
GST="
gst-rgb2nv12  bgrx XR24 640x480 NV12 NV12 640x480 6 0
gst-nv122rgb  nv12 NV12 640x480 BGRx XR24 320x240 10 2
"
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-g2d-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"; }
ship_client() { # the test client: ship it only when the board copy differs
  local want_sha have_sha; want_sha=$(sha256sum < $TOOL | cut -d' ' -f1)
  have_sha=$($SSH -n "sha256sum < $P 2>/dev/null | cut -d' ' -f1")
  [ "$want_sha" = "$have_sha" ] && { log "client on the board is current ($want_sha)"; return; }
  $V/ship.sh $TOOL $P 2>&1 | tail -1 | tee -a $OUT/runner.log; $SSH -n "chmod +x $P; mkdir -p $R"
  have_sha=$($SSH -n "sha256sum < $P | cut -d' ' -f1"); [ "$want_sha" = "$have_sha" ] || blocked "client ship failed"; }
boot_trial() { # install the newest cumulative kernel with the fallback armed; it must contain the G2D commit
  local c; c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the G2D commit $FIX"
  on_stock
  $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  $SSH -n 'modprobe sun50i-g2d 2>/dev/null; sleep 1; ls -d /sys/bus/platform/drivers/sun50i-g2d/1480000.g2d >/dev/null 2>&1' \
    || blocked "kernel $T has no bound sun50i-g2d driver at 1480000.g2d (G2D not in this kernel or probe failed; see dmesg in files/)"
  log "kernel g2d: bound ($($SSH -n 'dmesg | grep -i "sun50i-g2d\|g2d:" | tail -2' | tr '\n' ' '))"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
make_refs() { # host side: the destination-format reference of every case (same pattern code as the board input)
  [ -x $HOSTTOOL ] && [ -x $TOOL ] || { bash $S/tool/build.sh > /dev/null 2>&1 || { log "tool build failed"; exit 1; }; }
  while read -r name fi si fo so cs tol border n; do [ -n "$name" ] || continue
    $HOSTTOOL gen $fo $so $OUT/ref/$name.raw -c $cs > /dev/null || { log "reference $name failed"; exit 1; }
  done <<< "$CASES"
  while read -r name gfi fi si gfo fo so tol border; do [ -n "$name" ] || continue
    $HOSTTOOL gen $fo $so $OUT/ref/$name.raw -c 601 > /dev/null || { log "reference $name failed"; exit 1; }
  done <<< "$GST"
  log "references: $(ls $OUT/ref | wc -l) files"; }
chunk_script() { # board script of a chunk ($1 = chunk name); ends with ROUND-DONE
  cat <<EOS
set -u; D=$R/$1; rm -rf \$D; mkdir -p \$D/out \$D/in; cd \$D
uname -v > kernel.txt; cat /proc/cmdline > cmdline.txt
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
# --- probe ---
dmesg | grep -i 'g2d' > probe-dmesg.txt; echo "driver_lines \$(grep -ci 'sun50i-g2d' probe-dmesg.txt)" | tee probe.txt
echo "iommu_group \$(ls -d /sys/kernel/iommu_groups/*/devices/1480000.g2d 2>/dev/null | wc -l)" | tee -a probe.txt
cat /sys/kernel/debug/clk/g2d/clk_rate 2>/dev/null | sed 's/^/clk_rate /' | tee -a probe.txt
DEV=""; for v in /dev/video*; do v4l2-ctl -d \$v -D 2>/dev/null | grep -q 'Driver name *: sun50i-g2d' && DEV=\$v && break; done
echo "device \${DEV:-none}" | tee -a probe.txt
[ -n "\$DEV" ] || { echo NO-DEVICE; dmesg | tail -n +\$((n1+1)) > dmesg-chunk.txt; echo ROUND-DONE; exit 0; }
v4l2-ctl -d \$DEV -D --list-formats-out --list-formats > formats.txt 2>&1
echo "formats_out \$(sed -n '/Output/,/Capture/p' formats.txt | grep -c "^\s*\[")" | tee -a probe.txt
echo "formats_cap \$(sed -n '/Capture/,\$p' formats.txt | grep -c "^\s*\[")" | tee -a probe.txt
# --- compliance ---
timeout 300 v4l2-compliance -d \$DEV > compliance.txt 2>&1; echo "RC \$?" >> compliance.txt
grep -E '^Total for' compliance.txt | sed 's/^/COMPLIANCE: /'
timeout 300 v4l2-compliance -s -d \$DEV > compliance-s.txt 2>&1; echo "RC \$?" >> compliance-s.txt
grep -E '^Total for' compliance-s.txt | sed 's/^/COMPLIANCE-S: /'
# --- conversions: inputs generated once per (format, size, colour space) ---
gen() { local f=in/\$1-\$2-\$3.raw; [ -f \$f ] || $P gen \$1 \$2 \$f -c \$3 > /dev/null; echo \$f; }
conv() { local name=\$1 fi=\$2 si=\$3 fo=\$4 so=\$5 cs=\$6 n=\$7 in
  in=\$(gen \$fi \$si \$cs)
  timeout 120 $P conv -d \$DEV -n \$n -c \$cs -i \$in \$fi \$si -o out/\$name.raw \$fo \$so > \$name.txt 2>&1; echo "RC \$?" >> \$name.txt
  echo "== \$name: \$(grep -E '^(TIME|RESULT|RC)' \$name.txt | tr '\n' ' ')"; }
while read -r name fi si fo so cs tol border n; do [ -n "\$name" ] || continue; conv \$name \$fi \$si \$fo \$so \$cs \$n; done <<'CASES'
$CASES
CASES
# --- GStreamer v4l2convert (fresh registry so the plugin probes this kernel's devices) ---
export GST_REGISTRY=/tmp/g2d-gstreg.bin; rm -f \$GST_REGISTRY
gst-inspect-1.0 v4l2convert > gst-inspect.txt 2>&1; echo "RC \$?" >> gst-inspect.txt
echo "element \$(grep -c 'Long-name' gst-inspect.txt)" | tee gst.txt
echo "device \$(grep -E 'Device path|device  *:' gst-inspect.txt | head -1 | sed 's/.*: //;s/ .*//')" | tee -a gst.txt
echo "device_expected \$DEV" | tee -a gst.txt
gstrun() { local name=\$1 gfi=\$2 fi=\$3 si=\$4 gfo=\$5 fo=\$6 so=\$7 in w h wo ho
  in=\$(gen \$fi \$si 601); w=\${si%x*}; h=\${si#*x}; wo=\${so%x*}; ho=\${so#*x}
  timeout 120 gst-launch-1.0 -q filesrc location=\$in ! rawvideoparse format=\$gfi width=\$w height=\$h framerate=1/1 ! \
    v4l2convert ! video/x-raw,format=\$gfo,width=\$wo,height=\$ho ! filesink location=out/\$name.raw > \$name.txt 2>&1; echo "RC \$?" >> \$name.txt
  echo "size \$(stat -c %s out/\$name.raw 2>/dev/null || echo 0)" >> \$name.txt
  echo "== \$name: \$(grep -E '^(RC|size)' \$name.txt | tr '\n' ' ')"; }
while read -r name gfi fi si gfo fo so tol border; do [ -n "\$name" ] || continue; gstrun \$name \$gfi \$fi \$si \$gfo \$fo \$so; done <<'GST'
$GST
GST
rm -rf in
dmesg | tail -n +\$((n1+1)) > dmesg-chunk.txt
grep -E 'g2d|iommu|v4l|videobuf|$OOPS' dmesg-chunk.txt | tail -60 | sed 's/^/DMESG: /'
echo ROUND-DONE
EOS
}
extract() { # host side: one line per run and key into $OUT/results.txt (chunk run key value)
  local c=$1 d=$OUT/files/$1 name fi si fo so cs tol border n gfi gfo
  [ -f $d/probe.txt ] && sed "s/^/$c probe /" $d/probe.txt >> $OUT/results.txt || echo "$c probe missing 1" >> $OUT/results.txt
  for f in compliance compliance-s; do
    if [ -f $d/$f.txt ]; then
      awk -v c=$c -v r=$f '/^Total for/ { for (i = 1; i <= NF; i++) { if ($i == "Succeeded:") print c, r, "succeeded", $(i+1)+0; if ($i == "Failed:") print c, r, "failed", $(i+1)+0; if ($i == "Warnings:") print c, r, "warnings", $(i+1)+0 } }
                              /^RC / { print c, r, "rc", $2 }' $d/$f.txt >> $OUT/results.txt
      grep -q '^Total for' $d/$f.txt || echo "$c $f failed 999" >> $OUT/results.txt
      grep -E '^\s+fail:' $d/$f.txt | head -20 | sed "s/^/$c $f FAILLINE /" >> $OUT/results.txt
    else echo "$c $f missing 1" >> $OUT/results.txt; fi
  done
  while read -r name fi si fo so cs tol border n; do [ -n "$name" ] || continue
    if [ ! -f $d/$name.txt ]; then echo "$c $name rc 99" >> $OUT/results.txt; continue; fi
    awk -v c=$c -v r=$name '/^RESULT rc / { print c, r, "rc", $3; if ($3 != 0) print c, r, "reason", $5 }
                            /^TIME / { print c, r, "avg_us", $5; print c, r, "max_us", $9 }
                            /^FMT CAP / { print c, r, "cap_bpl", $7; print c, r, "cap_size", $9 }' $d/$name.txt >> $OUT/results.txt
    grep -q '^RESULT rc' $d/$name.txt || echo "$c $name rc $(grep '^RC' $d/$name.txt | cut -d' ' -f2)" >> $OUT/results.txt
    if [ -f $d/out/$name.raw ]; then
      python3 -I $CMP $fo $so $d/out/$name.raw $OUT/ref/$name.raw --tol $tol --border $border --tag $name 2>&1 | \
        awk -v c=$c -v r=$name '/^RESULT/ { for (i = 3; i < NF; i += 2) print c, r, $i, $(i+1) }' >> $OUT/results.txt
    else echo "$c $name pass 0" >> $OUT/results.txt; echo "$c $name reason no_output" >> $OUT/results.txt; fi
  done <<< "$CASES"
  [ -f $d/gst.txt ] && sed "s/^/$c gst /" $d/gst.txt >> $OUT/results.txt || echo "$c gst element 0" >> $OUT/results.txt
  while read -r name gfi fi si gfo fo so tol border; do [ -n "$name" ] || continue
    if [ ! -f $d/$name.txt ]; then echo "$c $name rc 99" >> $OUT/results.txt; continue; fi
    echo "$c $name rc $(grep '^RC' $d/$name.txt | cut -d' ' -f2)" >> $OUT/results.txt
    if [ -s $d/out/$name.raw ]; then
      python3 -I $CMP $fo $so $d/out/$name.raw $OUT/ref/$name.raw --tol $tol --border $border --tag $name 2>&1 | \
        awk -v c=$c -v r=$name '/^RESULT/ { for (i = 3; i < NF; i += 2) print c, r, $i, $(i+1) }' >> $OUT/results.txt
    else echo "$c $name pass 0" >> $OUT/results.txt; echo "$c $name reason no_output" >> $OUT/results.txt; fi
  done <<< "$GST"
  echo "$c all dmesg_bad $(grep -cE "$OOPS" $d/dmesg-chunk.txt 2>/dev/null || echo 0)" >> $OUT/results.txt
  echo "$c all iommu_faults $(grep -ciE 'iommu.*fault|page fault' $d/dmesg-chunk.txt 2>/dev/null || echo 0)" >> $OUT/results.txt
  echo "$c all g2d_timeouts $(grep -ci 'g2d.*timed out' $d/dmesg-chunk.txt 2>/dev/null || echo 0)" >> $OUT/results.txt
  echo "$c all g2d_dmesg_lines $(grep -ci 'g2d' $d/dmesg-chunk.txt 2>/dev/null || echo 0)" >> $OUT/results.txt; }
oops_fail() { log "OOPS during chunk $1 ($2): $(head -3 $OUT/OOPS | tr '\n' ' ')"; restore; release; log "job $J ABORTED (exit 3)"; exit 3; }
run_chunk() { # run_chunk <chunk>: remote script under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt oops=""
  chunk_script $c | $SSH "mkdir -p $R; cat > $R/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  local soff=$(stat -c %s $SER 2>/dev/null || echo 0)
  $SSH -n "timeout $CT bash $R/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 10
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ -f $SER ] && tail -c +$((soff+1)) $SER | grep -qE "$OOPS"; then
      tail -c +$((soff+1)) $SER | grep -E "$OOPS|Call trace|pc :|lr :" | head -40 > $OUT/OOPS
      log "OOPS on the serial log during chunk $c, killing ssh $p"; kill $p; echo OOPS >> $f; oops=serial; break; fi
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c; scp -q -r "${K[@]}" root@10.56.0.107:$R/$c/. $OUT/files/$c/ 2>/dev/null
  if [ -z "$oops" ] && grep -qE "$OOPS" $OUT/files/$c/dmesg-chunk.txt 2>/dev/null; then grep -E "$OOPS|Call trace|pc :|lr :" $OUT/files/$c/dmesg-chunk.txt | head -40 > $OUT/OOPS; oops=dmesg; fi
  extract $c
  [ -n "$oops" ] && oops_fail $c $oops
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
: > $OUT/results.txt
log "job $J start, kernel $T (Image md5 $want), G2D commit $FIX, chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
make_refs
trap 'release' EXIT
acquire; on_stock; ship_client
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; on_stock; fi
  boot_trial
  log "chunk $c start"; run_chunk $c
  restore
done
release
log "job $J end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done; results in $OUT/results.txt"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
