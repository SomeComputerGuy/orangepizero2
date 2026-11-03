/*
 * xviddec: reference MPEG-4 Part 2 decode with xvidcore (host only).
 * Usage: xviddec <in.m4v> > out.yuv   (raw MPEG-4 elementary stream in, I420 frames out, display order)
 * Build: gcc -O2 -o xviddec xviddec.c -I$P/include $P/lib/libxvidcore.a -lm -lpthread
 *        (P = kernel-check/xvidcore-build/prefix: xvidcore 1.3.7, --disable-assembly)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <xvid.h>

int main(int argc, char **argv)
{
	FILE *f = argc > 1 ? fopen(argv[1], "rb") : NULL;
	if (!f) { fprintf(stderr, "usage: %s in.m4v > out.yuv\n", argv[0]); return 1; }
	fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
	unsigned char *bs = malloc(len + 64); memset(bs + len, 0, 64);
	if (fread(bs, 1, len, f) != (size_t)len) return 1;
	fclose(f);

	xvid_gbl_init_t gi = { .version = XVID_VERSION, .cpu_flags = XVID_CPU_FORCE }; /* plain C paths */
	xvid_global(NULL, XVID_GBL_INIT, &gi, NULL);
	xvid_dec_create_t dc = { .version = XVID_VERSION };
	if (xvid_decore(NULL, XVID_DEC_CREATE, &dc, NULL) < 0) { fprintf(stderr, "create failed\n"); return 1; }

	int w = 0, h = 0, frames = 0; unsigned char *img = NULL; long pos = 0;
	for (int flush = 0; flush < 2; ) {
		xvid_dec_frame_t fr = { .version = XVID_VERSION };
		xvid_dec_stats_t st = { .version = XVID_VERSION };
		if (pos < len) { fr.bitstream = bs + pos; fr.length = len - pos; }
		else { fr.bitstream = NULL; fr.length = -1; flush++; }
		if (img) {
			fr.output.csp = XVID_CSP_I420; fr.output.plane[0] = img; fr.output.stride[0] = w;
		} else fr.output.csp = XVID_CSP_NULL;
		int used = xvid_decore(dc.handle, XVID_DEC_DECODE, &fr, &st);
		if (st.type == XVID_TYPE_VOL) {
			w = st.data.vol.width; h = st.data.vol.height;
			free(img); img = malloc((size_t)w * h * 3 / 2);
			fprintf(stderr, "VOL %dx%d\n", w, h);
		} else if (st.type > 0 && img) {
			fwrite(img, 1, (size_t)w * h * 3 / 2, stdout); frames++;
		}
		if (pos < len) {
			if (used <= 0) { if (++pos >= len) continue; } else pos += used;
		} else if (st.type <= 0) break;
	}
	fprintf(stderr, "frames %d\n", frames);
	xvid_decore(dc.handle, XVID_DEC_DESTROY, NULL, NULL);
	return 0;
}
