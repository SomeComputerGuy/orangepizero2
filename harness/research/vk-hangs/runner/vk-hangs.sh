#!/bin/bash
# Runner package for the Vulkan hangs (fork panfrost-opencl-fixes b7a705442bd, CLPER_OLD for read_invocation): vk-hangs.sh
# Self-contained: board lock (fresh owner name per acquire), deploy the cross-built fork to /root/opiz2-mesa/vk1 (the
# system Mesa and the older /root/opiz2-mesa/cl* stay untouched), copy the diagnostic Vulkan shaders + vkcomp, run the
# chunks (each at most ~15 min) under a stall watchdog, copy results off after every chunk, release. Kernel: installs
# the newest cumulative kernel with the one-shot fallback armed (harness/research/vdec-perf/install-kernel.sh, the
# ocl-job.sh pattern; it must carry the panfrost soft-stop/resume fix e544ddb00) and restores the stock image kernel
# (vmlinuz-7.3.1-edge-sunxi64) at the end and before every lock hand-over to another waiting session.
# Resumable: re-running the same command skips chunks listed in $OUT/state. Exit 0 = all chunks ran (pass/fail is
# judged from the results, see HANDOFF.md); 2 = blocked (reason in $OUT/BLOCKED); 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/vk-hangs; MW=$H/mesa-work; V=$H/harness/research/vdec-perf; SSH=$H/harness/ssh.sh
J=vkhangs
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED
CHUNKS="diag cases-sg cases-frag-a cases-frag-b subset1 subset2 subset3 subset4 ocl gles"; CT=870; STALL=870
FORK=b7a705442bd                          # mesa-cl commit the build must contain (CLPER_OLD for read_invocation)
SOFTSTOP=e544ddb00                        # kernel commit the cumulative kernel must contain (panfrost soft-stop/resume)
T=$(tail -1 $H/kernel-check/cumulative-kernels.txt | cut -d' ' -f1)   # newest cumulative tag (install-kernel.sh does the same)
LIB=$MW/build-cl/src/panfrost/vulkan/libvulkan_panfrost.so
B=/root/vkhangs                           # board work dir
VK=/root/cts/deqp-vk; CTS=/root/cts/opencl-cts; GL=/root/cts/deqp-gles
VKENV='export PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 MESA_VK_IGNORE_CONFORMANCE_WARNING=1 MESA_VK_VERSION_OVERRIDE=1.1 PANVK_DEBUG=sync'
FORKENV=". /root/opiz2-mesa/vk1/env.sh; export VK_ICD_FILENAMES=\$VK_DRIVER_FILES; $VKENV"
SYSENV="export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/panfrost_icd.json VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/panfrost_icd.json; $VKENV"
DEQP_ARGS='--deqp-log-images=disable --deqp-log-shader-sources=disable --deqp-shadercache=disable'
SG_CASES="dEQP-VK.subgroups.basic.compute.subgroupelect dEQP-VK.subgroups.basic.compute.subgroupelect_requiredsubgroupsize dEQP-VK.subgroups.basic.graphics.subgroupelect dEQP-VK.subgroups.ballot_broadcast.compute.subgroupbroadcast_int8_t dEQP-VK.subgroups.ballot_broadcast.compute.subgroupbroadcast_uint dEQP-VK.subgroups.basic.compute.subgroupbarrier dEQP-VK.subgroups.builtin_var.compute.subgroupsize_compute"
FRAG_A="dEQP-VK.spirv_assembly.type.vec4.i8.clamp_frag dEQP-VK.spirv_assembly.type.vec4.u32.bit_field_insert_offset16_count16_frag dEQP-VK.spirv_assembly.type.vec4.i16.bit_field_insert_offset8_count16_frag dEQP-VK.spirv_assembly.type.vec4.u16.bit_field_insert_offset8_count16_frag"
FRAG_B="dEQP-VK.spirv_assembly.type.vec4.i8.bit_field_insert_offset16_count64_frag dEQP-VK.spirv_assembly.type.vec4.i64.bit_field_u_extract_offset8_count16_frag dEQP-VK.spirv_assembly.type.vec4.u64.bit_field_insert_offset8_count64_frag"
OCL='^(Atomics|C11 Atomics|Half Ops|Relationals|Compute Info|Workgroups|Subgroups|Select)$'
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
restore() { $SSH -n 'ln -sfn vmlinuz-7.3.1-edge-sunxi64 /boot/Image; rm -f /boot/vdec-trial; sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
boot_trial() { # install the newest cumulative kernel with the fallback armed (ocl-job.sh pattern)
  [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"
  $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$KIMG" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok'; log "kernel fix: present ($T contains $SOFTSTOP)"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
# host-side preconditions (no board needed)
[ -f $LIB ] || { log "missing build: $LIB (run: . mesa-work/tools/env-cl.sh; ninja -C mesa-work/build-cl)"; exit 1; }
[ -f $S/host/vkcomp-arm64 ] && [ -f $S/host/diag/d8-cts-elect.spv ] || { log "missing $S/host/vkcomp-arm64 or diag/*.spv"; exit 1; }
head=$(git -C $MW/mesa-cl rev-parse --short=11 HEAD)
git -C $MW/mesa-cl merge-base --is-ancestor $FORK HEAD 2>/dev/null || { log "mesa-cl HEAD $head does not contain $FORK"; exit 1; }
[ -z "$(git -C $MW/mesa-cl status --short -- src 2>/dev/null)" ] || log "note: mesa-cl has uncommitted changes under src/"
[ "$(stat -c %Y $LIB)" -ge "$(git -C $MW/mesa-cl log -1 --format=%ct $FORK)" ] || { log "$LIB is older than commit $FORK: rebuild build-cl"; exit 1; }
KIMG=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || { log "no served kernel Image.$T"; exit 1; }
c=$(awk -v t=$T '$1==t{print $3}' $H/kernel-check/cumulative-kernels.txt)
git -C $H/wt-cumulative merge-base --is-ancestor $SOFTSTOP "$c" 2>/dev/null || { log "kernel $T ($c) lacks the panfrost soft-stop fix $SOFTSTOP"; exit 1; }
log "fork: $head (contains $FORK), lib $(md5sum < $LIB | cut -c1-32); kernel $T ($c, Image md5 $KIMG)"
setup() { # deploy the fork to /root/opiz2-mesa/vk1, copy the diag tools, check the CTS trees
  $SSH -n true || blocked "board does not answer ssh"
  $SSH -n 'uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  MESA_ENV=$MW/tools/env-cl.sh $MW/tools/deploy.sh build-cl vk1 2>&1 | tail -2 | tee -a $OUT/runner.log
  want=$(md5sum < $MW/deploy/vk1/lib/libvulkan_panfrost.so | cut -c1-32)
  have=$($SSH -n 'md5sum < /root/opiz2-mesa/vk1/lib/libvulkan_panfrost.so | cut -c1-32')
  [ -n "$want" ] && [ "$want" = "$have" ] && log "deployed vk1 ok (libvulkan_panfrost md5 $have)" || blocked "vk1 deploy mismatch (host $want board $have)"
  $SSH -n "test -f /root/opiz2-mesa/vk1/panfrost_icd.json && test -x $VK/deqp-vk && test -f $VK/mustpass/vk-subset.txt && test -x $CTS/test_conformance/basic/test_basic && test -x $GL/gles3/deqp-gles3 && mkdir -p $B/trace $B/logs" || blocked "vk1 icd json, deqp-vk, the OpenCL CTS or deqp-gles3 is missing on the board"
  scp -q "${K[@]}" $S/host/vkcomp-arm64 root@10.56.0.107:$B/vkcomp || blocked "cannot copy vkcomp"
  scp -q -r "${K[@]}" $S/host/diag root@10.56.0.107:$B/ || blocked "cannot copy the diag shaders"
  scp -q "${K[@]}" $H/harness/analysis/gpu/deqp-run.py root@10.56.0.107:$VK/deqp-run.py || blocked "cannot copy deqp-run.py"
  $SSH -n "chmod +x $B/vkcomp && $B/vkcomp 2>&1 | head -1" | tee -a $OUT/runner.log; }
diag_script() { # vkcomp matrix: fork x 8 shaders x 3 local sizes, then system Mesa x 4 shaders x 3 (fault baseline)
  cat <<EOS
run1() { drv=\$1; sh=\$2; lx=\$3; ly=\$4; lz=\$5; nb=1; tag=\$drv-\$sh-\${lx}x\${ly}x\${lz}
  rm -f $B/trace/\$tag.*; n=\$(dmesg | wc -l)
  out=\$( ( if [ \$drv = fork ]; then $FORKENV; else $SYSENV; fi; export PANVK_DEBUG=sync,trace PANDECODE_DUMP_FILE=$B/trace/\$tag; timeout 30 $B/vkcomp $B/diag/\$sh.spv \$lx \$ly \$lz 4 2 2 \$nb 2>&1 ) ); rc=\$?
  excs=\$(cat $B/trace/\$tag.* 2>/dev/null | grep 'Exception Status' | awk '{print \$3}' | sort | uniq -c | awk '{printf "%sx%s ", \$1, \$2}')
  echo "DIAG \$tag rc=\$rc excs=[\$excs] out=[\$(echo "\$out" | grep -v '^device\|^pipeline\|^dispatch' | head -1 | cut -c1-80)] wait=[\$(echo "\$out" | grep '^dispatch' | head -1)]"
  dmesg | tail -n +\$((n+1)) | grep -E 'panfrost|gpu sched|js fault|Soft-stop|Page fault|Unhandled' | tail -6 | sed "s/^/DMESG \$tag: /"
}
for sh in d1-plain d2-ballot d3-elect d4-shared d5-ids d6-broadcast d7-vote d8-cts-elect; do for ls in "1 1 1" "4 1 1" "3 5 7"; do run1 fork \$sh \$ls; done; done
for sh in d1-plain d2-ballot d3-elect d6-broadcast; do for ls in "1 1 1" "4 1 1" "3 5 7"; do run1 sys \$sh \$ls; done; done
tar -czf $B/trace.tgz -C $B trace
EOS
}
cases_script() { # one deqp-vk process per case under its own timeout, fork driver, wall time recorded
  cat <<EOS
$FORKENV
cd $VK
for c in $1; do n=\$(dmesg | wc -l); t0=\$(date +%s)
  timeout 200 ./deqp-vk --deqp-case=\$c $DEQP_ARGS --deqp-log-filename=$B/logs/\$c.qpa > $B/logs/\$c.txt 2>&1; rc=\$?
  echo "CASE \$c rc=\$rc t=\$(( \$(date +%s) - t0 ))s result=[\$(grep -E '^  (Pass|Fail|NotSupported|QualityWarning|Crash|Timeout|InternalError)' $B/logs/\$c.txt | head -1 | tr -s ' ')] msg=[\$(grep -E 'Incomplete job|Assert|FATAL|Aborted' $B/logs/\$c.txt | head -1)]"
  dmesg | tail -n +\$((n+1)) | grep -E 'panfrost|gpu sched|js fault|Soft-stop|Page fault|Unhandled' | tail -6 | sed "s/^/DMESG \$c: /"
done
EOS
}
chunk_script() { # print the board script of a chunk; it ends with ROUND-DONE
  local body
  case $1 in
    diag)         body=$(diag_script) ;;
    cases-sg)     body=$(cases_script "$SG_CASES") ;;
    cases-frag-a) body=$(cases_script "$FRAG_A") ;;
    cases-frag-b) body=$(cases_script "$FRAG_B") ;;
    subset*)      body="$FORKENV
