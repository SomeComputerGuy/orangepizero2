// SPDX-License-Identifier: MIT
/*
 * kbtrace: LD_PRELOAD tracer for the Arm kbase JM ioctl interface (/dev/mali0), UK 11.x.
 * Records every ioctl (in/out bytes), mmap/munmap of the mali fd, job submits (atom arrays) and job
 * events (read() on the mali fd). Before each JOB_SUBMIT and after each event read it snapshots all
 * CPU-visible GPU mappings (only pages that changed since the last snapshot). Mesa's pandecode can
 * then decode the job chains offline (kbdecode.c).
 *
 * Env: KBTRACE_OUT=<file> (default kbtrace.<pid>.bin), KBTRACE_MAX_REGION_MB (default 128),
 *      KBTRACE_NO_POST=1 (skip the after-event snapshots).
 * Markers: the traced program may call kbtrace_marker("text") (look it up with dlsym).
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#include "kbtrace.h"

#define KB_IOC_TYPE 0x80
#define KB_IOC_JOB_SUBMIT 2
#define KB_IOC_GET_GPUPROPS 3
#define COOKIE_BASE (64ul << 12)
#define FIRST_FREE ((64ul << 12) + COOKIE_BASE)

struct region { uint64_t cpu, len, gpu; int prot; uint8_t *shadow; uint8_t *valid; };
static struct region regs[4096];
static int nregs;
static unsigned char malifd[4096];
static pthread_mutex_t lk = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
static FILE *out;
static uint64_t max_region;
static int no_post;
static uint64_t seq;
static uint8_t *pagebuf;

static int (*r_ioctl)(int, unsigned long, ...);
static void *(*r_mmap)(void *, size_t, int, int, int, off_t);
static int (*r_munmap)(void *, size_t);
static ssize_t (*r_read)(int, void *, size_t);
static int (*r_close)(int);

static void init(void)
{
	if (out)
		return;
	r_ioctl = dlsym(RTLD_NEXT, "ioctl");
	r_mmap = dlsym(RTLD_NEXT, "mmap");
	r_munmap = dlsym(RTLD_NEXT, "munmap");
	r_read = dlsym(RTLD_NEXT, "read");
	r_close = dlsym(RTLD_NEXT, "close");
	const char *o = getenv("KBTRACE_OUT");
	char nm[256];
	if (!o) { snprintf(nm, sizeof nm, "kbtrace.%d.bin", getpid()); o = nm; }
	out = fopen(o, "wb");
	if (!out) { perror("kbtrace: open"); abort(); }
	setvbuf(out, NULL, _IOFBF, 1 << 20);
	max_region = (getenv("KBTRACE_MAX_REGION_MB") ? atoll(getenv("KBTRACE_MAX_REGION_MB")) : 128) << 20;
	no_post = getenv("KBTRACE_NO_POST") != NULL;
	pagebuf = malloc(1 << 20);
	fwrite(KBT_MAGIC, 1, 8, out);
}

static void rec(uint32_t type, const void *hdr, uint32_t hlen, const void *pay, uint32_t plen)
{
	struct kbt_rec r = { type, hlen + plen, seq++, 0 };
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	r.ns = ts.tv_sec * 1000000000ull + ts.tv_nsec;
	fwrite(&r, sizeof r, 1, out);
	if (hlen) fwrite(hdr, 1, hlen, out);
	if (plen) fwrite(pay, 1, plen, out);
}

static int is_mali(int fd)
{
	if (fd < 0 || fd >= 4096)
		return 0;
	if (malifd[fd])
		return malifd[fd] == 1;
	char p[64], l[128];
	snprintf(p, sizeof p, "/proc/self/fd/%d", fd);
	ssize_t n = readlink(p, l, sizeof l - 1);
	if (n < 0) return 0;
	l[n] = 0;
	malifd[fd] = strncmp(l, "/dev/mali", 9) ? 2 : 1;
	if (malifd[fd] == 1) rec(KBT_OPEN, &fd, 4, l, n);
	return malifd[fd] == 1;
}

/* read our own memory without faulting on unbacked (grow-on-GPF) pages */
static size_t safe_read(void *dst, uint64_t src, size_t len)
{
	struct iovec l = { dst, len }, r = { (void *)src, len };
	ssize_t n = process_vm_readv(getpid(), &l, 1, &r, 1, 0);
	return n < 0 ? 0 : n;
}

