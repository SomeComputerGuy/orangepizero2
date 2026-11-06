#!/bin/bash
# Runner package for the OpenCL Mesa-side fixes (fork panfrost-opencl-fixes a0a4534b14d): ocl-mesa2.sh
# Self-contained: board lock (fresh owner name per acquire), deploy the cross-built fork to /root/opiz2-mesa/cl2 (the
# existing /root/opiz2-mesa/cl and the system Mesa stay untouched), run the OpenCL-CTS chunks (each at most ~15 min)
# on the stock image kernel under a stall watchdog, copy the results off after every chunk, release. No kernel change:
# nothing to restore. Between chunks the lock is handed over if another session waits. Resumable: re-running the same
# command skips chunks listed in $OUT/state. Exit 0 = all chunks ran (pass/fail is judged from the results, see
# HANDOFF.md); 2 = blocked (reason in $OUT/BLOCKED); 1 = setup or lock error.
set -u
H=/home/aruni/orangepizero2; S=$H/harness/research/opencl-fixes; MW=$H/mesa-work; SSH=$H/harness/ssh.sh
J=mesa2
. $H/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   # shared ssh/scp options + scp timeout + kill_pid (harness/ssh-opts.sh)
OUT=$S/logs/runner-$J; mkdir -p $OUT/files; touch $OUT/state; rm -f $OUT/BLOCKED
CHUNKS="sl basic-a basic-b basic-c basic-d f2d-r2d f2d-r2da f2d-w f2d-rw imgA imgB imgC imgD reg"; CT=870; STALL=870
FORK=a0a4534b14d                          # mesa-cl commit the build must contain (rusticl sw_copy fix on top of the rest)
LIB=$MW/build-cl/src/gallium/targets/rusticl/libRusticlOpenCL.so.1.0.0
R=/root/oclfix/mesa2                      # board results dir (clcts-run.py resumes from $R/opencl-mesa/binaries.csv)
CTS=/root/cts/opencl-cts
BASIC_A="fpmath intmath_int intmath_int2 intmath_int4 intmath_long intmath_long2 intmath_long4 hiloeo local_arg_def local_kernel_def pointer_cast if loop readimage readimage_int16 readimage_fp32 readimage3d readimage3d_int16 readimage3d_fp32 writeimage writeimage_int16 writeimage_fp32 mri_one mri_multiple imagedim_pow2 imagedim_non_pow2 vload_global vload_local vload_constant vload_private vstore_global vstore_local vstore_private int2fp fp2int createkernelsinprogram"
BASIC_B="hostptr explicit_s2v constant image_multipass_integer_coord image_multipass_float_coord imagereadwrite imagereadwrite3d image_param imagenpot image_r8 barrier wg_barrier parameter_types arrayreadwrite immutable_arrayreadwrite arraycopy imagearraycopy imagearraycopy3d negative_imagearraycopy negative_imagearraycopy3d imagecopy imagerandomcopy arrayimagecopy arrayimagecopy3d imagecopy3d enqueue_map_buffer enqueue_map_image work_item_functions work_item_functions_out_of_range work_item_functions_out_of_range_hardcoded astype"
BASIC_C="async_copy_global_to_local async_copy_local_to_global prefetch async_work_group_copy_fence_import_after_export_aliased_local async_work_group_copy_fence_import_after_export_aliased_global async_work_group_copy_fence_import_after_export_aliased_global_and_local async_work_group_copy_fence_export_after_import_aliased_local async_work_group_copy_fence_export_after_import_aliased_global async_work_group_copy_fence_export_after_import_aliased_global_and_local"
BASIC_D="sizeof vector_creation vector_swizzle vec_type_hint host_numeric_constants kernel_numeric_constants kernel_limit_constants constant_source bufferreadwriterect immutable_bufferreadwriterect async_strided_copy_global_to_local async_strided_copy_local_to_global kernel_preprocessor_macros kernel_memory_alignment_local kernel_memory_alignment_global kernel_memory_alignment_constant kernel_memory_alignment_private global_work_offsets get_global_offset kernel_call_kernel_function local_kernel_scope global_linear_id local_linear_id enqueued_local_size simple_read_image_pitch simple_write_image_pitch get_linear_ids rw_image_access_qualifier"
IMGA='^(Images \(clCopyImage 1D\)|Images \(clReadWriteImage\)|Images \(clFillImage int\)|Images \(clFillImage uint\)|Images \(API Info\)|Images \(Kernel Methods\))$'
IMGB='^(Images \(clFillImage float\)|Images \(Kernel 1D int\))$'
IMGC='^(Images \(Kernel 1D uint\)|Images \(Kernel 1D float\))$'
IMGD='^(Images \(clCopyImage 3D\))$'
REG='^(Atomics|C11 Atomics|Half Ops|Relationals|Events|Buffers|Compiler|Select|Common Functions|Geometric Functions|Compute Info|Workgroups|Subgroups|Profiling|Printf|Device Partitioning|Mem \(Host Flags\))$'
OWN=""
log() { echo "$(date '+%F %T') $*" | tee -a $OUT/runner.log; }
acquire() { OWN=runner-$J-$(date +%s); out=$($H/harness/board-lock.sh acquire $OWN) || { log "lock: $out"; exit 1; }
  case $out in *"already held"*) log "lock already held by $OWN"; exit 1;; esac; log "$out"; }
