#!/bin/bash
# Runner package: bit-exact check of the cedrus AFBC capture through the DE33 (job 53, rerun 54). afbc-wb-job.sh j54
# The H616 Mali-G31 has no AFBC (job 51), so each decoded frame is shown 1:1 on the DE33 VI plane (FBD = the AFBC
# decompressor) and the composed frame is captured with the DE33 writeback connector (XR30), once from the linear
# decode (NV12/P010) and once from the AFBC decode (AS12/AS01) of the same stream, same plane setup; harness/afbc-wb
# (afbc-wb.c) compares the captures pixel by pixel. Synthetic lossless 1024x768 streams (harness/afbc-wb/mkstreams.sh,
# flat-chroma tiles) carry the pass criteria; the 4K real streams (cropped 1:1 window) are informational.
# Self-contained: board lock (fresh owner name), newest cumulative kernel installed with the fallback armed
# (vdec-perf/install-kernel.sh; must contain the writeback commit, else BLOCKED), DTB md5 + Writeback-1 checked,
# HDMI-A-1 forced on at 1024x768@60 (no sink). One chunk per case; resumable: re-running skips the cases in $OUT/state.
# Between cases, if another session waits on the board, the stock kernel is restored, the lock handed over and the
# trial kernel booted again afterwards. Stall watchdog per case; Oops/WARN/IOMMU fault on serial or dmesg aborts.
# Exit 0 = all cases ran (judge with HANDOFF.md "Checks"); 2 = blocked ($OUT/BLOCKED); 3 = Oops/WARN/fault ($OUT/OOPS);
# 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/afbc-wb; V=$H/harness/research/vdec-perf; SSH="timeout 120 $H/harness/ssh.sh"
J=${1:?job: j53 or j54}
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR
   -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=8)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED $OUT/OOPS
# case: name stream linear-fmt afbc-fmt frames wb-fmt extra-options (synthetic = syn-*: tile 64 band 10 + source md5s)
CASES="syn-hevc8 syn-hevc10 syn-vp9p0 syn-vp9p2 syn-hevc8-xr24 real-hevc10 real-hevc8 real-vp9p2 real-vp9p0"
FIX2=""                                    # j54: also the cedrus H.265 AFBC compose-offset commit
case $J in
  j53) ;;
  j54) FIX2=8b1f787fe                     # fix/sunxi-cedrus-h265-afbc-compose
       CASES="$CASES real-vp9p0-y4" ;;     # + a window at a 4-line (not 16-aligned) plane offset, informational
  *) echo "unknown job $J"; exit 1 ;;
esac
spec() { case $1 in
  syn-hevc8)      echo "syn-hevc8.mkv NV12 AS12 24 XR30" ;;
  syn-hevc10)     echo "syn-hevc10.mkv P010 AS01 24 XR30" ;;
  syn-vp9p0)      echo "syn-vp9p0.webm NV12 AS12 24 XR30" ;;
  syn-vp9p2)      echo "syn-vp9p2.webm P010 AS01 24 XR30" ;;
  syn-hevc8-xr24) echo "syn-hevc8.mkv NV12 AS12 24 XR24" ;;
  real-hevc10)    echo "hevc-main10-2160p60.mkv P010 AS01 12 XR30" ;;
  real-hevc8)     echo "hevc-main-2160p60.mkv NV12 AS12 12 XR30" ;;
  real-vp9p2)     echo "vp9-p2-2160p60.webm P010 AS01 12 XR30" ;;
  real-vp9p0)     echo "vp9-p0-2160p60.webm NV12 AS12 12 XR30" ;;
  real-vp9p0-y4)  echo "vp9-p0-2160p60.webm NV12 AS12 12 XR30 1408,708" ;;
