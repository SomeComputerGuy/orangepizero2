// SPDX-License-Identifier: MIT
/*
 * kbfake: host-side fake of the kbase JM device (/dev/mali0, UK 11.x) for running the Arm libmali blob under
 * qemu-aarch64 without a GPU. Purpose: see which render-target layout (AFBC/linear/tiled) the blob picks for a
 * given set of GPU properties, without a board session. Nothing executes on a GPU: every atom completes at once
 * (BASE_JD_EVENT_DONE), JIT allocations get an anonymous mapping. Stack it under kbtrace.so so the submitted
 * descriptors land in a kbtrace.bin that kbdecode decodes:
 *   LD_PRELOAD=kbtrace.so:kbfake.so KBTRACE_DEV=$KBFAKE_NODE ...
 * Env: KBFAKE_GPUPROPS=<file> (raw GET_GPUPROPS buffer, e.g. kbdecode's gpuprops.bin; required),
 *      /dev/mali0 opens get a /dev/null fd (the blob wants a character device; run kbtrace with KBTRACE_DEV=/dev/null),
 *      KBFAKE_SET="key=value,key=value" (override/add gpu property keys, decimal key, hex/dec value; an added key
 *      is appended as u32), KBFAKE_LOG=1 (log every ioctl to stderr).
 * DRM node opens (/dev/dri/...) and STREAM_CREATE fds get /dev/zero so the host's own GPU is never touched.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <link.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#define NR(r) (((r) >> 0) & 0xff)
#define TYPE(r) (((r) >> 8) & 0xff)
#define BASE_MEM_SAME_VA (1ull << 13)
#define COOKIE_BASE (64ul << 12)
#define TRACKING (3ul << 12)

static int (*r_open)(const char *, int, ...);
static int (*r_openat)(int, const char *, int, ...);
static ssize_t (*r_read)(int, void *, size_t);
static int (*r_poll)(struct pollfd *, nfds_t, int);
static int (*r_close)(int);
static unsigned char fake[4096];
static pthread_mutex_t lk = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
static pthread_cond_t cv = PTHREAD_COND_INITIALIZER;
static uint8_t props[4096];
static size_t nprops;
static int logon;
static uint64_t lowva = 0x1b0000000ull;	/* CPU/GPU VA allocator, top down, below 2^33 like kbase SAME_VA */
static uint64_t custom = 0x1f0000000ull;	/* non-SAME_VA (EXEC/custom) GPU VAs */
static uint64_t jitva = 0x1b0000000ull;		/* JIT GPU VAs (kbase put them at 0x1b0000000+) */
struct ev { uint32_t code; uint8_t atom, pad[3]; uint64_t udata[2]; };
static struct ev evq[4096];
static int evh, evt;
static uint64_t nsubmit, natoms;
static int closed;	/* POST_TERM seen: reads return BASE_JD_EVENT_DRV_TERMINATED like kbase_event_dequeue() */

static void L(const char *f, ...)
{
	if (!logon) return;
	va_list a; va_start(a, f); vfprintf(stderr, f, a); va_end(a);
}

__attribute__((constructor)) static void kbfake_ctor(void)
{
	r_open = dlsym(RTLD_NEXT, "open");
	r_openat = dlsym(RTLD_NEXT, "openat");
	r_read = dlsym(RTLD_NEXT, "read");
	r_poll = dlsym(RTLD_NEXT, "poll");
	r_close = dlsym(RTLD_NEXT, "close");
	logon = getenv("KBFAKE_LOG") != NULL;
	const char *p = getenv("KBFAKE_GPUPROPS");
	if (!p) { fputs("kbfake: KBFAKE_GPUPROPS not set\n", stderr); return; }
	FILE *f = fopen(p, "rb");
	if (!f) { perror("kbfake: gpuprops"); return; }
	nprops = fread(props, 1, sizeof props, f);
	fclose(f);
	const char *s = getenv("KBFAKE_SET");
	while (s && *s) {
		char *e; unsigned long k = strtoul(s, &e, 10);
		if (*e != '=') break;
		unsigned long long v = strtoull(e + 1, &e, 0);
		int found = 0;
		for (size_t i = 0; i + 4 <= nprops;) {
			uint32_t h; memcpy(&h, props + i, 4);
			size_t sz = 1u << (h & 3);
			if ((h >> 2) == k) { memcpy(props + i + 4, &v, sz); found = 1; }
			i += 4 + sz;
		}
		if (!found) { uint32_t h = (k << 2) | 2, v32 = v; memcpy(props + nprops, &h, 4); memcpy(props + nprops + 4, &v32, 4); nprops += 8; }
		fprintf(stderr, "kbfake: gpuprop %lu = 0x%llx (%s)\n", k, v, found ? "override" : "added");
		s = *e == ',' ? e + 1 : e;
	}
}

