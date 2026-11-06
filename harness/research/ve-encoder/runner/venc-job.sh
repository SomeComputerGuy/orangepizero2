#!/bin/bash
# Runner package for the H616 VE H.264 encoder (cedrus stateless encoder): venc-job.sh venc
# Self-contained: board lock (fresh owner name), one chunk "venc" on the newest cumulative kernel (installed with the
# one-shot fallback armed through harness/research/vdec-perf/install-kernel.sh; it must contain the venc commit, else
# BLOCKED). On the board: the encoder node probes (dmesg, v4l2-ctl), v4l2-compliance on it, five encodes of raw NV12
# test clips with harness/research/ve-encoder/tools/out/h264enc-test (all-intra and I+P, 720p, 1080p and 1366x768),
# a hardware decode of each stream with GStreamer v4l2slh264dec (if present), dmesg. On the host: every stream is
# decoded with ffmpeg (errors, frame count) and compared with its source clip (PSNR), the hardware decode is compared
# with ffmpeg's (md5). Results are copied off; the stock image kernel (vmlinuz-7.3.1-edge-sunxi64) is restored at the
# end and before every lock hand-over. Resumable: re-running skips the chunks listed in $OUT/state.
# Exit 0 = chunk ran (judge with HANDOFF.md "Checks"); 2 = blocked ($OUT/BLOCKED); 3 = Oops/WARN/IOMMU fault on the
# serial log or in dmesg (lines in $OUT/OOPS); 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/ve-encoder; V=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh
J=${1:?job: venc}
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=8)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED $OUT/OOPS
case $J in
  venc) CHUNKS="venc"; CT=900; STALL=180 ;;
  *) echo "unknown job $J"; exit 1 ;;
esac
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || exit 1
FIX=d6d2ce09b                              # fix/sunxi-h616-venc HEAD (armbian-build); the kernel must have it: f35cdf390 (encoder) +
                                           # ac009bb5b/c307dd053 (own media entities, job 32 hang) + 201516cc5 (every encoder address register
                                           # gets a buffer: the IOMMU fault for address 0 of job 34) + 4d9a200e8 (v4l2-compliance fixes) +
                                           # 4727ed447 (job 35: 24-bit puts = start codes and VUI timing back, SPS/PPS nal_ref_idc 3) +
                                           # d6d2ce09b (job 37: the source buffer gets one more macroblock row, the 1366x768 fault at 0xfff83000;
                                           # debugfs cedrus/encoder-buffers). c33 is the first kernel with all of it.
