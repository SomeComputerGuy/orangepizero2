#!/bin/bash
# Runner package for the GLES advanced-blend coherency fix (fork panfrost-opencl-fixes dc7266d584b): gles-advblend.sh
# Self-contained: board lock (fresh owner name per acquire), deploy the cross-built fork to /root/opiz2-mesa/gl1 (the
# system Mesa and /root/opiz2-mesa/cl* stay untouched), run the chunks (each at most ~15 min) on whatever kernel is
# booted under a stall watchdog, copy the results off after every chunk, compare the CTS chunks with the baseline
# (harness/analysis/gpu/cts/<suite>/results.csv), release. No kernel change: nothing to restore. Between chunks the lock
# is handed over if another session waits. Resumable: re-running the same command skips chunks listed in $OUT/state.
# Exit 0 = all chunks ran (pass/fail is judged from the results, see HANDOFF.md); 2 = blocked (reason in $OUT/BLOCKED);
# 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/gles-advblend; MW=$H/mesa-work; SSH=$H/harness/ssh.sh
J=advblend
K=(-i $H/harness/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=$H/harness/known_hosts -o LogLevel=ERROR)
OUT=$S/logs/runner; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED
CHUNKS="repro khr-adv deqp-fbfetch deqp-ms khr-ms deqp-fbo gles3-blend-a gles3-blend-b"; CT=870; STALL=870
FORK=dc7266d584b                          # mesa-cl commit the build must contain (the advanced-blend fix)
LIB=$MW/build-cl/src/gallium/targets/dri/libgallium-26.2.4.so
R=/root/oclfix/advblend                   # board results dir
D=/root/cts/deqp-gles                     # board dEQP/glcts install (deqp-run.py, glcts/, gles3/, gles31/, mustpass/)
FORKENV='. /root/opiz2-mesa/gl1/env.sh; export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/root/cts/lib EGL_PLATFORM=surfaceless MESA_SHADER_CACHE_DISABLE=true'
SYSENV='export LD_LIBRARY_PATH=/root/cts/lib EGL_PLATFORM=surfaceless MESA_SHADER_CACHE_DISABLE=true'
M=$H/harness/research/gpu-src/stage-deqp-gles/mustpass   # same mustpass lists as the board's $D/mustpass
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; release; exit 2; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
# host-side preconditions (no board needed)
[ -f $LIB ] || { log "missing build: $LIB (run: . mesa-work/tools/env-cl.sh; ninja -C mesa-work/build-cl)"; exit 1; }
[ -f $S/host/advblend-arm64 ] || { log "missing $S/host/advblend-arm64 (see RESULTS.md for the cross-compile line)"; exit 1; }
head=$(git -C $MW/mesa-cl rev-parse --short=11 HEAD)
git -C $MW/mesa-cl merge-base --is-ancestor $FORK HEAD 2>/dev/null || { log "mesa-cl HEAD $head does not contain $FORK"; exit 1; }
[ -z "$(git -C $MW/mesa-cl status --short -- src 2>/dev/null)" ] || log "note: mesa-cl has uncommitted changes under src/"
strings $LIB | grep -q "Mesa 26.2.4 (git-${FORK:0:10}" || log "note: $LIB version string is not git-${FORK:0:10} (stale build?)"
log "fork: $head (contains $FORK), libgallium $(md5sum < $LIB | cut -c1-32)"
# caselists (host side, from the mustpass lists)
mkdir -p $OUT/caselists
grep -E '^dEQP-GLES31\.functional\.(shaders\.framebuffer_fetch|blend_equation_advanced)\.' $M/gles31-main.txt > $OUT/caselists/deqp-fbfetch.txt
grep -E '^dEQP-GLES31\.functional\.(sample_shading|shaders\.multisample_interpolation|shaders\.sample_variables|shaders\.builtin_var)\.' $M/gles31-main.txt > $OUT/caselists/deqp-ms.txt
grep -E '^dEQP-GLES31\.functional\.fbo\.' $M/gles31-main.txt > $OUT/caselists/deqp-fbo.txt
grep -E '^KHR-GLES31\.core\.blend_equation_advanced\.' $M/gles31-khr-main.txt > $OUT/caselists/khr-adv.txt
grep -E '^KHR-GLES31\.core\.(sample_variables|draw_buffers_indexed|framebuffer_no_attachments)\.' $M/gles31-khr-main.txt > $OUT/caselists/khr-ms.txt
grep -E '^dEQP-GLES3\.functional\.fragment_ops\.blend\.' $M/gles3-main.txt | awk 'NR%2==1' > $OUT/caselists/gles3-blend-a.txt
grep -E '^dEQP-GLES3\.functional\.fragment_ops\.blend\.' $M/gles3-main.txt | awk 'NR%2==0' > $OUT/caselists/gles3-blend-b.txt
for c in deqp-fbfetch deqp-ms deqp-fbo khr-adv khr-ms gles3-blend-a gles3-blend-b; do n=$(wc -l < $OUT/caselists/$c.txt); [ "$n" -gt 0 ] || { log "empty caselist $c"; exit 1; }; done
setup() { # deploy the fork to /root/opiz2-mesa/gl1, the repro binary and the caselists; check the board has the CTS
  $SSH -n true || blocked "board does not answer ssh"
  $SSH -n 'uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  MESA_ENV=$MW/tools/env-cl.sh $MW/tools/deploy.sh build-cl gl1 2>&1 | tail -2 | tee -a $OUT/runner.log
  want=$(md5sum < $MW/deploy/gl1/lib/dri/libgallium-26.2.4.so | cut -c1-32)
  have=$($SSH -n 'md5sum < /root/opiz2-mesa/gl1/lib/dri/libgallium-26.2.4.so | cut -c1-32')
  [ -n "$want" ] && [ "$want" = "$have" ] && log "deployed gl1 ok (libgallium md5 $have)" || blocked "gl1 deploy mismatch (host $want board $have)"
  $SSH -n "test -f /root/opiz2-mesa/gl1/env.sh && test -x $D/glcts/glcts && test -x $D/gles31/deqp-gles31 && test -x $D/gles3/deqp-gles3 && test -f $D/deqp-run.py && mkdir -p $R/caselists" || blocked "gl1 env.sh or the GLES CTS is missing on the board"
  scp -q "${K[@]}" $S/host/advblend-arm64 root@10.56.0.107:$R/advblend || blocked "cannot copy advblend to the board"
  scp -q "${K[@]}" $OUT/caselists/*.txt root@10.56.0.107:$R/caselists/ || blocked "cannot copy the caselists"
  $SSH -n "chmod +x $R/advblend"; }
deqp_cmd() { echo "python3 $D/deqp-run.py --deqp $D/$1 --caselist $R/caselists/$2.txt --out $R/$2 --jobs 1 --timeout 180"; }
chunk_script() { # print the board script of a chunk; it ends with ROUND-DONE
  local cmd
  case $1 in
    repro) cmd="cd $R
r() { tag=\$1; shift; $R/advblend \"\$@\" > $R/repro-\$tag.txt 2>&1; echo \"TAG \$tag: \$(grep -E '^(renderer|first pixel|RESULT)' $R/repro-\$tag.txt | tr '\n' ' ')\"; }
( $SYSENV; r sys-mixed --size 1024; r sys-mixed-barrier --size 1024 --barrier )
( $FORKENV
  r fork-mixed --size 1024; r fork-mixed-2 --size 1024; r fork-mixed-3 --size 1024; r fork-multiply --seq multiply --size 1024
  r fork-mixed-barrier --size 1024 --barrier; r fork-mixed-x8 --size 1024 --repeat 8; r fork-mixed-256 --size 256
  PAN_MESA_DEBUG=fbfetch_opaque r knob-opaque --size 1024
  PAN_MESA_DEBUG=fbfetch_overdraw r knob-overdraw --size 1024
  PAN_MESA_DEBUG=persample_1x r knob-persample --size 1024
  PAN_MESA_DEBUG=fbfetch_opaque,fbfetch_overdraw r knob-opaque-overdraw --size 1024
  PAN_MESA_DEBUG=fbfetch_opaque,persample_1x r knob-opaque-persample --size 1024
  PAN_MESA_DEBUG=fbfetch_overdraw,persample_1x r knob-overdraw-persample --size 1024
  PAN_MESA_DEBUG=fbfetch_opaque,fbfetch_overdraw,persample_1x r knob-all --size 1024
  PAN_MESA_DEBUG=fbfetch_opaque,fbfetch_overdraw,persample_1x r knob-all-2 --size 1024 )" ;;
    khr-adv)       cmd="$FORKENV; $(deqp_cmd glcts/glcts khr-adv)" ;;
    khr-ms)        cmd="$FORKENV; $(deqp_cmd glcts/glcts khr-ms)" ;;
    deqp-fbfetch)  cmd="$FORKENV; $(deqp_cmd gles31/deqp-gles31 deqp-fbfetch)" ;;
    deqp-ms)       cmd="$FORKENV; $(deqp_cmd gles31/deqp-gles31 deqp-ms)" ;;
    deqp-fbo)      cmd="$FORKENV; $(deqp_cmd gles31/deqp-gles31 deqp-fbo)" ;;
    gles3-blend-a) cmd="$FORKENV; $(deqp_cmd gles3/deqp-gles3 gles3-blend-a)" ;;
    gles3-blend-b) cmd="$FORKENV; $(deqp_cmd gles3/deqp-gles3 gles3-blend-b)" ;;
  esac
  cat <<EOS
cd /root; uname -v
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
$cmd
echo CHUNK-RC \$?
dmesg | tail -n +\$((n1+1)) | grep -E 'panfrost|gpu sched|js fault|Soft-stop|Page fault|Unhandled' | tail -40 | sed 's/^/DMESG: /'
echo ROUND-DONE
EOS
}
compare() { # compare <chunk> <suite>: board results.csv vs the baseline; writes $OUT/compare-<chunk>.txt
  python3 - "$OUT/files/$1/results.csv" "$H/harness/analysis/gpu/cts/$2/results.csv" "$OUT/caselists/$1.txt" > $OUT/compare-$1.txt <<'PY'
import csv, sys, collections
new = {r[0]: r for r in csv.reader(open(sys.argv[1])) if r and r[0] != "test"}
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
  chunk_script $c | $SSH "mkdir -p $R; cat > $R/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  $SSH -n "timeout $CT bash $R/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  mkdir -p $OUT/files/$c
  case $c in
    repro) scp -q "${K[@]}" root@10.56.0.107:$R/repro-\*.txt $OUT/files/$c/ 2>/dev/null ;;
    *) scp -q -r "${K[@]}" root@10.56.0.107:$R/$c/. $OUT/files/$c/ 2>/dev/null; rm -f $OUT/files/$c/*.qpa
       case $c in khr-*) compare $c gles31-khr-main ;; gles3-*) compare $c gles3-main ;; *) compare $c gles31-main ;; esac ;;
  esac
  grep '^DMESG: ' $f > $OUT/dmesg-$c.txt
  grep -q ROUND-DONE $f && { echo $c >> $OUT/state; log "chunk $c done"; } || log "chunk $c ended without ROUND-DONE"; }
[ "${1:-}" = "--print" ] && { for c in $CHUNKS; do echo "## $c"; chunk_script $c; done; exit 0; }
log "job $J start, chunks: $CHUNKS, done before: $(tr '\n' ' ' < $OUT/state)"
trap 'release' EXIT
acquire; setup
for c in $CHUNKS; do
  grep -qx "$c" $OUT/state && continue
  if others_waiting; then log "another session waits: handing over the lock"; release; acquire; setup; fi
  log "chunk $c start"; run_chunk $c
done
release
log "job $J end: $(wc -l < $OUT/state) of $(echo $CHUNKS | wc -w) chunks done"
[ -f $OUT/BLOCKED ] && exit 2; exit 0
