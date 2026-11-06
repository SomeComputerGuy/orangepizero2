// SPDX-License-Identifier: MIT
/* kbdecode: decode a kbtrace.bin with Mesa's pandecode (host tool).
 * Usage: kbdecode <trace.bin> <outdir> [gpu_id_hex]
 * Writes <outdir>/index.txt (ioctls, markers, submits, events) and <outdir>/submit-NNNN.txt (pandecode of every
 * hardware atom in that submit, memory = snapshot taken just before the submit). Also writes
 * <outdir>/mem-NNNN/ (raw region contents after the events that follow submit NNNN) when KBDECODE_MEM=1.
 * v3 (after runner job 64): a submit whose atoms get a non-DONE event is decoded again from the memory snapshot
 * taken after that event (<outdir>/submit-NNNN-post.txt: the GPU has written the exception status and fault
 * pointer into the job header), index.txt gets one `POST` line per hardware atom (exception status, first
 * incomplete task, fault pointer, 64 bytes at the fault pointer), and the soft-job payloads (KBT_SOFT) are listed:
 * JIT alloc requests (gpu_alloc_addr, va/commit/extension pages, id, flags) and the value the kernel wrote at
 * gpu_alloc_addr (`JITADDR` lines, from the after-event snapshots). */
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "kbtrace.h"

struct pandecode_context;
struct pandecode_context *pandecode_create_context(bool to_stderr);
void pandecode_destroy_context(struct pandecode_context *ctx);
void pandecode_inject_mmap(struct pandecode_context *ctx, uint64_t gpu_va, void *cpu, unsigned sz, const char *name);
void pandecode_jc(struct pandecode_context *ctx, uint64_t jc_gpu_va, uint64_t gpu_id);
void pandecode_next_frame(struct pandecode_context *ctx);

struct reg { uint64_t gpu, len, cpu; int prot; uint8_t *d; };
static struct reg R[8192];
static int nr;
static struct reg *find(uint64_t a)
{
	for (int i = 0; i < nr; i++)
		if (a >= R[i].gpu && a < R[i].gpu + R[i].len) return &R[i];
	return NULL;
}
/* copy n bytes at GPU VA a from the snapshot memory; 0 if not (fully) inside one region */
static int rd(uint64_t a, void *d, unsigned n)
{
	struct reg *g = find(a);
	if (!g || a + n > g->gpu + g->len) return 0;
	memcpy(d, g->d + (a - g->gpu), n);
	return 1;
}
struct atm { uint64_t jc; uint32_t core_req; uint8_t nr; };
static struct atm last[256];
static unsigned nlast;
struct jitreq { uint64_t addr, last_val; uint8_t id; int printed; };
static struct jitreq jits[256];
static unsigned njits;

static const char *ioc_name(uint32_t req)
{
	static char b[32];
	unsigned t = (req >> 8) & 0xff, n = req & 0xff;
	static const char *nm[] = { [0] = "VERSION_CHECK", [1] = "SET_FLAGS", [2] = "JOB_SUBMIT", [3] = "GET_GPUPROPS",
		[4] = "POST_TERM", [5] = "MEM_ALLOC", [6] = "MEM_QUERY", [7] = "MEM_FREE", [8] = "HWCNT_READER_SETUP",
		[12] = "DISJOINT_QUERY", [13] = "GET_DDK_VERSION", [14] = "MEM_JIT_INIT", [15] = "MEM_SYNC",
		[16] = "MEM_FIND_CPU_OFFSET", [17] = "GET_CONTEXT_ID", [18] = "TLSTREAM_ACQUIRE", [19] = "TLSTREAM_FLUSH",
		[20] = "MEM_COMMIT", [21] = "MEM_ALIAS", [22] = "MEM_IMPORT", [23] = "MEM_FLAGS_CHANGE", [24] = "STREAM_CREATE",
		[25] = "FENCE_VALIDATE", [27] = "MEM_PROFILE_ADD", [29] = "STICKY_RESOURCE_MAP", [30] = "STICKY_RESOURCE_UNMAP",
		[31] = "MEM_FIND_GPU_START_AND_OFFSET", [32] = "HWCNT_SET", [38] = "MEM_EXEC_INIT", [50] = "GET_CPU_GPU_TIMEINFO",
		[51] = "KINSTR_JM_FD", [54] = "CONTEXT_PRIORITY_CHECK", [55] = "SET_LIMITED_CORE_COUNT",
		[56] = "KINSTR_PRFCNT_ENUM_INFO", [57] = "KINSTR_PRFCNT_SETUP" };
	if (t == 0x80 && n < sizeof nm / sizeof nm[0] && nm[n]) return nm[n];
	snprintf(b, sizeof b, "0x%02x:%u", t, n);
	return b;
}