static int is_fake(int fd) { return fd >= 0 && fd < 4096 && fake[fd] == 1; }

static int fake_open(const char *path, int *fd)
{
	if (!path) return 0;
	if (!strcmp(path, "/dev/mali0")) {
		/* the blob checks S_ISCHR: /dev/null is a character device (kbtrace: KBTRACE_DEV=/dev/null) */
		*fd = r_open("/dev/null", O_RDWR | O_CLOEXEC);
		if (*fd >= 0 && *fd < 4096) fake[*fd] = 1;
		L("kbfake: open /dev/mali0 -> %d\n", *fd);
		return 1;
	}
	if (!strncmp(path, "/dev/dri/", 9)) {
		*fd = r_open("/dev/zero", O_RDWR | O_CLOEXEC);
		L("kbfake: open %s -> /dev/zero %d\n", path, *fd);
		return 1;
	}
	return 0;
}

int open(const char *path, int fl, ...)
{
	va_list a; va_start(a, fl); int mode = va_arg(a, int); va_end(a);
	int fd;
	if (fake_open(path, &fd)) return fd;
	return r_open(path, fl, mode);
}
int open64(const char *path, int fl, ...) __attribute__((alias("open")));
int openat(int dfd, const char *path, int fl, ...)
{
	va_list a; va_start(a, fl); int mode = va_arg(a, int); va_end(a);
	int fd;
	if (fake_open(path, &fd)) return fd;
	return r_openat(dfd, path, fl, mode);
}
int openat64(int dfd, const char *path, int fl, ...) __attribute__((alias("openat")));

int access(const char *path, int mode)
{
	static int (*r)(const char *, int);
	if (!r) r = dlsym(RTLD_NEXT, "access");
	if (!strcmp(path, "/dev/mali0")) return 0;
	return r(path, mode);
}
int faccessat(int dfd, const char *path, int mode, int fl)
{
	static int (*r)(int, const char *, int, int);
	if (!r) r = dlsym(RTLD_NEXT, "faccessat");
	if (!strcmp(path, "/dev/mali0")) return 0;
	return r(dfd, path, mode, fl);
}

int close(int fd)
{
	if (fd >= 0 && fd < 4096) fake[fd] = 0;
	return r_close(fd);
}

static void *lowmap(size_t len, int prot)
{
	len = (len + 0xfff) & ~0xfffull;
	for (int tries = 0; tries < 64; tries++) {
		lowva -= len;
		void *p = mmap((void *)lowva, len, prot, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE | MAP_NORESERVE, -1, 0);
		if (p == (void *)lowva) return p;
		if (p != MAP_FAILED) munmap(p, len);
		lowva -= 0x100000;
	}
	return MAP_FAILED;
}

/* mmap of the fake device. kbtrace.so's mmap calls this through RTLD_NEXT. */
void *mmap(void *addr, size_t len, int prot, int fl, int fd, off_t off)
{
	static void *(*r_mmap)(void *, size_t, int, int, int, off_t);
	if (!r_mmap) r_mmap = dlsym(RTLD_NEXT, "mmap");
	if (!is_fake(fd)) return r_mmap(addr, len, prot, fl, fd, off);
	pthread_mutex_lock(&lk);
	void *p = lowmap(len, prot ? prot : PROT_NONE);
	pthread_mutex_unlock(&lk);
	L("kbfake: mmap len 0x%zx prot %d off 0x%lx -> %p\n", len, prot, (long)off, p);
	return p;
}
void *mmap64(void *, size_t, int, int, int, off_t) __attribute__((alias("mmap")));