cd $VK; [ -f $B/vk-subset-fork11/summary.txt ] && { echo SUBSET-ALREADY-COMPLETE; } || timeout 850 python3 $VK/deqp-run.py --deqp $VK/deqp-vk --caselist $VK/mustpass/vk-subset.txt --out $B/vk-subset-fork11 --jobs 1 --timeout 300
[ -f $B/vk-subset-fork11/summary.txt ] && echo SUBSET-COMPLETE || echo SUBSET-INCOMPLETE \$(cat $B/vk-subset-fork11/shard-*.csv 2>/dev/null | wc -l) of 5225" ;;
    ocl)          body=". /root/opiz2-mesa/vk1/env.sh
python3 $CTS/clcts-run.py --cts $CTS/test_conformance --profile $CTS/opencl_conformance_tests_mesa.csv --out $B/ocl --timeout 800 --only '$OCL'" ;;
    gles)         body=". /root/opiz2-mesa/vk1/env.sh; export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:/root/cts/lib EGL_PLATFORM=surfaceless
grep 'functional.shaders.derivate' $GL/mustpass/gles3-main.txt > $B/gles3-derivate.txt; wc -l $B/gles3-derivate.txt
timeout 850 python3 $GL/deqp-run.py --deqp $GL/gles3/deqp-gles3 --caselist $B/gles3-derivate.txt --out $B/gles3-derivate --jobs 1 --timeout 180" ;;
  esac
  cat <<EOS