static void hex(FILE *f, const uint8_t *p, unsigned n)
{
	for (unsigned i = 0; i < n; i++) fprintf(f, "%02x%s", p[i], (i & 15) == 15 ? " " : "");
}

/* pandecode every hardware atom of the last submit with the current snapshot memory into fn */
static int pdecode(const char *fn, uint64_t gpu_id)
{
	fflush(stderr);
	FILE *o = freopen(fn, "w", stderr);
	if (!o) { perror(fn); return 1; }
	struct pandecode_context *ctx = pandecode_create_context(true);
	for (int i = 0; i < nr; i++) {
		char nm[64]; snprintf(nm, sizeof nm, "r%d", i);
		pandecode_inject_mmap(ctx, R[i].gpu, R[i].d, R[i].len, nm);
	}
	for (unsigned k = 0; k < nlast; k++) {
		fprintf(stderr, "\n######## atom %u jc 0x%" PRIx64 " core_req 0x%x\n", last[k].nr, last[k].jc, last[k].core_req);
		if (last[k].jc && !(last[k].core_req & 0x200 /* BASE_JD_REQ_SOFT_JOB */) && find(last[k].jc))
			pandecode_jc(ctx, last[k].jc, gpu_id);
	}
	fflush(stderr);
	pandecode_destroy_context(ctx);
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 3) { fprintf(stderr, "usage: kbdecode trace.bin outdir [gpu_id]\n"); return 1; }
	FILE *in = fopen(argv[1], "rb");
	char mg[8];
	if (!in || fread(mg, 1, 8, in) != 8 || memcmp(mg, KBT_MAGIC, 8)) { fprintf(stderr, "bad trace\n"); return 1; }
	mkdir(argv[2], 0755);
	uint64_t gpu_id = argc > 3 ? strtoull(argv[3], NULL, 16) : 0x70930000;
	bool dump_mem = getenv("KBDECODE_MEM") != NULL;
	char fn[4096];
	snprintf(fn, sizeof fn, "%s/index.txt", argv[2]);
	FILE *ix = fopen(fn, "w");
	struct kbt_rec r;
	uint8_t *buf = NULL; size_t cap = 0;
	int nsub = 0, last_sub = -1, post_needed = 0, post_done = 0;
	char last_marker[256] = "";
	while (fread(&r, sizeof r, 1, in) == 1) {
		if (r.len > cap) { cap = r.len * 2; buf = realloc(buf, cap); }
		if (fread(buf, 1, r.len, in) != r.len) break;
		switch (r.type) {
		case KBT_OPEN: fprintf(ix, "%8" PRIu64 " open fd %d %.*s\n", r.seq, *(int *)buf, r.len - 4, buf + 4); break;
		case KBT_IOCTL_PRE: case KBT_IOCTL_POST: {
			struct kbt_ioctl *h = (void *)buf;
			uint32_t pl = r.len - sizeof *h;
			if (r.type == KBT_IOCTL_PRE && ((h->req & 0xff) == 2)) break; /* submits listed separately */
			fprintf(ix, "%8" PRIu64 " %s %s", r.seq, r.type == KBT_IOCTL_PRE ? "ioctl>" : "ioctl<", ioc_name(h->req));
			if (r.type == KBT_IOCTL_POST) fprintf(ix, " ret=%d err=%d", h->ret, h->err);
			if (pl) { fprintf(ix, " ["); hex(ix, buf + sizeof *h, pl < 64 ? pl : 64); fprintf(ix, "%s]", pl > 64 ? "..." : ""); }
			fprintf(ix, "\n");
			break; }
		case KBT_MMAP: {
			struct kbt_mmap *h = (void *)buf;
			fprintf(ix, "%8" PRIu64 " mmap len=0x%" PRIx64 " prot=%d off=0x%" PRIx64 " -> cpu 0x%" PRIx64 " gpu 0x%" PRIx64 "\n",
				r.seq, h->len, h->prot, h->off, h->ret, h->gpu);
			if (h->gpu && nr < 8192) { R[nr] = (struct reg){ h->gpu, h->len, h->ret, h->prot, calloc(1, h->len) }; nr++; }
			break; }
		case KBT_MUNMAP: {
			struct kbt_munmap *h = (void *)buf;
			fprintf(ix, "%8" PRIu64 " munmap cpu 0x%" PRIx64 " len 0x%" PRIx64 "\n", r.seq, h->addr, h->len);
			for (int i = 0; i < nr; i++) if (R[i].cpu == h->addr) { free(R[i].d); R[i] = R[--nr]; break; }
			break; }
		case KBT_MEM: {
			struct kbt_mem *h = (void *)buf;
			struct reg *g = find(h->gpu);
			if (g && h->gpu + h->len <= g->gpu + g->len) memcpy(g->d + (h->gpu - g->gpu), buf + sizeof *h, h->len);
			else fprintf(ix, "%8" PRIu64 " MEM outside region 0x%" PRIx64 "\n", r.seq, h->gpu);
			break; }
		case KBT_MARKER:
			snprintf(last_marker, sizeof last_marker, "%.*s", (int)r.len, buf);
			fprintf(ix, "%8" PRIu64 " ==== MARKER %s\n", r.seq, last_marker);
			break;
		case KBT_SNAP_BEGIN:
			if (*(uint32_t *)buf == 2 && dump_mem && last_sub >= 0) { /* after-event: write raw regions later at SNAP_END */ }
			break;
		case KBT_SNAP_END:
			if (*(uint32_t *)buf == 2 && last_sub >= 0) {
				for (unsigned j = 0; j < njits; j++) {	/* what the kernel wrote at gpu_alloc_addr */
					uint64_t v = 0;
					if (!rd(jits[j].addr, &v, 8)) {
						if (!jits[j].printed) { fprintf(ix, "%8" PRIu64 " JITADDR id %u at 0x%" PRIx64 ": not in a captured region\n", r.seq, jits[j].id, jits[j].addr); jits[j].printed = 1; }
						continue;
					}
					if (!jits[j].printed || v != jits[j].last_val)
						fprintf(ix, "%8" PRIu64 " JITADDR id %u *0x%" PRIx64 " = 0x%" PRIx64 "\n", r.seq, jits[j].id, jits[j].addr, v);
					jits[j].printed = 1; jits[j].last_val = v;
				}
			}
			if (*(uint32_t *)buf == 2 && post_needed && !post_done && last_sub >= 0) {
				post_done = 1;
				for (unsigned k = 0; k < nlast; k++) {
					if (last[k].core_req & 0x200 || !last[k].jc) continue;
					uint32_t hd[8] = { 0 };
					if (!rd(last[k].jc, hd, 32)) { fprintf(ix, "%8" PRIu64 " POST atom %u jc 0x%" PRIx64 ": header not captured\n", r.seq, last[k].nr, last[k].jc); continue; }
					uint64_t fp = hd[2] | (uint64_t)hd[3] << 32;
					fprintf(ix, "%8" PRIu64 " POST atom %u jc 0x%" PRIx64 " exception_status 0x%x first_incomplete 0x%x fault_ptr 0x%" PRIx64 " ctrl 0x%08x next 0x%08x%08x",
						r.seq, last[k].nr, last[k].jc, hd[0], hd[1], fp, hd[4], hd[7], hd[6]);
					uint8_t fb[64];
					if (fp && rd(fp & ~63ull, fb, 64)) { fprintf(ix, " @0x%" PRIx64 ": ", fp & ~63ull); hex(ix, fb, 64); }
					else if (fp) fprintf(ix, " (fault_ptr not in a captured region)");
					fprintf(ix, "\n");
				}
				snprintf(fn, sizeof fn, "%s/submit-%04d-post.txt", argv[2], last_sub);
				fprintf(ix, "%8" PRIu64 " POST decode of submit #%d after its fault event -> %s\n", r.seq, last_sub, fn);
				if (pdecode(fn, gpu_id)) return 1;
			}
			if (*(uint32_t *)buf == 2 && dump_mem && last_sub >= 0) {
				snprintf(fn, sizeof fn, "%s/mem-%04d", argv[2], last_sub); mkdir(fn, 0755);
				for (int i = 0; i < nr; i++) {
					snprintf(fn, sizeof fn, "%s/mem-%04d/%010" PRIx64 ".bin", argv[2], last_sub, R[i].gpu);
					FILE *f = fopen(fn, "wb"); fwrite(R[i].d, 1, R[i].len, f); fclose(f);
				}
			}
			break;
		case KBT_SUBMIT: {
			struct kbt_submit *s = (void *)buf;
			uint8_t *a = buf + sizeof *s;
			int jco = s->stride == 64 ? 8 : 0;   /* base_jd_atom has seq_nr first; base_jd_atom_v2 (56) does not */
			fprintf(ix, "%8" PRIu64 " SUBMIT #%d (%u atoms, stride %u) after marker '%s'\n", r.seq, nsub, s->nr, s->stride, last_marker);
			snprintf(fn, sizeof fn, "%s/submit-%04d.txt", argv[2], nsub);
			nlast = 0; njits = 0; post_needed = 0; post_done = 0;
			for (unsigned k = 0; k < s->nr && nlast < 256; k++) {
				uint8_t *at = a + k * s->stride;
				uint64_t jc; memcpy(&jc, at + jco, 8);
				uint32_t core_req; memcpy(&core_req, at + jco + 44, 4);
				uint8_t atom_nr = at[jco + 40], dep0 = at[jco + 36], dep1 = at[jco + 38];
				fprintf(ix, "           atom %u jc 0x%" PRIx64 " core_req 0x%x deps %u,%u\n", atom_nr, jc, core_req, dep0, dep1);
				last[nlast++] = (struct atm){ jc, core_req, atom_nr };
			}
			if (pdecode(fn, gpu_id)) return 1;
			last_sub = nsub++;
			break; }
		case KBT_SOFT: {	/* soft-job payload: JIT alloc = base_jit_alloc_info[nr_extres] (48 bytes each), JIT free = u8 ids */
			struct kbt_soft *h = (void *)buf;
			uint8_t *pl = buf + sizeof *h; unsigned pn = r.len - sizeof *h;
			fprintf(ix, "%8" PRIu64 " SOFT atom %u core_req 0x%x jc 0x%" PRIx64 " nr_extres %u payload %u bytes\n", r.seq, h->atom_nr, h->core_req, h->jc, h->nr_extres, pn);
			if ((h->core_req & 0xff) == 0x09) {
				for (unsigned j = 0; j < (h->nr_extres ? h->nr_extres : 1u) && (j + 1) * 48 <= pn; j++) {
					uint64_t q[6]; memcpy(q, pl + j * 48, 48);
					uint8_t *b = pl + j * 48 + 32;
					uint16_t usage; memcpy(&usage, b + 6, 2);
					fprintf(ix, "           JIT_ALLOC id %u bin %u max_alloc %u flags 0x%x usage %u gpu_alloc_addr 0x%" PRIx64 " va_pages 0x%" PRIx64 " commit_pages 0x%" PRIx64 " extension 0x%" PRIx64 " heap_info 0x%" PRIx64 "\n",
						b[0], b[1], b[2], b[3], usage, q[0], q[1], q[2], q[3], q[5]);
					if (njits < 256) jits[njits++] = (struct jitreq){ q[0], 0, b[0], 0 };
				}
			} else if ((h->core_req & 0xff) == 0x0a && pn) {
				fprintf(ix, "           JIT_FREE ids");
				for (unsigned j = 0; j < (h->nr_extres ? h->nr_extres : 1u) && j < pn; j++) fprintf(ix, " %u", pl[j]);
				fprintf(ix, "\n");
			}
			break; }
		case KBT_EVENT: {
			for (unsigned o = 0; o + 24 <= r.len; o += 24) {
				uint32_t code; memcpy(&code, buf + o, 4);
				if (code != 1) post_needed = 1;
				fprintf(ix, "%8" PRIu64 " event code 0x%x atom %u\n", r.seq, code, buf[o + 4]);
			}
			break; }
		case KBT_GPUPROPS:
			fprintf(ix, "%8" PRIu64 " gpuprops %u bytes\n", r.seq, r.len);
			snprintf(fn, sizeof fn, "%s/gpuprops.bin", argv[2]);
			{ FILE *f = fopen(fn, "wb"); fwrite(buf, 1, r.len, f); fclose(f); }
			break;
		case KBT_CLOSE: fprintf(ix, "%8" PRIu64 " close\n", r.seq); break;
		}
	}
	fclose(ix);
	fprintf(stdout, "%d submits decoded\n", nsub);
	return 0;
}