COMPLIANCE_EXPECTED='v4l2-test-formats.cpp(1445)'   # the one justified fail: G/S_PARM on a stateless encoder (v4l2-compliance 1.32 predates the uAPI)
# compliance_unexpected counts only the ENCODER node's section of compliance.txt: with -m the tool also tests the decoder node,
# whose `v4l2-test-codecs.cpp(161)` fail (job 35) is the known stock-1.32 limitation (unknown cedrus fourccs -> no codec mask,
# harness/research/impl-cedrus-compliance.md); the decoder's fail lines are reported as compliance_dec_fail (information only).
TOOL=$S/tools/out/h264enc-test             # built by harness/research/ve-encoder/tools/build.sh
CLIPS=$S/runner/clips                      # generated here with the host ffmpeg (testsrc2, raw NV12)
P=/root/venc/h264enc-test
R=/root/venc                               # board dir: clips/, out/
OOPS='Unable to handle|Oops|WARNING:|workqueue lockup|iommu.*fault|Page fault|frame processing timed out'
SER=$H/harness/serial.log
PSNR_AVG_MIN=30; PSNR_MIN_MIN=28           # dB, luma; a wrong encode is below 20
OWN=""
# run name, width, height, frames, gop (0 = all IDR), qp, clip
RUNS="r1 1280 720 30 0 26 testsrc2-1280x720-30
r2 1280 720 30 10 26 testsrc2-1280x720-30
r3 1920 1080 10 0 20 testsrc2-1920x1080-10
r4 1920 1080 10 10 30 testsrc2-1920x1080-10
r5 1366 768 5 0 26 testsrc2-1366x768-5
r6 720 480 10 5 26 testsrc2-720x480-10
r7 854 480 10 5 26 testsrc2-854x480-10"
cnt() { local n; n=$(grep -c "$@" 2>/dev/null); echo "${n:-0}"; }   # match count, 0 for none or no file (grep -c || echo 0 gave "0\n0")
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
waitup() { for i in $(seq 1 ${1:-60}); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }   # waitup [tries of 5 s]
acquire() { OWN=runner-venc-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
restore() { $V/restore-kernel.sh | tee -a $OUT/runner.log   # Image, DTB (.stock), modules (.good), reboot
  sleep 15; if waitup 100; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image; readlink /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb' | tr '\n' ' ')"   # a reboot with a stuck task waits out the stop timeouts (~6 min, job 32)
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
on_stock() { [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"; }
gen_clips() { # host: raw NV12 test clips (testsrc2: moving bars, text and a counter), generated once
  mkdir -p $CLIPS
  while read -r r w h n g q c; do
    [ -s $CLIPS/$c.nv12 ] && continue
    ffmpeg -v error -y -f lavfi -i "testsrc2=size=${w}x${h}:rate=30" -frames:v $n -pix_fmt nv12 -f rawvideo $CLIPS/$c.nv12 \
      || { log "clip $c: ffmpeg failed"; exit 1; }
  done <<< "$RUNS"; }
ship_file() { # ship_file <host file> <board path>: only when the board copy differs
  local want_sha have_sha; want_sha=$(sha256sum < "$1" | cut -d' ' -f1)
  have_sha=$($SSH -n "sha256sum < $2 2>/dev/null | cut -d' ' -f1")
  [ "$want_sha" = "$have_sha" ] && { log "$(basename $2) on the board is current ($want_sha)"; return; }
  $V/ship.sh "$1" "$2" 2>&1 | tail -1 | tee -a $OUT/runner.log
  have_sha=$($SSH -n "sha256sum < $2 | cut -d' ' -f1"); [ "$want_sha" = "$have_sha" ] || blocked "ship of $2 failed"; }
ship_all() { $SSH -n "mkdir -p $R/clips $R/out"; ship_file $TOOL $P; $SSH -n "chmod +x $P"
  while read -r r w h n g q c; do ship_file $CLIPS/$c.nv12 $R/clips/$c.nv12; done <<< "$RUNS"; }
boot_trial() { # install the newest cumulative kernel with the fallback armed; it must contain the venc commit
  local c; c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
  git -C $H/wt-cumulative merge-base --is-ancestor $FIX "$c" 2>/dev/null || blocked "kernel $T ($c) lacks the venc commit $FIX"
  on_stock
  $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  $SSH -n 'dmesg | grep -q "cedrus.*Encoder registered"' || blocked "kernel $T has no cedrus encoder device (encoder not in this kernel)"
  log "kernel encoder: $($SSH -n 'dmesg | grep -o "Encoder registered as /dev/video[0-9]*"')"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
chunk_script() { # board script of a chunk ($1 = chunk name); ends with ROUND-DONE
  cat <<EOS
set -u; D=$R/out; rm -rf \$D; mkdir -p \$D; cd \$D
step() { echo "STEP \$*"; }   # every step announces itself (the host names the step on a stall) and runs under its own timeout
V="timeout -k 5 20 v4l2-ctl"
uname -v > kernel.txt; cat /proc/cmdline > cmdline.txt
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
step probe
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug   # for cedrus/encoder-buffers
dmesg | grep -i 'cedrus\|sun50i-iommu\|video-codec' > dmesg-probe.txt; cat dmesg-probe.txt
echo "boot_warnings \$(dmesg | grep -c 'WARNING:')" | tee probe.txt; dmesg | grep -B2 -A16 'WARNING:' > boot-warnings.txt
# nodes from sysfs (no ioctl before the nodes are known): the encoder vdev is named cedrus-enc, the decoder cedrus
ENC=""; DEC=""; for v in /sys/class/video4linux/video*; do n=\$(cat \$v/name 2>/dev/null)
  [ "\$n" = cedrus-enc ] && ENC=/dev/\$(basename \$v); [ "\$n" = cedrus ] && DEC=/dev/\$(basename \$v); done
# media devices are on a bus, not a class (/sys/bus/media/devices/mediaN, the job 34 "media_node none" lookup bug)
for m in /sys/bus/media/devices/media*; do echo "media /dev/\$(basename \$m) model=\$(cat \$m/model 2>&1 | tr -d '\n')"; done | tee -a probe.txt
MED=\$(for m in /sys/bus/media/devices/media*; do grep -qx cedrus \$m/model 2>/dev/null && echo /dev/\$(basename \$m) && break; done)
[ -z "\$MED" ] && [ -c /dev/media0 ] && MED=/dev/media0 && echo "media fallback /dev/media0" | tee -a probe.txt
echo "ENC \$ENC DEC \$DEC MEDIA \$MED" | tee nodes.txt
echo "media_node \${MED:-none}" | tee -a probe.txt
[ -n "\$ENC" ] || { echo "NO-ENCODER-NODE"; echo ROUND-DONE; exit 0; }
step topology
\$V -d \$ENC -D > enc-D.txt 2>&1; echo "RC \$?" >> enc-D.txt
echo "media_info \$(grep -c 'Media Driver Info' enc-D.txt)" | tee -a probe.txt        # the topology ioctl answered (the c26/c27 hang)
echo "dec_D_rc \$(\$V -d \$DEC -D > dec-D.txt 2>&1; echo \$?)" | tee -a probe.txt
step enc-info
\$V -d \$ENC --all > enc-all.txt 2>&1; \$V -d \$ENC --list-ctrls > enc-ctrls.txt 2>&1
\$V -d \$ENC --list-formats-out > enc-fmt-out.txt 2>&1; \$V -d \$ENC --list-formats > enc-fmt-cap.txt 2>&1
echo "== formats"; cat enc-fmt-out.txt enc-fmt-cap.txt | grep -E "\[|Pixel"
echo "== controls \$(grep -c ' 0x' enc-ctrls.txt)"
step compliance
if command -v v4l2-compliance >/dev/null; then
  timeout -k 5 300 v4l2-compliance -d \$ENC \${MED:+-m \$MED} > compliance.txt 2>&1; echo "RC \$?" >> compliance.txt
  echo "== compliance: \$(grep -E '^Total' compliance.txt)"; grep -E 'fail:|FAIL' compliance.txt | head -20
else echo "COMPLIANCE-SKIP (no v4l2-compliance)" | tee compliance.txt; fi
m0=\$(dmesg | wc -l); echo DMESG-ENCODES-START \$m0   # the compliance Requests test queues requests without controls: its "Failed to setup" lines are its own
run() { local name=\$1 w=\$2 h=\$3 n=\$4 g=\$5 q=\$6 c=\$7
  step encode \$name
  echo "== \$name \${w}x\${h} n=\$n gop=\$g qp=\$q"
  m1=\$(dmesg | wc -l)
  timeout -k 5 120 $P -v -w \$w -h \$h -n \$n -g \$g -q \$q -i $R/clips/\$c.nv12 -o \$name.h264 > \$name.txt 2>&1; echo "RC \$?" >> \$name.txt
  grep -E '^RESULT|^RC|ERROR|error|timeout' \$name.txt | head -8
  dmesg | tail -n +\$((m1+1)) > \$name.dmesg.txt   # per run: which run a fault belongs to (job 35's fault was r5's, not r1's)
  cat /sys/kernel/debug/cedrus/encoder-buffers > \$name.buffers.txt 2>&1   # IOVA + size of every buffer of the run's last picture (c33+)
  sed 's/^/BUFFERS: /' \$name.buffers.txt | head -14
  grep -iE 'cedrus|iommu|timed out' \$name.dmesg.txt | head -5 | sed 's/^/DMESG: /'
  if command -v gst-launch-1.0 >/dev/null && [ -s \$name.h264 ]; then
    step hwdec \$name
    timeout -k 5 120 gst-launch-1.0 -q filesrc location=\$name.h264 ! h264parse ! v4l2slh264dec ! videoconvert ! video/x-raw,format=NV12 ! filesink location=\$name.hwdec.nv12 > \$name.hwdec.txt 2>&1; echo "RC \$?" >> \$name.hwdec.txt
    echo "HWDEC \$name bytes \$(stat -c %s \$name.hwdec.nv12 2>/dev/null || echo 0) md5 \$(md5sum < \$name.hwdec.nv12 2>/dev/null | cut -c1-32) \$(tail -1 \$name.hwdec.txt)" | tee -a \$name.hwdec.txt
    rm -f \$name.hwdec.nv12
  else echo "HWDEC \$name SKIP" | tee \$name.hwdec.txt; fi
}
while read -r r w h n g q c; do run \$r \$w \$h \$n \$g \$q \$c; done <<'RUNS'
$RUNS
RUNS
step dmesg
dmesg | tail -n +\$((n1+1)) > dmesg-chunk.txt
dmesg | tail -n +\$((m0+1)) > dmesg-encodes.txt
grep -E 'cedrus|iommu|$OOPS' dmesg-chunk.txt | tail -60 | sed 's/^/DMESG: /'
ls -la *.h264 | sed 's/^/OUT: /'
echo ROUND-DONE
EOS
}
extract() { # host side: decode every stream with ffmpeg, PSNR against the clip, one line per key into results.txt
  local c=$1 d=$OUT/files/$1 r w h n g q clip fs dec frames
  grep -q NO-ENCODER-NODE $OUT/chunk-$c.txt 2>/dev/null && echo "$c all encoder_node 0" >> $OUT/results.txt || echo "$c all encoder_node 1" >> $OUT/results.txt
  grep -q "Encoder registered" $d/dmesg-probe.txt 2>/dev/null && echo "$c all probe_registered 1" >> $OUT/results.txt || echo "$c all probe_registered 0" >> $OUT/results.txt
  echo "$c all controls $(cnt ' 0x' $d/enc-ctrls.txt)" >> $OUT/results.txt
  for k in boot_warnings media_node media_info dec_D_rc; do echo "$c all $k $(awk -v k=$k '$1==k {print $2; f=1} END {if (!f) print "missing"}' $d/probe.txt 2>/dev/null || echo missing)" >> $OUT/results.txt; done
  grep '^media ' $d/probe.txt 2>/dev/null | sed "s/^/$c all /" >> $OUT/results.txt
  if grep -q COMPLIANCE-SKIP $d/compliance.txt 2>/dev/null; then echo "$c all compliance SKIP" >> $OUT/results.txt
  else
    local enc tot; enc=$(awk '$1=="ENC" {print $2}' $d/nodes.txt 2>/dev/null)
    # the encoder node's section: from "Compliance test for ... <enc>:" to its "Total for ... <enc>:" line
    awk -v n="$enc:" '/^Compliance test for / { s = ($NF == n) } s { print } /^Total for / { s = 0 }' $d/compliance.txt > $d/compliance-enc.txt 2>/dev/null
    awk -v n="$enc:" '/^Compliance test for / { s = ($0 ~ /\/dev\/video/ && $NF != n) } s && /fail:/ { print }' $d/compliance.txt > $d/compliance-dec-fails.txt 2>/dev/null
    tot=$(grep -E '^Total' $d/compliance-enc.txt 2>/dev/null | tail -1)
    echo "$c all compliance_failed $(echo "$tot" | grep -o 'Failed: [0-9]*' | grep -o '[0-9]*' || echo missing)" >> $OUT/results.txt
    echo "$c all compliance_warnings $(echo "$tot" | grep -o 'Warnings: [0-9]*' | grep -o '[0-9]*' || echo missing)" >> $OUT/results.txt
    echo "$c all compliance_unexpected $(grep 'fail:' $d/compliance-enc.txt 2>/dev/null | grep -vcF "$COMPLIANCE_EXPECTED" || true)" >> $OUT/results.txt
    echo "$c all compliance_dec_fail $(cnt . $d/compliance-dec-fails.txt)" >> $OUT/results.txt
  fi
  while read -r r w h n g q clip; do
    fs=$((w * h * 3 / 2))
    if [ ! -f $d/$r.txt ]; then echo "$c $r missing 1" >> $OUT/results.txt; continue; fi
    awk -v c=$c -v r=$r '/^RESULT/ { for (i = 2; i <= NF; i++) { split($i, kv, "="); print c, r, kv[1], kv[2] } }
                         /^RC / { print c, r, "rc", $2 }' $d/$r.txt >> $OUT/results.txt
    echo "$c $r stream_bytes $(stat -c %s $d/$r.h264 2>/dev/null || echo 0)" >> $OUT/results.txt
    # the first bytes as hex (start code 00000001, then the SPS NAL header 67 and profile 42 c0 28), the start-code and NAL counts:
    # job 35's streams began 0742c028... (no start codes, nal_ref_idc 0) because the bit writer dropped 32-bit puts
    echo "$c $r head_hex $(head -c 32 $d/$r.h264 2>/dev/null | od -An -tx1 -v | tr -d ' \n')" >> $OUT/results.txt
    [ -s $d/$r.h264 ] && python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); n = d.split(b"\x00\x00\x01")[1:]
t = [x[0] & 31 for x in n if x]; r = sys.argv[2]
print(r, "start_first", int(d[:4] == b"\x00\x00\x00\x01")); print(r, "start_codes", len(n))
print(r, "nal_sps", t.count(7)); print(r, "nal_pps", t.count(8)); print(r, "nal_idr", t.count(5)); print(r, "nal_p", t.count(1))
print(r, "sps_ref_idc", next(((x[0] >> 5) & 3 for x in n if x and x[0] & 31 == 7), -1))' $d/$r.h264 "$c $r" >> $OUT/results.txt
    echo "$c $r dmesg_iommu $(cnt -iE 'iommu.*fault|Page fault' $d/$r.dmesg.txt)" >> $OUT/results.txt
    # debugfs buffer list (d6d2ce09b): the source buffer must hold stride x (ALIGN(h,16) x 3/2 + 16) bytes (one macroblock row past
    # the NV12 picture: the engine reads past its end, job 37's 1366x768 fault)
    local bpl want_src have_src; bpl=$(( (w + 15) / 16 * 16 )); want_src=$(( bpl * ((h + 15) / 16 * 16 * 3 / 2 + 16) ))
    have_src=$(awk '$1=="source" {print strtonum($4)}' $d/$r.buffers.txt 2>/dev/null | tail -1)
    echo "$c $r buffers_file $(cnt -E '^(source|coded|mb-info|rec) ' $d/$r.buffers.txt)" >> $OUT/results.txt
    echo "$c $r source_bytes ${have_src:-missing} want $want_src" >> $OUT/results.txt
    [ -n "$have_src" ] && [ "$have_src" -ge "$want_src" ] && echo "$c $r source_room 1" >> $OUT/results.txt || echo "$c $r source_room 0" >> $OUT/results.txt
    echo "$c $r dmesg_timeout $(cnt -iE 'timed out' $d/$r.dmesg.txt)" >> $OUT/results.txt
    if [ -s $d/$r.h264 ]; then
      dec=$d/$r.dec.nv12
      ffmpeg -v error -y -i $d/$r.h264 -f rawvideo -pix_fmt nv12 $dec > $d/$r.ffmpeg-err.txt 2>&1
      echo "$c $r ffmpeg_errors $(grep -c . $d/$r.ffmpeg-err.txt)" >> $OUT/results.txt
      frames=$(( $(stat -c %s $dec 2>/dev/null || echo 0) / fs ))
      echo "$c $r decoded $frames" >> $OUT/results.txt
      echo "$c $r hwdec_md5_ffmpeg $(head -c $((frames * fs)) $dec | md5sum | cut -c1-32)" >> $OUT/results.txt
      if [ $frames -gt 0 ]; then
        ffmpeg -v error -f rawvideo -pix_fmt nv12 -s ${w}x${h} -i $dec -f rawvideo -pix_fmt nv12 -s ${w}x${h} -i $CLIPS/$clip.nv12 \
          -frames:v $frames -lavfi "psnr=stats_file=$d/$r.psnr.txt" -f null - > /dev/null 2>&1
        awk -v c=$c -v r=$r '{ for (i = 1; i <= NF; i++) if ($i ~ /^psnr_y:/) { split($i, kv, ":"); y = kv[2] + 0; if (y > 999) y = 999; s += y; if (m == "" || y < m) m = y; k++ } }
                             END { if (k) { printf "%s %s psnr_avg %.2f\n%s %s psnr_min %.2f\n%s %s psnr_frames %d\n", c, r, s / k, c, r, m, c, r, k } else print c, r, "psnr_avg 0" }' $d/$r.psnr.txt >> $OUT/results.txt
      fi
      rm -f $dec
    fi
    local hw; hw=$(grep '^HWDEC' $d/$r.hwdec.txt 2>/dev/null | tail -1)
    if echo "$hw" | grep -q SKIP; then echo "$c $r hwdec SKIP" >> $OUT/results.txt
    else echo "$c $r hwdec_frames $(( $(echo "$hw" | awk '{print $4}') / fs ))" >> $OUT/results.txt
         echo "$c $r hwdec_md5 $(echo "$hw" | awk '{print $6}')" >> $OUT/results.txt
         a=$(echo "$hw" | awk '{print $6}'); b=$(grep "^$c $r hwdec_md5_ffmpeg" $OUT/results.txt | awk '{print $4}')
         [ -n "$a" ] && [ "$a" = "$b" ] && [ "$(echo "$hw" | awk '{print $4}')" -gt 0 ] 2>/dev/null && echo "$c $r hwdec_md5_match 1" >> $OUT/results.txt || echo "$c $r hwdec_md5_match 0" >> $OUT/results.txt; fi
  done <<< "$RUNS"
  echo "$c all dmesg_bad $(cnt -E "$OOPS" $d/dmesg-chunk.txt)" >> $OUT/results.txt
  echo "$c all dmesg_iommu $(cnt -iE 'iommu.*fault|Page fault' $d/dmesg-chunk.txt)" >> $OUT/results.txt
  echo "$c all dmesg_timeout $(cnt -iE 'timed out' $d/dmesg-chunk.txt)" >> $OUT/results.txt
  echo "$c all dmesg_encode_failed $(cnt -iE 'encode failed|Failed to setup encoding|invalid coded size' $d/dmesg-encodes.txt)" >> $OUT/results.txt; }
stall_diag() { # a fresh ssh session (ConnectTimeout) after a stall: which tasks are stuck and where, for the next agent
  local d=$OUT/files/stall-diag-$1.txt; mkdir -p $OUT/files
  timeout 120 $SSH -n 'echo "== uptime"; uptime; echo "== D/R tasks"; ps -eo pid,stat,etime,wchan:32,comm | awk "NR==1 || (\$2 ~ /^[DR]/ && \$5 != \"ps\")"
    for p in $(ps -eo pid=,stat=,comm= | awk "\$2 ~ /^[DR]/ && \$3 != \"ps\" {print \$1}"); do echo "== /proc/$p/stack $(cat /proc/$p/comm 2>/dev/null)"; cat /proc/$p/stack 2>&1 | head -30; done
    echo "== dmesg tail"; dmesg | tail -80' > $d 2>&1
  log "stall diagnostics: $d ($(grep -c . $d 2>/dev/null) lines)"; }
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
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s in step '$(grep '^STEP' $f | tail -1 | cut -c6-)', killing ssh $p"; kill $p; echo "STALLED in step $(grep '^STEP' $f | tail -1 | cut -c6-)" >> $f; stall_diag $c; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c; scp -q -r "${K[@]}" root@10.56.0.107:$R/out/. $OUT/files/$c/ 2>/dev/null
  if [ -z "$oops" ] && grep -qE "$OOPS" $OUT/files/$c/dmesg-chunk.txt 2>/dev/null; then grep -E "$OOPS|Call trace|pc :|lr :" $OUT/files/$c/dmesg-chunk.txt | head -40 > $OUT/OOPS; oops=dmesg; fi
  extract $c
  [ -n "$oops" ] && oops_fail $c $oops
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
: > $OUT/results.txt
[ -x $TOOL ] || { log "missing $TOOL (run tools/build.sh)"; exit 1; }
log "job $J start, kernel $T (Image md5 $want), venc commit $FIX, chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
gen_clips
trap 'release' EXIT
acquire; on_stock; ship_all
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
