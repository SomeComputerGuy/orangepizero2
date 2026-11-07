#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner job 69-image-check (DEV, ~70-90 min): reflash the board with the newest SERVER image (harness/reflash.sh, the
# harness/REFLASH.md procedure, scripted), then check the image: kernel + boot, verify-board.sh (CUPS, scan stack,
# GStreamer JPEG autoplug, ...), our +opiz2 packages (gst-plugins-bad/-good, Mesa fork), GStreamer elements and JPEG
# decodes, the gst-libav MPEG-1 fallback (job 24 check 1), PAN_I_WANT_A_BROKEN_VULKAN_DRIVER system-wide, vulkaninfo
# (panvk, Vulkan 1.0.x), vkcube (needs HDMI), dEQP-VK smoke + job 52's subgroup cases, GLES (eglinfo, kmscube,
# job 52's gles3 derivate set) and OpenCL (clinfo, job 52's suites) on the SYSTEM Mesa, and dmesg. It also restages
# /root/cts (harness/analysis/gpu/cts-restage.sh, no --start), which the reflash wipes and job 68 needs.
#   bash harness/research/image-check/runner/image-check.sh            run (resumable: finished steps are skipped)
#   bash harness/research/image-check/runner/image-check.sh --check    print CHECK 0-17 + VERDICT from the results
# Pause: touch harness/research/image-check/logs/runner/PAUSE (stops before the next step, releases the lock, exit 4);
# resume = the same command (rm the PAUSE file first). Another session waiting for the board gets it between steps.
# Exit: 0 all steps done (judge with --check); 2 blocked (logs/runner/BLOCKED says why); 4 paused; 1 setup/lock error.
# The board never runs a trial kernel here: it is on the new image's own kernel from the reflash on.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/image-check; R=$S/runner; OUT=$S/logs/runner
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}"); SSH=$H/harness/ssh.sh
IMGDIR=$H/armbian-build/output/images
PAT='Armbian-unofficial_26.11.0-trunk_Orangepizero2_stonking_edge_*.img.xz'
CCM1=$H/build/gst-mpeg1/bundle/vec/ccm1          # job 24's MPEG-1 conformance stream (16x16, 129 frames)
BSTEPS="pkgs gst libav venv vulkan gles ocl dmesg"
mkdir -p $OUT; touch $OUT/state $OUT/runner.log
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }

