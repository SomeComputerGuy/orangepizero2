#!/bin/bash
# Host self-test of kbtrace.c (no board, no blob): build it natively, LD_PRELOAD it into a small program that opens a
# plain file as the "mali" device (KBTRACE_DEV), does a kbase-type ioctl, mmap, read, munmap and close, and checks
# that the program exits 0 and the trace starts with the magic and an OPEN record. Job 16's SIGSEGV (record before
# init) fails this test; v3 also checks that region memory and soft-job payloads land in the trace (job 64).   Usage: kbtrace-selftest.sh [kbtrace.c]   (exit 0 = PASS)
set -u
SRC=${1:-$(dirname "$(readlink -f "$0")")/kbtrace.c}; D=$(mktemp -d); trap 'rm -rf $D' EXIT
cp "$SRC" $D/kbtrace.c; cp "$(dirname "$(readlink -f "$0")")/kbtrace.h" $D/
cat > $D/t.c <<'EOT'
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
int main(int c, char **v) {
	int fd = open(v[1], O_RDWR); if (fd < 0) return 2;
	struct { uint64_t buffer; uint32_t size, flags; } gp = { 0, 0, 0 };
	ioctl(fd, _IOW(0x80, 3, gp), &gp);			/* GET_GPUPROPS-shaped: ENOTTY on a plain file */
	/* SAME_VA-style cookie offset (>= 64 pages): a traced region; its 2nd half lies beyond EOF (SIGBUS on access,
	 * like unbacked grow-on-GPF pages), which the snapshot must skip without a signal */
	char *p = mmap(NULL, 16384, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0x41000);
	if (p == MAP_FAILED) return 3;
	strcpy(p + 4096, "KBTRACE-MEM-OK");
	/* one soft atom (JIT alloc, core_req 0x209) whose jc points at a base_jit_alloc_info, in a 64-byte base_jd_atom */
	static uint64_t jit[6] = { 0x1afe38008, 0x1000, 0x10, 0x10, 0x00000201, 0 };
	uint8_t atom[64] = { 0 }; uint64_t jc = (uint64_t)(uintptr_t)jit; uint32_t cr = 0x209;
	memcpy(atom + 8, &jc, 8); atom[40] = 1; atom[48] = 1; memcpy(atom + 52, &cr, 4);
	struct { uint64_t addr; uint32_t nr, stride; } js = { (uint64_t)(uintptr_t)atom, 1, 64 };
	ioctl(fd, _IOW(0x80, 2, js), &js);			/* JOB_SUBMIT-shaped */
	char b[16]; pread(fd, b, 1, 0); read(fd, b, sizeof b);
	munmap(p, 16384);
	close(fd); puts("selftest-done"); return 0; }
EOT
gcc -O2 -Wall -shared -fPIC -o $D/kbtrace.so $D/kbtrace.c -ldl -lpthread 2>&1 | grep -E 'error|warning' && exit 1
gcc -O2 -w -o $D/t $D/t.c || exit 1
head -c $((0x41000 + 8192)) /dev/zero > $D/fakemali0   # mapping at 0x41000 of 16 KiB: last 8 KiB beyond EOF
( cd $D && KBTRACE_DEV=$D/fakemali KBTRACE_OUT=$D/kbtrace.bin LD_PRELOAD=$D/kbtrace.so ./t $D/fakemali0 ) > $D/out.txt 2>&1; rc=$?
ok=1
[ $rc = 0 ] && grep -q selftest-done $D/out.txt && echo "PASS traced program rc 0" || { echo "FAIL traced program rc $rc: $(head -3 $D/out.txt)"; ok=0; }
[ "$(head -c 8 $D/kbtrace.bin 2>/dev/null)" = KBTRACE1 ] && echo "PASS kbtrace.bin magic" || { echo "FAIL kbtrace.bin missing or no magic"; ok=0; }
t=$(od -An -tu4 -j8 -N4 $D/kbtrace.bin 2>/dev/null | tr -d ' ')
[ "$t" = 1 ] && echo "PASS first record is OPEN, file $(stat -c %s $D/kbtrace.bin) bytes" || { echo "FAIL first record type '${t}' (want 1 = OPEN)"; ok=0; }
# job 64: the snapshot captured no memory at all (process_vm_readv refuses kbase's VM_PFNMAP mappings)
grep -a -q KBTRACE-MEM-OK $D/kbtrace.bin && echo "PASS region memory captured (KBT_MEM)" || { echo "FAIL no region memory in the trace"; ok=0; }
python3 -I - $D/kbtrace.bin <<'EOP' && echo "PASS soft-job payload recorded (KBT_SOFT, JIT alloc info)" || { echo "FAIL no KBT_SOFT record with the JIT info"; ok=0; }
import struct, sys
d = open(sys.argv[1], 'rb').read(); o = 8; ok = False
while o + 24 <= len(d):
    t, l = struct.unpack_from('<II', d, o); o += 24
    if t == 14 and l >= 16 + 48 and struct.unpack_from('<Q', d, o + 16)[0] == 0x1afe38008: ok = True
    o += l
sys.exit(0 if ok else 1)
EOP
[ $ok = 1 ]