static void push(uint32_t code, uint8_t atom, const uint64_t *udata)
{
	struct ev *e = &evq[evt++ % 4096];
	memset(e, 0, sizeof *e);
	e->code = code; e->atom = atom; e->udata[0] = udata[0]; e->udata[1] = udata[1];
}

struct jit_info { uint64_t gpu_alloc_addr, va_pages, commit_pages, extension; uint8_t id, bin, max, flags, pad[2]; uint16_t usage; uint64_t heap_info; };

static void submit(const uint8_t *atoms, uint32_t n, uint32_t stride)
{
	nsubmit++;
	for (uint32_t i = 0; i < n; i++) {
		const uint8_t *a = atoms + (size_t)i * stride;
		uint64_t jc, udata[2], nr_extres; uint32_t core_req; uint8_t atom;
		memcpy(&jc, a + 8, 8); memcpy(udata, a + 16, 16);
		nr_extres = *(const uint16_t *)(a + 40);
		atom = a[48];
		memcpy(&core_req, a + 52, 4);
		natoms++;
		L("kbfake: atom %u jc 0x%llx core_req 0x%x\n", atom, (unsigned long long)jc, core_req);
		if ((core_req & 0x3ff) == 0x209 && jc) {	/* BASE_JD_REQ_SOFT_JIT_ALLOC: write the GPU VA */
			struct jit_info *ji = (struct jit_info *)(uintptr_t)jc;
			for (uint64_t k = 0; k < (nr_extres ? nr_extres : 1); k++) {
				uint64_t va = jitva; jitva += (ji[k].va_pages << 12) + 0x200000;
				void *p = mmap((void *)va, ji[k].va_pages << 12, PROT_READ | PROT_WRITE,
					       MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE | MAP_NORESERVE, -1, 0);
				(void)p;
				*(uint64_t *)(uintptr_t)ji[k].gpu_alloc_addr = va;
			}
		}
		push(1, atom, udata);
	}
	pthread_cond_broadcast(&cv);
}

/* KBFAKE_POKE="idx=val,...": write the blob's option table slots (libmali g24p0: table pointer at base+0x35b0410,
 * values at ctx->values + idx * 16, bool byte at +8) at the first device ioctl, after the blob parsed its config. */
static int find_mali(struct dl_phdr_info *i, size_t sz, void *d)
{
	(void)sz;
	if (i->dlpi_name && strstr(i->dlpi_name, "libmali")) { *(uintptr_t *)d = i->dlpi_addr; return 1; }
	return 0;
}
static void poke(void)
{
	static int done;
	const char *s = getenv("KBFAKE_POKE");
	if (done || !s) return;
	done = 1;
	uintptr_t base = 0;
	dl_iterate_phdr(find_mali, &base);
	uint8_t *ctx = base ? *(uint8_t **)(base + 0x35b0410) : NULL;
	if (!ctx) { fputs("kbfake: poke: no option table\n", stderr); return; }
	uint8_t *vals = *(uint8_t **)(ctx + 8);
	while (*s) {
		char *e; unsigned long k = strtoul(s, &e, 10);
		if (*e != '=') break;
		unsigned long v = strtoul(e + 1, &e, 0);
		fprintf(stderr, "kbfake: poke option %lu type %u value %u -> %lu\n", k, *(uint32_t *)(vals + k * 16),
			vals[k * 16 + 8], v);
		vals[k * 16 + 8] = v;
		s = *e == ',' ? e + 1 : e;
	}
}