esac; }
CT=420; STALL=240                          # per case: board timeout, watchdog (no output for STALL s)
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
FIX=30706dcc8                              # DE33 writeback (fix/sunxi-h616-de33-wb-fb-formats HEAD); the kernel must have it
CLIENT=$H/harness/afbc-wb/out/afbc-wb      # harness/afbc-wb/build.sh
SYN=$H/kernel-check/vdec-serve/afbc-wb     # harness/afbc-wb/mkstreams.sh (synthetic streams + .srcmd5)
R=/root/afbcwb; P=$R/afbc-wb; RS=/root/vdec-streams   # board: work dir, client, the 4K streams of the vdec jobs
MODE=1024x768@60
OOPS='Unable to handle|Oops|WARNING:|flip_done timed out|vblank wait timed out|workqueue lockup|iommu.*fault|Page fault'
SER=$H/harness/serial.log
OWN=""; BOOTED=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
acquire() { OWN=runner-afbcwb-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { timeout 600 $V/restore-kernel.sh | tee -a $OUT/runner.log; BOOTED=""   # Image, DTB (.stock), modules (.good), reboot
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image; readlink /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; [ -n "$BOOTED" ] && restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"; }
ship() { # ship <host file> <board path>: only when the board copy differs (sha256)
  local w h; w=$(sha256sum < $1 | cut -d' ' -f1); h=$($SSH -n "sha256sum < $2 2>/dev/null | cut -d' ' -f1")
  [ "$w" = "$h" ] && { log "board $2 current"; return 0; }
  NOXZ=${NOXZ:-} timeout 600 $V/ship.sh $1 $2 2>&1 | tail -1 | tee -a $OUT/runner.log
  h=$($SSH -n "sha256sum < $2 | cut -d' ' -f1"); [ "$w" = "$h" ] || blocked "ship of $(basename $1) failed"; }
prepare() { # client + synthetic streams; the 4K streams must already be on the board (vdec jobs), else those cases are skipped
  ship $CLIENT $P; $SSH -n "chmod +x $P; mkdir -p $R/streams"
  for f in syn-hevc8.mkv syn-hevc10.mkv syn-vp9p0.webm syn-vp9p2.webm; do
    [ -s $SYN/$f ] && [ -s $SYN/${f%.*}.srcmd5 ] || blocked "missing $SYN/$f or its .srcmd5 (run harness/afbc-wb/mkstreams.sh)"
    NOXZ=1 ship $SYN/$f $R/streams/$f; ship $SYN/${f%.*}.srcmd5 $R/streams/${f%.*}.srcmd5; done
  for c in $CASES; do grep -qx "$c" $OUT/state && continue; case $c in real-*) set -- $(spec $c)
    $SSH -n "[ -s $RS/$1 ]" || { log "case $c: $RS/$1 not on the board: skipped (informational case)"; echo "$c" >> $OUT/state; echo "$c all skipped_stream_missing 1" >> $OUT/results.txt; }
  esac; done; }
boot_trial() { # install the newest cumulative kernel with the fallback armed; it must contain the writeback commit
  local c; c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the DE33 writeback commit $FIX"
  [ -z "$FIX2" ] || git -C $H/wt-cumulative merge-base --is-ancestor $FIX2 "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the cedrus H.265 AFBC compose commit $FIX2"
  on_stock
  timeout 900 $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log; BOOTED=1
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  local dw dh; dw=$(md5sum < $H/kernel-check/vdec-serve/sun50i-h616-orangepi-zero2.dtb.$T | cut -c1-32)
  dh=$($SSH -n 'md5sum < /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb | cut -c1-32')
  [ "$dh" = "$dw" ] || blocked "$T DTB not installed: board md5 $dh, want $dw (install-kernel.sh DTB step)"
  $SSH -n 'ls -d /sys/class/drm/card*-Writeback-1 >/dev/null 2>&1' || { $SSH -n 'ls /sys/class/drm; dmesg | grep -iE "sun50i_wb|writeback|sun8i-mixer" | tail -20' > $OUT/files/blocked-connector.txt 2>&1; blocked "kernel $T has no Writeback-1 connector (files/blocked-connector.txt)"; }
  log "kernel $T dtb ok ($dh), writeback present"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
case_script() { # board script of one case ($1); ends with ROUND-DONE
  local c=$1 st lin af n wf cr src ms opt=""; set -- $(spec $c); st=$1 lin=$2 af=$3 n=$4 wf=$5 cr=${6:-1408,704}
  case $c in
    syn-*)  src="$R/streams/$st"; opt="--tile 64 --band 10"; ms="--src-md5 $R/streams/${st%.*}.srcmd5" ;;
    real-*) src="$RS/$st"; opt="--crop $cr"; ms="" ;;   # 1024x768 window in the middle of the 4K frame, 64-aligned (y4: 4 lower)
  esac
  cat <<EOS
set -u; D=$R/$c; REF=/dev/shm/afbcwb-ref; rm -rf \$D \$REF; mkdir -p \$D/dump \$REF; cd \$D
uname -v > kernel.txt; free -m > mem.txt
n1=\$(dmesg | wc -l)
params() { for f in /sys/module/sun8i_mixer/parameters/de33_wb_*; do [ -f "\$f" ] && echo "\$(basename \$f)=\$(cat \$f)"; done; true; }
params > params.before
for k in /sys/class/drm/card*-HDMI-A-1; do echo on > \$k/status; done; sleep 2
for k in /sys/class/drm/card*-HDMI-A-1; do echo "\$k status=\$(cat \$k/status) modes: \$(tr '\n' ' ' < \$k/modes)"; done > connector.txt
grep -q 1024x768 connector.txt || echo MODE-UNAVAILABLE | tee -a connector.txt
echo "== linear $lin"
timeout 180 $P -i $src -f $lin -n $n -w $wf $opt $ms --save \$REF > linear.txt 2>&1; echo "RC \$?" >> linear.txt
grep -E '^RESULT (summary|src_md5 |verdict|stream|crtc|fb |mode_unavailable|.*error|frame [0-9]+ pic_offset)|^RC ' linear.txt | head -20
echo "== afbc $af"
timeout 180 $P -i $src -f $af -n $n -w $wf $opt --ref \$REF -o \$D/dump > afbc.txt 2>&1; echo "RC \$?" >> afbc.txt
grep -E '^RESULT (summary|compare|interior|edge_dist|verdict|stream|fb |mode_unavailable|.*error|frame [0-9]+ pic_offset)|^RC ' afbc.txt | head -20
rm -rf \$REF
params > params.after
for k in /sys/class/drm/card*-HDMI-A-1; do echo detect > \$k/status; done
dmesg | tail -n +\$((n1+1)) > dmesg-chunk.txt
grep -E 'sun4i|sun8i|sun50i|cedrus|drm|iommu|$OOPS' dmesg-chunk.txt | tail -30 | sed 's/^/DMESG: /'
ls -la dump | tail -n +2 | sed 's/^/DUMP: /'
echo ROUND-DONE
EOS
}
extract() { # host side: "case pass key value" lines into $OUT/results.txt
  local c=$1 d=$OUT/files/$1 p k a b
  for p in linear afbc; do
    [ -f $d/$p.txt ] || { echo "$c $p missing 1" >> $OUT/results.txt; continue; }
    awk -v c=$c -v p=$p '
      /^RC / { print c, p, "rc", $2 }
      /^RESULT mode_unavailable / { print c, p, "mode_unavailable", 1 }
      /^RESULT summary / { for (i = 5; i < NF; i += 2) print c, p, $i, $(i+1) }
      /^RESULT src_md5 ok / { print c, p, "src_md5_ok", $4; print c, p, "src_md5_mismatch", $6 }
      /^RESULT (compare|interior) frames / { for (i = 3; i < NF; i += 2) print c, p, $2 "_" $i, $(i+1) }
      /^RESULT edge_dist_hist / { $1 = ""; $2 = ""; print c, p, "edge_dist_hist", $0 }
      /^RESULT verdict / { print c, p, "verdict", $3 }
      /^RESULT fb .* format / { for (i = 1; i <= NF; i++) if ($i == "format") f = $(i+1) " " $(i+3); print c, p, "fb_format_modifier", f }
      /^RESULT [a-z_]*_error / { print c, p, $2, $3 }
      /^RESULT frame [0-9]+ wb_error / { print c, p, "wb_error_frame" $3, $5 "/" $6 }
      /^RESULT frame [0-9]+ pic_offset / { po = po (po == "" ? "" : ";") $5 }
      END { print c, p, "pic_offset", (po == "" ? "none" : po) }' $d/$p.txt | sort -u -k1,3 >> $OUT/results.txt
  done
  for k in jobs done failed; do
    a=$(grep "^de33_wb_$k=" $d/params.after 2>/dev/null | cut -d= -f2); b=$(grep "^de33_wb_$k=" $d/params.before 2>/dev/null | cut -d= -f2)
    [ -n "$a" ] && [ -n "$b" ] && echo "$c all wb_${k}_delta $((a - b))" >> $OUT/results.txt
  done
  grep -q MODE-UNAVAILABLE $d/connector.txt 2>/dev/null && echo "$c all mode_unavailable 1" >> $OUT/results.txt
  k=$(grep -cE "$OOPS" $d/dmesg-chunk.txt 2>/dev/null); echo "$c all dmesg_bad ${k:-0}" >> $OUT/results.txt
  k=$(grep -ciE 'iommu' $d/dmesg-chunk.txt 2>/dev/null); echo "$c all dmesg_iommu ${k:-0}" >> $OUT/results.txt; }