# ---------------- --check: mechanical verdicts from the result files ----------------
if [ "${1:-}" = --check ]; then
  exec 2>/dev/null   # a missing result file is judged by the checks (FAIL), not reported by grep
  fail=0; nt=0
  res() { echo "CHECK $1 $2: $3 ($4)"; [ "$3" = FAIL ] && fail=1; [ "$3" = NOT-TESTED ] && nt=1; return 0; }
  g() { grep -m1 "^$2" $OUT/$1.txt 2>/dev/null | cut -d' ' -f2-; }   # g <step> KEY -> rest of the first KEY line
  done_() { grep -q "^STEP-DONE $1" $OUT/$1.txt 2>/dev/null; }
  IMG=$(head -1 $OUT/image.txt 2>/dev/null); KV=$(sed -n 2p $OUT/image.txt 2>/dev/null)
  [ -n "$IMG" ] && [ -n "$KV" ] && res 0 image PASS "$(basename "$IMG") kernel $KV; $(sed -n 3p $OUT/image.txt)" || res 0 image FAIL "image.txt missing"
  L=$(ls -1 $OUT/reflash*.log 2>/dev/null | tr '\n' ' ')
  if [ -n "$L" ] && grep -q 'FLASHER: RESULT OK' $L && grep -q 'ssh ok:' $L && grep -qx 'rc=0' $(ls -1t $OUT/reflash*.log | head -1) && ! grep -qiE 'oops|BUG:|panic' $L
  then res 1 reflash PASS "$(grep -h -m1 -o 'ssh ok:.*' $L | head -1)"; else res 1 reflash FAIL "logs: ${L:-none}; last: $([ -n "$L" ] && tail -1 $(ls -1t $OUT/reflash*.log | head -1))"; fi
  u=$(g pkgs UNAME); l=$(g pkgs IMAGE-LINK)
  [[ $u == "$KV-edge-sunxi64 "* ]] && [ "$l" = "vmlinuz-$KV-edge-sunxi64" ] && res 2 "kernel + boot" PASS "$u; /boot/Image -> $l; state $(g pkgs SYSTEM-STATE)" || res 2 "kernel + boot" FAIL "uname: ${u:-missing}; link: ${l:-missing}; want $KV-edge-sunxi64"
  nf=$(grep -c '^FAIL' $OUT/verify.txt 2>/dev/null); np=$(grep -c '^PASS' $OUT/verify.txt 2>/dev/null)
  [ "$nf" = 0 ] && [ "${np:-0}" -ge 20 ] && res 3 verify-board PASS "$np PASS, 0 FAIL" || res 3 verify-board FAIL "$np PASS, $nf FAIL: $(grep '^FAIL' $OUT/verify.txt 2>/dev/null | tr -s ' ' | tr '\n' '|')"
  bad=$(grep '^PKG ' $OUT/pkgs.txt 2>/dev/null | grep -v -E '^PKG [^ ]+ ii .*\+opiz2' | tr '\n' '|'); no=$(g pkgs NOT-OURS); oc=$(g pkgs OURS-COUNT)
  [ -z "$bad" ] && [ "${no%% *}" = 0 ] && [ "${oc:-0}" -ge 8 ] && grep -q 'file:/opt/opiz2-media' $OUT/pkgs.txt && res 4 "packages +opiz2" PASS "$oc packages of mesa/gst-plugins-bad/-good, all +opiz2; $(grep '^PKG libgl1-mesa-dri\|^PKG gstreamer1.0-plugins-bad\|^PKG gstreamer1.0-plugins-good' $OUT/pkgs.txt | cut -d' ' -f2,4- | tr '\n' ';') ffmpeg: $(g pkgs FFMPEG)" || res 4 "packages +opiz2" FAIL "not ours: ${bad:-} ${no:-missing}; count ${oc:-0}; repo: $(g pkgs REPO)"
  e=""; for x in v4l2sljpegdec v4l2jpegdec v4l2slh264dec v4l2slh265dec v4l2slmpeg2dec v4l2slvp8dec v4l2slvp9dec jpegdec avdec_mpeg2video; do grep -qx "ELEM $x yes" $OUT/gst.txt 2>/dev/null || e="$e $x"; done
  [ -z "$e" ] && grep -q 'v4l2jpegdec:MARGINAL' <<< "$(g gst RANK-ENV)" && grep -qi 'marginal' <<< "$(g gst RANK-V4L2JPEGDEC)" && res 5 "gst elements + rank" PASS "$(g gst V4L2CODECS); v4l2jpegdec $(g gst RANK-V4L2JPEGDEC)" || res 5 "gst elements + rank" FAIL "missing:${e:- none}; rank env $(g gst RANK-ENV); $(g gst RANK-V4L2JPEGDEC)"
  j1=$(grep -m1 '^JPEG v4l2sljpegdec ' $OUT/gst.txt); j2=$(grep -m1 '^JPEG v4l2jpegdec ' $OUT/gst.txt); j3=$(grep -m1 '^JPEG jpegdec ' $OUT/gst.txt); ja=$(g gst JPEG-AUTOPLUG)
  hw() { grep -q 'rc=0 size=115200 ' <<< "$1" && [ "$(grep -o 'irqs=[0-9]*' <<< "$1" | cut -d= -f2)" -ge 1 ]; }
  hw "$j1" && hw "$j2" && grep -q 'rc=0 size=115200 ' <<< "$j3" && grep -q '^rc=0 ' <<< "$ja" && ! grep -qE 'picked=\[[^]]*v4l2jpegdec' <<< "$ja" && res 6 "JPEG decodes" PASS "$j1 | $j2 | $j3 | autoplug $ja" || res 6 "JPEG decodes" FAIL "$j1 | $j2 | $j3 | autoplug $ja"
  m=$(g libav MG1S); db=$(g libav CCM1-DB)
  if [ -z "$m" ]; then res 7 "gst-libav MPEG-1 fallback (job 24 check 1)" FAIL "libav.txt missing"
  elif [ "${m%% *}" != 0 ]; then res 7 "gst-libav MPEG-1 fallback (job 24 check 1)" SKIP "the image kernel enumerates MG1S ($m); $db"
  elif grep -q '^ii' <<< "$(g libav LIBAV-PKG)" && [ -n "$(g libav SWDEC)" ] && grep -q '^rc=0 .* size=49536 irqs=0 ' <<< "$db" && ! grep -q v4l2slmpeg2dec <<< "$db" && grep -qE 'picked=\[[^]]*(avdec_mpeg|mpeg2dec)' <<< "$db"
  then res 7 "gst-libav MPEG-1 fallback (job 24 check 1)" PASS "no MG1S; libav $(g libav LIBAV-PKG); sw: $(g libav SWDEC); ccm1 $db"
  else res 7 "gst-libav MPEG-1 fallback (job 24 check 1)" FAIL "MG1S $m; libav $(g libav LIBAV-PKG); sw: $(g libav SWDEC); ccm1 ${db:-missing}"; fi
  v=""; for k in LOGIN-ENV ETC-ENVIRONMENT SYSTEMD-SYSTEM SYSTEMD-USER-CONF ENVIRONMENT-D SERVICE-ENV; do [ "$(g venv $k)" = 1 ] || v="$v $k=$(g venv $k)"; done
  [ -z "$v" ] && done_ venv && res 8 "PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 everywhere" PASS "login, /etc/environment, system + user managers, environment.d, a system service" || res 8 "PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 everywhere" FAIL "not 1:$v"
  a=$(g vulkan PANVK-API); dv=$(g vulkan PANVK-DEVICE); di=$(g vulkan PANVK-DRIVERINFO)
  [ "$(g vulkan VULKANINFO)" = rc=0 ] && [[ $a =~ ^1\.0\.[0-9]+$ ]] && [[ $dv == *Mali-G31* ]] && [[ $di == *+opiz2* ]] && res 9 "vulkaninfo panvk (login env)" PASS "apiVersion $a, $dv, $di; without the variable panvk devices: $(g vulkan NO-ENV-PANVK)" || res 9 "vulkaninfo panvk (login env)" FAIL "$(g vulkan VULKANINFO) api=${a:-none} device=${dv:-none} driverInfo=${di:-none}"
  c=$(g vulkan VKCUBE)
  case $c in "rc=0 "*) res 10 "vkcube --c 100" PASS "$c" ;; "not-run hdmi=disconnected"*) res 10 "vkcube --c 100" NOT-TESTED "$c" ;; *) res 10 "vkcube --c 100" FAIL "${c:-missing}: $(tail -3 $OUT/files/vkcube.txt 2>/dev/null | tr '\n' '|')" ;; esac
  sg=$(grep -c '^SG .* rc=0 result=\[ Pass' $OUT/vulkan.txt 2>/dev/null)
  grep -q '^SMOKE rc=0' $OUT/vulkan.txt && grep -qE 'Failed: 0/' <<< "$(g vulkan SMOKE-FAILED)" && grep -q 'Pass' <<< "$(g vulkan SMOKE-TRIANGLE)" && [ "$sg" = 9 ] && [ "$(g vulkan VK-DMESG)" = 0 ] && res 11 "Vulkan offscreen (dEQP-VK smoke + 9 subgroup cases)" PASS "smoke $(g vulkan SMOKE-FAILED), triangle $(g vulkan SMOKE-TRIANGLE); subgroup 9/9 Pass; dmesg 0" || res 11 "Vulkan offscreen (dEQP-VK smoke + 9 subgroup cases)" FAIL "$(grep -E '^SMOKE' $OUT/vulkan.txt | tr '\n' '|') subgroup Pass $sg/9: $(grep '^SG' $OUT/vulkan.txt | grep -v 'result=\[ Pass' | tr '\n' '|') dmesg $(g vulkan VK-DMESG)"
  er=$(g gles EGL-RENDERER); ev=$(g gles EGL-VERSION); gs=$(g gles GLES-SUMMARY)
  [[ $er == *Mali-G31* ]] && [[ $ev == *"OpenGL ES 3.1"* ]] && [[ $ev == *+opiz2* ]] && grep -q '556 cases' <<< "$gs" && grep -qE 'Pass 556( |$)' <<< "$gs" && [ "$(g gles GLES-DMESG)" = 0 ] && res 12 "GLES (eglinfo + gles3 derivate 556)" PASS "$er; $ev; $gs" || res 12 "GLES (eglinfo + gles3 derivate 556)" FAIL "renderer ${er:-none}; version ${ev:-none}; ${gs:-no summary}; dmesg $(g gles GLES-DMESG)"
  k=$(g gles KMSCUBE)
  case $k in "rc=0 "*) res 13 kmscube PASS "$k" ;; "not-run hdmi=disconnected"*) res 13 kmscube NOT-TESTED "$k" ;; *) res 13 kmscube FAIL "${k:-missing}" ;; esac
  ns=$(grep -c '^OCL-SUITE .* Pass$' $OUT/ocl.txt 2>/dev/null)
  grep -q '^CLINFO rc=0' $OUT/ocl.txt && grep -qi rusticl <<< "$(g ocl CL-PLATFORM)" && [[ $(g ocl CL-DEVICE) == *Mali-G31* ]] && [ "$ns" = 8 ] && [ "$(g ocl OCL-DMESG)" = 0 ] && res 14 "OpenCL (clinfo + job 52 suites)" PASS "$(g ocl CL-PLATFORM) / $(g ocl CL-DEVICE) / $(g ocl CL-VERSION); 8/8 suites Pass" || res 14 "OpenCL (clinfo + job 52 suites)" FAIL "$(g ocl CLINFO); platform $(g ocl CL-PLATFORM); device $(g ocl CL-DEVICE); suites Pass $ns/8: $(grep '^OCL-SUITE' $OUT/ocl.txt | grep -v ' Pass$' | tr '\n' '|') dmesg $(g ocl OCL-DMESG)"
  [ "$(g dmesg DMESG-BAD)" = 0 ] && res 15 dmesg PASS "0 Oops/BUG/panic/GPU fault lines" || res 15 dmesg FAIL "$(g dmesg DMESG-BAD) lines: $(grep '^DMESG-LINE' $OUT/dmesg.txt 2>/dev/null | cut -c12- | tr '\n' '|')"
  grep -q 'staged; not started' $OUT/restage.txt 2>/dev/null && grep -qx 'rc=0' $OUT/restage.txt && res 16 "/root/cts restaged for job 68" PASS "$(grep -E '^== (deqp-vk|deqp-gles|opencl-cts):' $OUT/restage.txt | tr '\n' '|')" || res 16 "/root/cts restaged for job 68" FAIL "$(tail -3 $OUT/restage.txt 2>/dev/null | tr '\n' '|')"
  f=$(cat $OUT/final.txt 2>/dev/null)
  [ "$f" = "vmlinuz-$KV-edge-sunxi64" ] && res 17 "end state" PASS "/boot/Image -> $f (the image's stock kernel), lock released" || res 17 "end state" FAIL "/boot/Image -> ${f:-unknown}"
  if [ $fail != 0 ]; then echo "VERDICT: FAIL"; elif [ $nt != 0 ]; then echo "VERDICT: PASS (with NOT-TESTED checks: no display attached)"; else echo "VERDICT: PASS"; fi
  exit 0