int ioctl(int fd, unsigned long req, ...)
{
	static int (*r_ioctl)(int, unsigned long, ...);
	if (!r_ioctl) r_ioctl = dlsym(RTLD_NEXT, "ioctl");
	va_list a; va_start(a, req); void *arg = va_arg(a, void *); va_end(a);
	if (!is_fake(fd)) return r_ioctl(fd, req, arg);
	if (TYPE(req) != 0x80) { errno = ENOTTY; return -1; }
	int ret = 0;
	pthread_mutex_lock(&lk);
	poke();
	uint64_t *u = arg;
	switch (NR(req)) {
	case 0: case 52: { uint16_t *v = arg; v[0] = 11; v[1] = 45; break; }	/* VERSION_CHECK: what the board's kbase answered */
	case 3: {	/* GET_GPUPROPS */
		uint32_t size = ((uint32_t *)arg)[2];
		if (size) memcpy((void *)(uintptr_t)u[0], props, size < nprops ? size : nprops);
		ret = nprops;
		break;
	}
	case 5: {	/* MEM_ALLOC */
		uint64_t pages = u[0], flags = u[3];
		if (flags & BASE_MEM_SAME_VA) { u[0] = flags; u[1] = COOKIE_BASE + 0x1000; }
		else { u[0] = flags; u[1] = custom; custom += pages << 12; }
		L("kbfake: MEM_ALLOC pages 0x%llx flags 0x%llx -> 0x%llx\n", (unsigned long long)pages,
		  (unsigned long long)flags, (unsigned long long)u[1]);
		break;
	}
	case 2: submit((const uint8_t *)(uintptr_t)u[0], ((uint32_t *)arg)[2], ((uint32_t *)arg)[3]); break;
	case 17: *(uint32_t *)arg = 5; break;			/* GET_CONTEXT_ID */
	case 24: ret = r_open("/dev/zero", O_RDWR | O_CLOEXEC); break;	/* STREAM_CREATE: an fd */
	case 54: *(uint8_t *)arg = 0; break;			/* CONTEXT_PRIORITY_CHECK */
	case 13: { /* GET_DDK_VERSION */ break; }
	case 4: closed = 1; pthread_cond_broadcast(&cv); break;	/* POST_TERM */
	default: break;	/* SET_FLAGS, MEM_FREE, MEM_JIT_INIT, MEM_EXEC_INIT, POST_TERM, ...: success */
	}
	L("kbfake: ioctl nr %lu ret %d\n", NR(req), ret);
	pthread_mutex_unlock(&lk);
	return ret;
}

ssize_t read(int fd, void *buf, size_t n)
{
	if (!is_fake(fd)) return r_read(fd, buf, n);
	pthread_mutex_lock(&lk);
	struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts); ts.tv_sec += 2;
	while (evh == evt && !closed)
		if (pthread_cond_timedwait(&cv, &lk, &ts)) break;
	size_t got = 0;
	if (evh == evt && closed && n >= sizeof(struct ev)) {
		memset(buf, 0, sizeof(struct ev)); *(uint32_t *)buf = 0x7000; got = sizeof(struct ev);
	}
	while (evh != evt && got + sizeof(struct ev) <= n) {
		memcpy((uint8_t *)buf + got, &evq[evh++ % 4096], sizeof(struct ev));
		got += sizeof(struct ev);
	}
	pthread_mutex_unlock(&lk);
	if (!got) { errno = EAGAIN; return -1; }
	return got;
}

int poll(struct pollfd *pf, nfds_t n, int to)
{
	int has = 0;
	for (nfds_t i = 0; i < n; i++) if (is_fake(pf[i].fd)) has = 1;
	if (!has) return r_poll(pf, n, to);
	for (int waited = 0;; waited += 5) {
		int r = 0;
		pthread_mutex_lock(&lk);
		int ready = evh != evt || closed;
		pthread_mutex_unlock(&lk);
		for (nfds_t i = 0; i < n; i++) {
			pf[i].revents = 0;
			if (is_fake(pf[i].fd)) { if (ready && (pf[i].events & POLLIN)) pf[i].revents = POLLIN; }
			else { struct pollfd q = pf[i]; if (r_poll(&q, 1, 0) > 0) pf[i].revents = q.revents; }
			if (pf[i].revents) r++;
		}
		if (r || (to >= 0 && waited >= to)) return r;
		usleep(5000);
	}
}

__attribute__((destructor)) static void kbfake_dtor(void)
{
	fprintf(stderr, "kbfake: %llu submits, %llu atoms\n", (unsigned long long)nsubmit, (unsigned long long)natoms);
}