oops_fail() { log "OOPS during case $1 ($2): $(head -3 $OUT/OOPS | tr '\n' ' ')"; restore; release; log "job $J ABORTED (exit 3)"; exit 3; }
run_case() { # remote script under timeout + stall watchdog; output to $OUT/chunk-<c>.txt; files to $OUT/files/<c>/
  local c=$1 f=$OUT/chunk-$1.txt oops=""
  case_script $c | $SSH "mkdir -p $R; cat > $R/case-$c.sh" || { log "case $c: cannot write the board script"; return; }
  local soff=$(stat -c %s $SER 2>/dev/null || echo 0)
  timeout $((CT + 60)) $H/harness/ssh.sh -n "timeout $CT bash $R/case-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0 n
  while kill -0 $p 2>/dev/null; do sleep 10
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ -f $SER ] && tail -c +$((soff+1)) $SER | grep -qE "$OOPS"; then
      tail -c +$((soff+1)) $SER | grep -E "$OOPS|Call trace|pc :|lr :" | head -40 > $OUT/OOPS
      log "OOPS on the serial log during case $c, killing ssh $p"; kill $p; echo OOPS >> $f; oops=serial; break; fi
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: case $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c; timeout 300 scp -q -r "${K[@]}" root@10.56.0.107:$R/$c/. $OUT/files/$c/ 2>/dev/null || log "scp of $R/$c failed or timed out"
  if [ -z "$oops" ] && grep -qE "$OOPS" $OUT/files/$c/dmesg-chunk.txt 2>/dev/null; then grep -E "$OOPS|Call trace|pc :|lr :" $OUT/files/$c/dmesg-chunk.txt | head -40 > $OUT/OOPS; oops=dmesg; fi
  sed -i "/^$c /d" $OUT/results.txt; extract $c
  [ -n "$oops" ] && oops_fail $c $oops
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "case $c done"; } || log "case $c ended without ROUND-DONE"; }
touch $OUT/results.txt
log "job $J start, kernel $T (Image md5 $want), client sha $(sha256sum < $CLIENT | cut -c1-16), done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire; on_stock; prepare
for c in $CASES; do
  grep -qx "$c" $OUT/state && continue
  if [ -n "$BOOTED" ] && others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; on_stock; fi
  [ -n "$BOOTED" ] || boot_trial
  log "case $c start: $(spec $c)"; run_case $c
done
[ -n "$BOOTED" ] && restore
release
log "job $J end: $(sort -u $OUT/state | wc -l) of $(echo $CASES | wc -w) cases done; results in $OUT/results.txt"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