release() { [ -n "$OWN" ] && $H/harness/board-lock.sh release $OWN | tee -a $OUT/runner.log; OWN=""; }
blocked() { log "BLOCKED: $*"; echo "$*" > $OUT/BLOCKED; release; exit 2; }
others_waiting() { ls $H/harness/queue/board.wait 2>/dev/null | grep -v "\.$OWN\." | grep -q .; }
# host-side preconditions (no board needed)
[ -f $LIB ] || { log "missing build: $LIB (run: . mesa-work/tools/env-cl.sh; ninja -C mesa-work/build-cl)"; exit 1; }
head=$(git -C $MW/mesa-cl rev-parse --short=11 HEAD)
git -C $MW/mesa-cl merge-base --is-ancestor $FORK HEAD 2>/dev/null || { log "mesa-cl HEAD $head does not contain $FORK"; exit 1; }
[ -z "$(git -C $MW/mesa-cl status --short -- src 2>/dev/null)" ] || log "note: mesa-cl has uncommitted changes under src/"
[ "$LIB" -nt $MW/mesa-cl/.git/HEAD ] || [ "$LIB" -nt "$(git -C $MW/mesa-cl rev-parse --git-path HEAD)" ] || log "note: $LIB is older than the mesa-cl HEAD ref"
log "fork: $head (contains $FORK), lib $(md5sum < $LIB | cut -c1-32)"
setup() { # deploy the fork to /root/opiz2-mesa/cl2 and check the board has the CTS
  $SSH -n true || blocked "board does not answer ssh"
  $SSH -n 'uname -v' | sed 's/^/kernel: /' | tee -a $OUT/runner.log
  MESA_ENV=$MW/tools/env-cl.sh $MW/tools/deploy.sh build-cl cl2 2>&1 | tail -2 | tee -a $OUT/runner.log
  want=$(md5sum < $MW/deploy/cl2/lib/libRusticlOpenCL.so.1.0.0 | cut -c1-32)
  have=$($SSH -n 'md5sum < /root/opiz2-mesa/cl2/lib/libRusticlOpenCL.so.1.0.0 | cut -c1-32')
  [ -n "$want" ] && [ "$want" = "$have" ] && log "deployed cl2 ok (libRusticlOpenCL md5 $have)" || blocked "cl2 deploy mismatch (host $want board $have)"
  $SSH -n "test -f /root/opiz2-mesa/cl2/env.sh && test -x $CTS/test_conformance/basic/test_basic && test -x $CTS/test_conformance/images/kernel_read_write/test_image_streams && mkdir -p $R" || blocked "cl2 env.sh or the OpenCL CTS is missing on the board"; }
