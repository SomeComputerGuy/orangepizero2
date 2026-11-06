#!/bin/bash
# Host self-test of kbtrace.c (no board, no blob): build it natively, LD_PRELOAD it into a small program that opens a
# plain file as the "mali" device (KBTRACE_DEV), does a kbase-type ioctl, mmap, read, munmap and close, and checks
# that the program exits 0 and the trace starts with the magic and an OPEN record. Job 16's SIGSEGV (record before
# init) fails this test.   Usage: kbtrace-selftest.sh [kbtrace.c]   (exit 0 = PASS)
set -u
SRC=${1:-$(dirname "$(readlink -f "$0")")/kbtrace.c}; D=$(mktemp -d); trap 'rm -rf $D' EXIT
cp "$SRC" $D/kbtrace.c; cp "$(dirname "$(readlink -f "$0")")/kbtrace.h" $D/
cat > $D/t.c <<'EOT'
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
int main(int c, char **v) {
	int fd = open(v[1], O_RDWR); if (fd < 0) return 2;
	struct { uint64_t buffer; uint32_t size, flags; } gp = { 0, 0, 0 };
	ioctl(fd, _IOW(0x80, 3, gp), &gp);			/* GET_GPUPROPS-shaped: ENOTTY on a plain file */
	struct { uint64_t addr; uint32_t nr, stride; } js = { (uint64_t)(uintptr_t)&gp, 1, sizeof gp };
	ioctl(fd, _IOW(0x80, 2, js), &js);			/* JOB_SUBMIT-shaped */
	void *p = mmap(NULL, 8192, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	char b[16]; pread(fd, b, 1, 0); read(fd, b, sizeof b);
	if (p != MAP_FAILED) munmap(p, 8192);
	close(fd); puts("selftest-done"); return 0; }
EOT
gcc -O2 -Wall -shared -fPIC -o $D/kbtrace.so $D/kbtrace.c -ldl -lpthread 2>&1 | grep -E 'error|warning' && exit 1
gcc -O2 -w -o $D/t $D/t.c || exit 1
head -c 16384 /dev/zero > $D/fakemali0
( cd $D && KBTRACE_DEV=$D/fakemali KBTRACE_OUT=$D/kbtrace.bin LD_PRELOAD=$D/kbtrace.so ./t $D/fakemali0 ) > $D/out.txt 2>&1; rc=$?
ok=1
[ $rc = 0 ] && grep -q selftest-done $D/out.txt && echo "PASS traced program rc 0" || { echo "FAIL traced program rc $rc: $(head -3 $D/out.txt)"; ok=0; }
[ "$(head -c 8 $D/kbtrace.bin 2>/dev/null)" = KBTRACE1 ] && echo "PASS kbtrace.bin magic" || { echo "FAIL kbtrace.bin missing or no magic"; ok=0; }
t=$(od -An -tu4 -j8 -N4 $D/kbtrace.bin 2>/dev/null | tr -d ' ')
[ "$t" = 1 ] && echo "PASS first record is OPEN, file $(stat -c %s $D/kbtrace.bin) bytes" || { echo "FAIL first record type '${t}' (want 1 = OPEN)"; ok=0; }
[ $ok = 1 ]
