// SPDX-License-Identifier: MIT
/*
 * blobopt: LD_PRELOAD that turns on boolean options of the Arm libmali g24p0 blob (libmali-bifrost-g31-g24p0,
 * md5 dd143e98d3e0850e74ecd422731ce5e6) that the release build no longer reads from mali_*.config.
 *
 * Why (item 8, 2026-11-06): this G31 has no AFBC (AFBC_FEATURES 0x10001) but the blob writes AFBC render targets,
 * so every AFBC fragment job faults (DATA_INVALID). The blob has GLES_DISABLE_SURFACE_AFBC (option 140) and
 * GLES_DISABLE_TEXTURE_AFBC (141), but in this release build their registry entries are "disabled": the
 * entry's enabled() hook returns 0 and its parse() hook is the presence-only stub (0x1a90bc0), so the value is
 * zero whatever the config file says (job 66: "parsed 2 variables", still AFBC). No GPU property changes the
 * choice either (host simulation, hostsim/). The option registry is in writable .data: each entry is
 * {name, type, default(), enabled(), parse(ctx, entry, slot), index}. blobopt points enabled() and parse() of
 * the requested bool options at its own functions (enabled = 1, parse = write the value, return 3 = "set"), so the
 * blob's own option machinery stores the value and the blob takes its own non-AFBC path. No blob code is changed.
 *
 * Env: BLOBOPT="NAME=0|1,..." (names as in the blob, e.g. GLES_DISABLE_SURFACE_AFBC=1). One stderr line per option
 *      ("blobopt: NAME = v (entry i)"), or "blobopt: ..." errors; nothing happens when BLOBOPT is unset.
 */
#define _GNU_SOURCE
#include <link.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TABLE 0x3585d88ul	/* first registry entry (libmali g24p0) */
#define NENT 180
#define STUB 0x1a90bc0ul	/* presence-only parse() of the disabled options */

struct entry { const char *name; uint64_t type; void *def, *enabled, *parse; uint64_t index; };

static uint8_t want[NENT];	/* value + 1 per entry, 0 = untouched */
static struct entry *tab;

static int enabled_on(void *ctx) { (void)ctx; return 1; }
static int parse_forced(void *ctx, struct entry *e, uint8_t *slot)
{
	(void)ctx;
	slot[0] = want[e - tab] - 1;
	if (getenv("BLOBOPT_DEBUG")) fprintf(stderr, "blobopt: parse %s slot %p\n", e->name, (void *)slot);
	return 3;
}

static int find_mali(struct dl_phdr_info *i, size_t sz, void *d)
{
	(void)sz;
	if (i->dlpi_name && strstr(i->dlpi_name, "libmali")) { *(uintptr_t *)d = i->dlpi_addr; return 1; }
	return 0;
}

__attribute__((constructor)) static void blobopt_ctor(void)
{
	const char *s = getenv("BLOBOPT");
	if (!s || !*s) return;
	uintptr_t base = 0;
	dl_iterate_phdr(find_mali, &base);
	if (!base) { fputs("blobopt: libmali not loaded\n", stderr); return; }
	tab = (struct entry *)(base + TABLE);
	/* guard: this layout is for g24p0 only; check the first and the AFBC entries */
	if (strcmp(tab[0].name, "GLES_FILTER")) {
		fprintf(stderr, "blobopt: registry not at +0x%lx (other blob build?), nothing changed\n", TABLE);
		return;
	}
	char buf[1024];
	snprintf(buf, sizeof buf, "%s", s);
	for (char *tok = strtok(buf, ","); tok; tok = strtok(NULL, ",")) {
		char *eq = strchr(tok, '=');
		if (!eq) continue;
		*eq = 0;
		int v = atoi(eq + 1), hit = 0;
		for (int i = 0; i < NENT; i++) {
			if (strcmp(tab[i].name, tok)) continue;
			hit = 1;
			if (tab[i].type != 1) { fprintf(stderr, "blobopt: %s is not a bool (type %lu)\n", tok, (unsigned long)tab[i].type); break; }
			if ((uintptr_t)tab[i].parse != base + STUB)
				fprintf(stderr, "blobopt: note: %s parse() is not the release stub\n", tok);
			want[i] = (v ? 1 : 0) + 1;
			tab[i].enabled = (void *)enabled_on;
			tab[i].parse = (void *)parse_forced;
			fprintf(stderr, "blobopt: %s = %d (entry %d, index %lu)\n", tok, v ? 1 : 0, i, (unsigned long)tab[i].index);
			break;
		}
		if (!hit) fprintf(stderr, "blobopt: no option %s\n", tok);
	}
}