cd /root; uname -v
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
$body
echo CHUNK-RC \$?
dmesg | tail -n +\$((n1+1)) | grep -E 'panfrost|gpu sched|js fault|Soft-stop|Page fault|Unhandled' | tail -60 | sed 's/^/DMESG: /'
echo ROUND-DONE
EOS
}
run_chunk() { # run_chunk <chunk>: remote command under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt
  chunk_script $c | $SSH "mkdir -p $B; cat > $B/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  $SSH -n "timeout $CT bash $B/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c
  case $c in
    diag)    scp -q "${K[@]}" root@10.56.0.107:$B/trace.tgz $OUT/files/$c/ 2>/dev/null ;;
    cases*)  scp -q -r "${K[@]}" root@10.56.0.107:$B/logs/. $OUT/files/$c/ 2>/dev/null ;;
    subset*) scp -q -r "${K[@]}" root@10.56.0.107:$B/vk-subset-fork11/. $OUT/files/$c/ 2>/dev/null
             [ -f $OUT/files/$c/results.csv ] && python3 $S/runner/vk-cmp.py $S/runner/baseline-vk-subset-override1.1.csv.xz $OUT/files/$c/results.csv > $OUT/files/$c/cmp.txt 2>&1 ;;
    ocl)     scp -q -r "${K[@]}" root@10.56.0.107:$B/ocl/. $OUT/files/$c/ 2>/dev/null ;;
    gles)    scp -q -r "${K[@]}" root@10.56.0.107:$B/gles3-derivate/. $OUT/files/$c/ 2>/dev/null ;;
  esac
  grep '^DMESG' $f > $OUT/dmesg-$c.txt
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
[ "${1:-}" = "--print" ] && { for c in $CHUNKS; do echo "## $c"; chunk_script $c; done; exit 0; }
log "job $J start, chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire; boot_trial; setup
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; restore; release; acquire; boot_trial; setup; fi
  log "chunk $c start"; run_chunk $c
done
restore; release
log "job $J end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
