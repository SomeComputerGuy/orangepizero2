#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runner package (job 63): panfrost BO mapping under memcg pressure on the newest cumulative kernel (c48+, carries
# fix/sunxi-panfrost-mmu-map-enomem a524d09da on top of the WARN removal da59f9208).
# The 2 dEQP-GLES31 draw_indirect compute_interop large drawelements 1000x1000 cases run inside a memcg
# (MemoryMax 450M..700M, like the CTS queue's 600M) so panfrost BO creation/mapping and heap growth hit -ENOMEM;
# the kernel must return errors (process gets err=12 / memcg OOM kill), never WARN/oops, never hang. Then a short
# GLES 3.1 (draw_indirect, compute, KHR compute_shader; system Mesa) and OpenCL (fork rusticl, job-52 suites)
# regression subset, compared with the baselines.
# Self-contained: board lock (fresh owner per acquire), install the newest cumulative kernel with the one-shot
# fallback armed (vdec-perf/install-kernel.sh), check its Image + panfrost.ko md5, deploy the fork Mesa build-cl to
# /root/opiz2-mesa/pme (system Mesa untouched), chunks of <= 15 min under a stall watchdog, results copied after each
# chunk, stock kernel restored (vdec-perf/restore-kernel.sh) at the end, before a lock hand-over and when blocked.
# Resumable: re-running skips the chunks listed in $OUT/state. `--print` prints the board scripts.
# Exit 0 = all chunks ran (judge with HANDOFF.md); 2 = blocked ($OUT/BLOCKED); 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/panfrost-map-enomem; MW=$H/mesa-work; SSH=$H/harness/ssh.sh
J=mapenomem; V=$H/harness/research/vdec-perf
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED
CHUNKS="oom gles31-di gles31-compute khr-compute ocl"; CT=870; STALL=870
KFIX=a524d09da                            # kernel: fix/sunxi-panfrost-mmu-map-enomem
CK=$H/kernel-check/cumulative-kernels.txt; T=$(tail -1 $CK | cut -d' ' -f1); KC=$(tail -1 $CK | cut -d' ' -f3)
LIB=$MW/build-cl/src/gallium/targets/dri/libgallium-26.2.4.so
B=/root/mapenomem                          # board work dir
D=/root/cts/deqp-gles; CTS=/root/cts/opencl-cts
SYSENV='export LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless MESA_SHADER_CACHE_DISABLE=true'
OCL='^(Atomics|C11 Atomics|Half Ops|Compute Info|Workgroups|Subgroups|Select)$'   # job-52 suites minus Relationals (698 s)
OOMCASES="dEQP-GLES31.functional.draw_indirect.compute_interop.large.drawelements_separate_grid_1000x1000_drawcount_5000
dEQP-GLES31.functional.draw_indirect.compute_interop.large.drawelements_combined_grid_1000x1000_drawcount_5000"
ROUNDS="600M-1:600M 600M-2:600M 600M-3:600M 450M:450M 500M:500M 700M:700M"   # tag:MemoryMax
M=$H/harness/research/gpu-src/stage-deqp-gles/mustpass
DPAT='WARNING|cut here|Oops|BUG:|Unable to handle|refcount_t|panfrost|gpu sched|js fault|Soft-stop|Hard-stop|Page fault|Unhandled|Memory cgroup out of memory|oom-kill|Killed process'
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
waitup() { for i in $(seq 1 60); do sleep 5; $SSH -n true 2>/dev/null && return 0; done; return 1; }
restore() { $V/restore-kernel.sh 2>&1 | tail -1 | tee -a $OUT/runner.log   # Image, DTB (.stock), modules (7.3.1.good); reboots
  sleep 15; if waitup; then log "restored: $($SSH -n 'uname -rv; readlink /boot/Image' | tr '\n' ' ')"
  else log "BOARD UNREACHABLE after restore reboot"; echo "board unreachable after restore" > $OUT/BLOCKED; fi; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; restore; release; exit 2; }