/* Write the pages of every region that changed since the previous snapshot. */
static void snapshot(uint32_t why)
{
	uint32_t w = why;
	rec(KBT_SNAP_BEGIN, &w, 4, NULL, 0);
	for (int i = 0; i < nregs; i++) {
		struct region *g = &regs[i];
		if (!(g->prot & PROT_READ) || g->len > max_region)
			continue;
		if (!g->shadow) {
			g->shadow = calloc(1, g->len);
			g->valid = calloc(1, g->len >> 12);
		}
		for (uint64_t off = 0; off < g->len; off += 4096) {
			uint8_t *pg = pagebuf;
			if (safe_read(pg, g->cpu + off, 4096) != 4096)
				continue;
			if (g->valid[off >> 12] && !memcmp(pg, g->shadow + off, 4096))
				continue;
			/* coalesce a run of changed pages */
			uint64_t end = off + 4096;
			memcpy(g->shadow + off, pg, 4096); g->valid[off >> 12] = 1;
			while (end < g->len && end - off < (1 << 20)) {
				uint8_t *p2 = pagebuf + (end - off);
				if (safe_read(p2, g->cpu + end, 4096) != 4096) break;
				if (g->valid[end >> 12] && !memcmp(p2, g->shadow + end, 4096)) break;
				memcpy(g->shadow + end, p2, 4096); g->valid[end >> 12] = 1;
				end += 4096;
			}
			struct kbt_mem h = { g->gpu + off, g->cpu + off, end - off };
			rec(KBT_MEM, &h, sizeof h, pagebuf, end - off);
			off = end - 4096;
		}
	}
	rec(KBT_SNAP_END, &w, 4, NULL, 0);
}

void kbtrace_marker(const char *s)
{
	pthread_mutex_lock(&lk);
	init();
	rec(KBT_MARKER, NULL, 0, s, strlen(s));
	fflush(out);
	pthread_mutex_unlock(&lk);
}

int ioctl(int fd, unsigned long req, ...)
{
	va_list ap;
	va_start(ap, req);
	void *arg = va_arg(ap, void *);
	va_end(ap);
	if (!r_ioctl) r_ioctl = dlsym(RTLD_NEXT, "ioctl");
	if (_IOC_TYPE(req) < KB_IOC_TYPE || _IOC_TYPE(req) > KB_IOC_TYPE + 2 || !is_mali(fd))
		return r_ioctl(fd, req, arg);

	pthread_mutex_lock(&lk);
	init();
	uint32_t sz = _IOC_SIZE(req);
	struct kbt_ioctl h = { fd, (uint32_t)req, 0, 0 };
	rec(KBT_IOCTL_PRE, &h, sizeof h, (_IOC_DIR(req) & _IOC_WRITE) && arg ? arg : NULL,
	    (_IOC_DIR(req) & _IOC_WRITE) && arg ? sz : 0);
	if (_IOC_TYPE(req) == KB_IOC_TYPE && _IOC_NR(req) == KB_IOC_JOB_SUBMIT && arg) {
		struct { uint64_t addr; uint32_t nr, stride; } *js = arg;
		snapshot(1);
		struct kbt_submit s = { js->nr, js->stride };
		rec(KBT_SUBMIT, &s, sizeof s, (void *)js->addr, js->nr * js->stride);
	}
	pthread_mutex_unlock(&lk);

	int ret = r_ioctl(fd, req, arg);
	int e = errno;

	pthread_mutex_lock(&lk);
	h.ret = ret; h.err = ret < 0 ? e : 0;
	rec(KBT_IOCTL_POST, &h, sizeof h, (_IOC_DIR(req) & _IOC_READ) && arg ? arg : NULL,
	    (_IOC_DIR(req) & _IOC_READ) && arg ? sz : 0);
	if (_IOC_TYPE(req) == KB_IOC_TYPE && _IOC_NR(req) == KB_IOC_GET_GPUPROPS && arg && ret > 0) {
		struct { uint64_t buffer; uint32_t size, flags; } *gp = arg;
		if (gp->buffer && gp->size)
			rec(KBT_GPUPROPS, NULL, 0, (void *)gp->buffer, ret < (int)gp->size ? ret : gp->size);
	}
	fflush(out);
	pthread_mutex_unlock(&lk);
	errno = e;
	return ret;
}