fi

# ---------------- run ----------------
[ $# = 0 ] || { echo "usage: image-check.sh [--check]"; exit 1; }
rm -f $OUT/BLOCKED
IMG=$(ls -1t $IMGDIR/$PAT 2>/dev/null | grep -Ev '_(minimal|desktop)\.img\.xz$' | head -1)
[ -n "$IMG" ] && [ -f "$IMG.sha" ] || { log "no server image ($PAT without _minimal/_desktop) with its .sha in $IMGDIR"; exit 1; }
KV=$(basename "$IMG" | sed -nE 's/.*_edge_([0-9]+\.[0-9]+\.[0-9]+)\.img\.xz$/\1/p')
[ -n "$KV" ] || { log "cannot read the kernel version from $(basename "$IMG")"; exit 1; }
if [ -f $OUT/image.txt ] && [ "$(head -1 $OUT/image.txt)" != "$IMG" ]; then   # another image: start over
  A=$OUT.$(date +%s); mv $OUT $A; mkdir -p $OUT; touch $OUT/state $OUT/runner.log; log "results of another image moved to $A"; fi
printf '%s\n%s\n%s\n' "$IMG" "$KV" "$(cat "$IMG.sha")" > $OUT/image.txt
[ -f $CCM1 ] || { log "missing $CCM1 (job 24 bundle)"; exit 1; }
OWN=""
acquire() { OWN=image-check-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; release; exit 2; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
between() { # before every step: pause point and hand-over (the board is on the image kernel at every step boundary)
  if [ -f $OUT/PAUSE ]; then log "PAUSE file found: pausing before $1"; release; exit 4; fi
  if others_waiting; then log "another session waits for the board: handing over before $1"; release; acquire; fi; }
step_done() { grep -qx "$1" $OUT/state; }
# watched <name> <timeout-s> <stall-s> cmd...: output to $OUT/<name>.txt (+ "rc=N"); kills on timeout or stall
watched() { local n=$1 to=$2 st=$3; shift 3; local f=$OUT/$n.txt
  timeout -k 30 $to "$@" > $f 2>&1 & local p=$! last=$(date +%s) sz=-1 s
  while kill -0 $p 2>/dev/null; do sleep 20; s=$(stat -c %s $f)
    [ "$s" != "$sz" ] && { sz=$s; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $st ]; then log "STALL: $n no output for $st s, killing $p"; kill_pid $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null; local rc=$?; echo "rc=$rc" >> $f; return $rc; }

trap 'release' EXIT
log "job 69-image-check start: $(basename "$IMG") (kernel $KV)"
acquire

# 1. reflash (harness/REFLASH.md steps 3-5, scripted)
if ! step_done reflash; then
  between reflash
  pgrep -f 'scripts/serial-log.py$' > /dev/null || pgrep -fx 'python3 -I scripts/serial-log.py' > /dev/null || blocked "scripts/serial-log.py is not running (REFLASH.md precondition)"
  cd $H
  watched reflash-dryrun 900 600 harness/reflash.sh --dry-run --image "$IMG"
  d=$OUT/reflash-dryrun.txt
  grep -q 'dry run complete' $d && grep -q 'manifest served ok' $d && grep -q 'image served ok' $d || blocked "reflash dry run failed: $(grep -iE 'fail|error|differ' $d | head -5 | tr '\n' '|')"
  rf() { log "reflash ($1) start"; harness/reflash.sh $2 > $OUT/$1.log 2>&1 & local p=$! last=$(date +%s) sz=-1 s t0=$(date +%s)
    while kill -0 $p 2>/dev/null; do sleep 30; s=$(stat -c %s $OUT/$1.log); [ "$s" != "$sz" ] && { sz=$s; last=$(date +%s); }
      if [ $(( $(date +%s) - last )) -gt 2400 ] || [ $(( $(date +%s) - t0 )) -gt 5400 ]; then log "STALL/timeout: reflash ($1), killing $p"; kill_pid $p; echo STALLED >> $OUT/$1.log; break; fi; done
    wait $p 2>/dev/null; local rc=$?; echo "rc=$rc" >> $OUT/$1.log; log "reflash ($1) rc=$rc"; return $rc; }
  if ! rf reflash "--image $IMG"; then
    if grep -q 'FLASHER: RESULT OK' $OUT/reflash.log && grep -qE 'first-login automation failed|key/timezone setup failed' $OUT/reflash.log; then
      rf reflash-post "--post-only" || blocked "reflash --post-only failed: $(tail -5 $OUT/reflash-post.log | tr '\n' '|')"
    elif grep -qE 'flasher failed|U-Boot pxe step failed' $OUT/reflash.log; then
      mv $OUT/reflash.log $OUT/reflash-try1.log
      rf reflash "--image $IMG" || blocked "reflash failed twice: $(tail -5 $OUT/reflash.log | tr '\n' '|')"
    else blocked "reflash failed: $(tail -30 $OUT/reflash.log | tr '\n' '|')"; fi
  fi
  echo reflash >> $OUT/state
fi
$SSH -n true 2>/dev/null || blocked "board does not answer ssh after the reflash"
[ "$($SSH -n 'readlink /boot/Image')" = "vmlinuz-$KV-edge-sunxi64" ] || blocked "board not on the image kernel vmlinuz-$KV-edge-sunxi64 (/boot/Image -> $($SSH -n 'readlink /boot/Image'))"

# 2. verify-board.sh, 3. /root/cts restage (the GPU checks need it; job 68 too)
if ! step_done verify; then between verify; watched verify 600 300 $H/harness/verify-board.sh
  grep -qE '^(PASS|FAIL) +hwrng' $OUT/verify.txt && echo verify >> $OUT/state || log "verify-board.sh did not finish: $(tail -2 $OUT/verify.txt | tr '\n' ' ')"; fi
if ! step_done restage; then between restage
  watched restage 3600 900 $H/harness/analysis/gpu/cts-restage.sh && grep -q 'staged; not started' $OUT/restage.txt && echo restage >> $OUT/state || log "restage: rc=$(tail -1 $OUT/restage.txt)"; fi

# 4. board checks (board-checks.sh, login shell)
$SSH "mkdir -p /root/imgchk && cat > /root/imgchk/board-checks.sh" < $R/board-checks.sh || blocked "cannot copy board-checks.sh"
$SSH "cat > /root/imgchk/ccm1" < $CCM1 || blocked "cannot copy ccm1"
for b in $BSTEPS; do
  step_done $b && continue
  between $b
  log "step $b"
  case $b in ocl) to=1800 ;; gles|vulkan) to=1200 ;; *) to=600 ;; esac
  watched $b $to 900 $SSH "bash -l /root/imgchk/board-checks.sh $b $KV"
  grep -q "^STEP-DONE $b" $OUT/$b.txt && echo $b >> $OUT/state || log "step $b not finished: $(tail -2 $OUT/$b.txt | tr '\n' ' ')"
done
mkdir -p $OUT/files
SCP_TIMEOUT=600 scp -q "${K[@]}" root@10.56.0.107:'/root/imgchk/*.txt' root@10.56.0.107:'/root/imgchk/*.log' $OUT/files/ 2>/dev/null
SCP_TIMEOUT=600 scp -q -r "${K[@]}" root@10.56.0.107:/root/imgchk/ocl root@10.56.0.107:/root/imgchk/gles3-derivate $OUT/files/ 2>/dev/null
$SSH -n 'readlink /boot/Image' > $OUT/final.txt 2>/dev/null
release; trap - EXIT
log "job 69-image-check done: $(wc -l < $OUT/state) steps finished of 11 (reflash verify restage $BSTEPS)"
bash $R/image-check.sh --check | tee $OUT/check.txt
[ "$(wc -l < $OUT/state)" = 11 ] && exit 0
log "unfinished steps: rerun the same command once"; exit 2