want=$(md5sum < $H/kernel-check/vdec-serve/Image.$T | cut -c1-32) || { log "no served Image.$T"; exit 1; }
boot_trial() { # newest cumulative kernel with the fix, verified by Image and panfrost.ko md5
  $SSH -n true || { log "BLOCKED: board does not answer ssh"; echo "board does not answer ssh" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'readlink /boot/Image')" = vmlinuz-7.3.1-edge-sunxi64 ] || blocked "board not on the stock image kernel at start"
  $V/install-kernel.sh $T 2>&1 | tail -3 | tee -a $OUT/runner.log
  $SSH -n 'sync; (sleep 2; systemctl reboot) >/dev/null 2>&1 &'; sleep 15
  waitup || { log "trial kernel did not come up (the fallback reverts on the next boot)"; echo "trial boot failed" > $OUT/BLOCKED; release; exit 2; }
  [ "$($SSH -n 'md5sum < /boot/$(readlink /boot/Image) | cut -c1-32')" = "$want" ] || blocked "$T Image md5 mismatch after install"
  $SSH -n 'touch /run/vdec-ok; uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  local d=$(mktemp -d) ws hs; tar xzf $H/kernel-check/vdec-serve/modules-$T.tgz -C $d 7.3.1/kernel/drivers/gpu/drm/panfrost/panfrost.ko
  ws=$(md5sum < $d/7.3.1/kernel/drivers/gpu/drm/panfrost/panfrost.ko | cut -c1-32); rm -rf $d
  hs=$($SSH -n 'md5sum < $(modinfo -n panfrost) | cut -c1-32')
  [ -n "$ws" ] && [ "$ws" = "$hs" ] && log "kernel fix: present ($T contains $KFIX, panfrost.ko md5 $hs)" || blocked "panfrost.ko on the board ($hs) is not the $T module ($ws)"; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
# host-side preconditions (no board needed)
git -C $H/wt-cumulative merge-base --is-ancestor $KFIX "$KC" 2>/dev/null || { log "newest cumulative kernel $T ($KC) lacks $KFIX"; exit 1; }
[ -f $LIB ] || { log "missing build: $LIB"; exit 1; }
log "kernel $T ($KC, Image md5 $want); fork lib $(md5sum < $LIB | cut -c1-32)"
mkdir -p $OUT/caselists; printf '%s\n' "$OOMCASES" > $OUT/caselists/oom.txt
echo dEQP-GLES31.functional.compute.basic.ubo_to_ssbo_single_invocation > $OUT/caselists/alive.txt
grep -E '^dEQP-GLES31\.functional\.draw_indirect\.' $M/gles31-main.txt > $OUT/caselists/gles31-di.txt
grep -E '^dEQP-GLES31\.functional\.compute\.' $M/gles31-main.txt > $OUT/caselists/gles31-compute.txt
grep -E '^KHR-GLES31\.core\.compute_shader\.' $M/gles31-khr-main.txt > $OUT/caselists/khr-compute.txt
for c in oom gles31-di gles31-compute khr-compute; do [ -s $OUT/caselists/$c.txt ] || { log "empty caselist $c"; exit 1; }; done
setup() { # deploy the fork (OpenCL only) to /root/opiz2-mesa/pme, copy caselists, check the CTS trees
  MESA_ENV=$MW/tools/env-cl.sh $MW/tools/deploy.sh build-cl pme 2>&1 | tail -2 | tee -a $OUT/runner.log
  local w h; w=$(md5sum < $MW/deploy/pme/lib/libgallium-26.2.4.so | cut -c1-32)
  h=$($SSH -n 'md5sum < /root/opiz2-mesa/pme/lib/libgallium-26.2.4.so | cut -c1-32')
  [ -n "$w" ] && [ "$w" = "$h" ] && log "deployed pme ok (libgallium md5 $h)" || blocked "pme deploy mismatch (host $w board $h)"
  $SSH -n "test -f /root/opiz2-mesa/pme/env.sh && test -x $D/glcts/glcts && test -x $D/gles31/deqp-gles31 && test -f $D/deqp-run.py && test -f $CTS/clcts-run.py && mkdir -p $B/caselists" || blocked "pme env.sh or the GLES/OpenCL CTS is missing on the board"
  scp -q "${K[@]}" $OUT/caselists/*.txt root@10.56.0.107:$B/caselists/ || blocked "cannot copy the caselists"; }
deqp_cmd() { echo "python3 $D/deqp-run.py --deqp $D/$1 --caselist $B/caselists/$2.txt --out $B/$2 --jobs 1 --timeout 180"; }
chunk_script() { # print the board script of a chunk; it ends with ROUND-DONE
  local cmd r
  case $1 in
    oom) cmd="rm -rf $B/oom-*"
         for r in $ROUNDS; do cmd="$cmd
t0=\$(date +%s); timeout 240 systemd-run --unit=mapenomem-${r%%:*} --wait --pipe --collect -q -p MemoryMax=${r#*:} -p MemorySwapMax=64M -p OOMPolicy=continue \\
  --setenv=LD_LIBRARY_PATH=/root/cts/lib --setenv=EGL_PLATFORM=surfaceless --setenv=MESA_SHADER_CACHE_DISABLE=true \\
  python3 $D/deqp-run.py --deqp $D/gles31/deqp-gles31 --caselist $B/caselists/oom.txt --out $B/oom-${r%%:*} --jobs 1 --timeout 180 > $B/oom-${r%%:*}.log 2>&1
rc=\$?; [ \$rc = 124 ] && { echo \"HANG ${r%%:*}: still running after 240 s\"; systemctl kill -s KILL mapenomem-${r%%:*}; systemctl stop mapenomem-${r%%:*}; }
n=\$(tail -n +2 $B/oom-${r%%:*}/results.csv 2>/dev/null | wc -l)
echo \"ROUND ${r%%:*}: rc=\$rc s=\$(( \$(date +%s)-t0 )) rows=\$n \$(tail -n +2 $B/oom-${r%%:*}/results.csv 2>/dev/null | cut -d, -f2 | sort | uniq -c | tr -s ' ' | tr '\n' ' ') err12=\$(grep -c 'err=12' $B/oom-${r%%:*}.log $B/oom-${r%%:*}/*.csv 2>/dev/null | awk -F: '{s+=\$NF} END {print s+0}')\"
( $SYSENV; rm -rf $B/alive-${r%%:*}; timeout 120 python3 $D/deqp-run.py --deqp $D/gles31/deqp-gles31 --caselist $B/caselists/alive.txt --out $B/alive-${r%%:*} --jobs 1 --timeout 60 >/dev/null 2>&1 )
echo \"GPU-ALIVE ${r%%:*}: \$(tail -n +2 $B/alive-${r%%:*}/results.csv 2>/dev/null | cut -d, -f1,2 | tr '\n' ' ')\""; done ;;
    gles31-di)      cmd="$SYSENV; $(deqp_cmd gles31/deqp-gles31 gles31-di)" ;;
    gles31-compute) cmd="$SYSENV; $(deqp_cmd gles31/deqp-gles31 gles31-compute)" ;;
    khr-compute)    cmd="$SYSENV; $(deqp_cmd glcts/glcts khr-compute)" ;;
    ocl)            cmd=". /root/opiz2-mesa/pme/env.sh
python3 $CTS/clcts-run.py --cts $CTS/test_conformance --profile $CTS/opencl_conformance_tests_mesa.csv --out $B/ocl --timeout 800 --only '$OCL'" ;;
  esac
  cat <<EOS
cd /root; uname -v
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
$cmd
echo CHUNK-RC \$?
dmesg | tail -n +\$((n1+1)) > $B/dmesg-$1.full
grep -E '$DPAT' $B/dmesg-$1.full | grep -v 'Memory cgroup stats\|Tasks state' | tail -150 | sed 's/^/DMESG: /'
echo ROUND-DONE
EOS
}
compare() { # compare <chunk> <suite>: board results.csv vs the baseline; writes $OUT/compare-<chunk>.txt
  python3 - "$OUT/files/$1/results.csv" "$H/harness/analysis/gpu/cts/$2/results.csv" "$OUT/caselists/$1.txt" > $OUT/compare-$1.txt <<'PY'
import csv, sys, collections
try: new = {r[0]: r for r in csv.reader(open(sys.argv[1])) if r and r[0] != "test"}
except OSError: new = {}
base = {r[0]: r[1] for r in csv.reader(open(sys.argv[2])) if r and r[0] != "test"}
cases = [l.strip() for l in open(sys.argv[3]) if l.strip()]
st = collections.Counter(); reg = fixed = changed = missing = 0
for c in cases:
    if c not in new: missing += 1; print("MISSING", c); continue
    s = new[c][1]; st[s] += 1; b = base.get(c, "?")
    if s == b: continue
    if b == "Pass" and s != "Pass": reg += 1; print("REGRESSION", c, b, "->", s, new[c][3] if len(new[c]) > 3 else "")
    elif s == "Pass": fixed += 1; print("FIXED", c, b, "->", s)
    else: changed += 1; print("CHANGED", c, b, "->", s)
print("SUMMARY cases=%d %s REGRESSIONS=%d FIXED=%d CHANGED=%d MISSING=%d" % (len(cases), dict(st), reg, fixed, changed, missing))
PY
  tail -1 $OUT/compare-$1.txt | tee -a $OUT/runner.log; }
run_chunk() { # run_chunk <chunk>: remote command under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt
  chunk_script $c | $SSH "mkdir -p $B; cat > $B/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  $SSH -n "timeout $CT bash $B/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  rm -rf $OUT/files/$c; mkdir -p $OUT/files/$c
  scp -q "${K[@]}" root@10.56.0.107:$B/dmesg-$c.full $OUT/files/$c/ 2>/dev/null
  case $c in
    oom) for r in $ROUNDS; do scp -q -r "${K[@]}" root@10.56.0.107:$B/oom-${r%%:*} root@10.56.0.107:$B/oom-${r%%:*}.log $OUT/files/$c/ 2>/dev/null; done
         rm -f $OUT/files/$c/*/*.qpa ;;
    ocl) scp -q -r "${K[@]}" root@10.56.0.107:$B/ocl/. $OUT/files/$c/ 2>/dev/null ;;
    *)   scp -q -r "${K[@]}" root@10.56.0.107:$B/$c/. $OUT/files/$c/ 2>/dev/null; rm -f $OUT/files/$c/*.qpa
         case $c in khr-*) compare $c gles31-khr-main ;; *) compare $c gles31-main ;; esac ;;
  esac
  grep '^DMESG: ' $f > $OUT/dmesg-$c.txt; grep '^ROUND \|^GPU-ALIVE ' $f > $OUT/rounds-$c.txt 2>/dev/null
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