cts_cmd() { echo "python3 $CTS/clcts-run.py --cts $CTS/test_conformance --profile $CTS/opencl_conformance_tests_mesa.csv --out $R/opencl-mesa --timeout 800 --only '$1'"; }
chunk_script() { # print the board script of a chunk; it ends with ROUND-DONE
  local cmd
  case $1 in
    sl)       cmd=$(cts_cmd '^Images \(Samplerless (int|uint|float)\)$') ;;
    basic-a)  cmd="cd $CTS/test_conformance/basic && timeout 850 ./test_basic $BASIC_A" ;;
    basic-b)  cmd="cd $CTS/test_conformance/basic && timeout 850 ./test_basic $BASIC_B" ;;
    basic-c)  cmd="cd $CTS/test_conformance/basic && timeout 850 ./test_basic $BASIC_C" ;;
    basic-d)  cmd="cd $CTS/test_conformance/basic && timeout 850 ./test_basic $BASIC_D" ;;
    f2d-r2d)  cmd="cd $CTS/test_conformance/images/kernel_read_write && timeout 850 ./test_image_streams read CL_FILTER_NEAREST float 2D" ;;
    f2d-r2da) cmd="cd $CTS/test_conformance/images/kernel_read_write && timeout 850 ./test_image_streams read CL_FILTER_NEAREST float 2Darray" ;;
    f2d-w)    cmd="cd $CTS/test_conformance/images/kernel_read_write && timeout 850 ./test_image_streams write CL_FILTER_NEAREST float 2D 2Darray" ;;
    f2d-rw)   cmd="cd $CTS/test_conformance/images/kernel_read_write && timeout 850 ./test_image_streams read_write CL_FILTER_NEAREST float 2D 2Darray" ;;
    imgA)     cmd=$(cts_cmd "$IMGA") ;;
    imgB)     cmd=$(cts_cmd "$IMGB") ;;
    imgC)     cmd=$(cts_cmd "$IMGC") ;;
    imgD)     cmd=$(cts_cmd "$IMGD") ;;
    reg)      cmd=$(cts_cmd "$REG") ;;
  esac
  cat <<EOS
. /root/opiz2-mesa/cl2/env.sh
cd /root; uname -v
n1=\$(dmesg | wc -l); echo DMESG-START \$n1
$cmd
echo CHUNK-RC \$?
dmesg | tail -n +\$((n1+1)) | grep -E 'panfrost|gpu sched|js fault|Soft-stop|Page fault|Unhandled' | tail -40 | sed 's/^/DMESG: /'
echo ROUND-DONE
EOS
}
run_chunk() { # run_chunk <chunk>: remote command under timeout + stall watchdog; output to $OUT/chunk-<c>.txt
  local c=$1 f=$OUT/chunk-$1.txt
  chunk_script $c | $SSH "mkdir -p /root/oclfix; cat > /root/oclfix/chunk-$c.sh" || { log "chunk $c: cannot write the board script"; return; }
  $SSH -n "timeout $CT bash /root/oclfix/chunk-$c.sh" > $f 2>&1 & local p=$!
  local last=$(date +%s) sz=0
  while kill -0 $p 2>/dev/null; do sleep 20
    n=$(stat -c %s $f); [ "$n" != "$sz" ] && { sz=$n; last=$(date +%s); }
    if [ $(( $(date +%s) - last )) -gt $STALL ]; then log "STALL: chunk $c no output for $STALL s, killing ssh $p"; kill_pid $p; echo STALLED >> $f; break; fi
  done; wait $p 2>/dev/null
  case $c in sl|img*|reg) mkdir -p $OUT/files/$c; scp -q -r "${K[@]}" root@10.56.0.107:$R/opencl-mesa/. $OUT/files/$c/ 2>/dev/null ;; esac
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