void *mmap(void *addr, size_t len, int prot, int flags, int fd, off_t off)
{
	if (!r_mmap) r_mmap = dlsym(RTLD_NEXT, "mmap");
	void *p = r_mmap(addr, len, prot, flags, fd, off);
	if (fd < 0 || !is_mali(fd))
		return p;
	int e = errno;
	pthread_mutex_lock(&lk);
	init();
	uint64_t uoff = (uint64_t)off;
	struct kbt_mmap h = { (uint64_t)addr, len, prot, flags, fd, 0, uoff, (uint64_t)p, 0 };
	if (p != MAP_FAILED) {
		if (uoff >= FIRST_FREE) h.gpu = uoff;			/* non SAME_VA: offset is the GPU VA */
		else if (uoff >= COOKIE_BASE) h.gpu = (uint64_t)p;	/* SAME_VA: CPU VA == GPU VA */
		else h.gpu = 0;					/* special handle (tracking page etc.) */
		if (h.gpu && nregs < 4096)
			regs[nregs++] = (struct region){ (uint64_t)p, len, h.gpu, prot, NULL, NULL };
	}
	rec(KBT_MMAP, &h, sizeof h, NULL, 0);
	fflush(out);
	pthread_mutex_unlock(&lk);
	errno = e;
	return p;
}
void *mmap64(void *addr, size_t len, int prot, int flags, int fd, off_t off) __attribute__((alias("mmap")));

int munmap(void *addr, size_t len)
{
	if (!r_munmap) r_munmap = dlsym(RTLD_NEXT, "munmap");
	pthread_mutex_lock(&lk);
	for (int i = 0; i < nregs; i++) {
		if (regs[i].cpu == (uint64_t)addr) {
			struct kbt_munmap h = { (uint64_t)addr, len, regs[i].gpu };
			init();
			rec(KBT_MUNMAP, &h, sizeof h, NULL, 0);
			free(regs[i].shadow); free(regs[i].valid);
			regs[i] = regs[--nregs];
			break;
		}
	}
	pthread_mutex_unlock(&lk);
	return r_munmap(addr, len);
}

ssize_t read(int fd, void *buf, size_t n)
{
	if (!r_read) r_read = dlsym(RTLD_NEXT, "read");
	ssize_t r = r_read(fd, buf, n);
	if (fd < 0 || fd >= 4096 || malifd[fd] != 1 || r <= 0)
		return r;
	int e = errno;
	pthread_mutex_lock(&lk);
	rec(KBT_EVENT, NULL, 0, buf, r);
	if (!no_post)
		snapshot(2);
	fflush(out);
	pthread_mutex_unlock(&lk);
	errno = e;
	return r;
}

int close(int fd)
{
	if (!r_close) r_close = dlsym(RTLD_NEXT, "close");
	if (fd >= 0 && fd < 4096) {
		if (malifd[fd] == 1) {
			pthread_mutex_lock(&lk);
			rec(KBT_CLOSE, &fd, 4, NULL, 0);
			fflush(out);
			pthread_mutex_unlock(&lk);
		}
		malifd[fd] = 0;
	}
	return r_close(fd);
}
