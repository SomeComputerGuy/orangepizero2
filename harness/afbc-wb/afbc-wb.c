// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * afbc-wb: bit-exact check of the cedrus AFBC capture through the DE33.
 *
 * The H616 Mali-G31 has no AFBC (job 51), so the AFBC frames cedrus writes
 * are checked on the display engine instead: each decoded frame is shown 1:1
 * on the DE33 VI plane (the FBD decompresses AFBC there) and the composed
 * output is captured with the DE33 writeback connector. The same frames are
 * then decoded into the linear format (NV12/P010) and captured the same way.
 * The plane setup (plane, source rect, 1:1, colour encoding/range, primary
 * off, background) is identical in both passes; only the framebuffer differs.
 *
 *   afbc-wb -i STREAM -f NV12|P010 --save DIR   linear pass: captures -> DIR
 *   afbc-wb -i STREAM -f AS12|AS01 --ref DIR    AFBC pass: compare with DIR
 *
 * Per frame: one blocking plane commit, then two writeback captures (poison
 * 0x5a / 0xa5 before each) that must be identical (repeat check; also proves
 * every pixel was written). The linear pass can check every decoded frame
 * against the source md5s (--src-md5, lossless synthetic streams). The AFBC
 * pass compares each capture with the linear one: all pixels, and with
 * --tile T --band B only the pixels at least B px away from a T x T chroma
 * tile edge ("interior"; the DE33 scaler uses another chroma phase for AFBC
 * than for linear 4:2:0, see sun8i_vi_scaler_setup(), so pixels next to a
 * chroma edge may legitimately differ). FBD_CTL (DE+0x105000) is read after
 * each plane commit: enabled in the AFBC pass, disabled in the linear pass.
 *
 * Every result is a "RESULT ..." line. Exit 0 = ran (the job script judges
 * the RESULT lines), 1 = a pass check failed (see "RESULT verdict"),
 * 2 = setup error, 3 = mode not offered (NOT TESTED).
 *
 * Build: harness/afbc-wb/build.sh (static FFmpeg as afbc-kms-play, dynamic
 * libdrm/libc).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>
#include <linux/dma-buf.h>
#include <linux/sync_file.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_drm.h>
#include <libavutil/md5.h>
#include <libavutil/pixdesc.h>

#ifndef DRM_CLIENT_CAP_WRITEBACK_CONNECTORS
#define DRM_CLIENT_CAP_WRITEBACK_CONNECTORS 5
#endif
#ifndef DRM_MODE_CONNECTOR_WRITEBACK
#define DRM_MODE_CONNECTOR_WRITEBACK 18
#endif

#define MAX_FB		64
#define FENCE_TIMEOUT_MS 2000
#define FBD_PHYS	0x01105000UL	/* DE33 channel 0 FBD (sun50i_afbc.c: ch*0x20000 + 0x5000) */
#define AFBC_MOD	DRM_FORMAT_MOD_ARM_AFBC(AFBC_FORMAT_MOD_BLOCK_SIZE_16x16 | \
					AFBC_FORMAT_MOD_SPARSE | AFBC_FORMAT_MOD_SPLIT)
#define MAX_DUMPS	2

static struct {
	const char *input, *device, *connector, *pixfmt, *save, *ref, *src_md5, *dump;
	int mode_w, mode_h, mode_r;
	int frames, crop_x, crop_y, tile, band;
	uint32_t wb_fmt;
} o = {
	.device = "/dev/dri/card0",
	.connector = "HDMI-A-1",
	.mode_w = 1024, .mode_h = 768, .mode_r = 60,
	.frames = 24,
	.wb_fmt = DRM_FORMAT_XRGB2101010,
};

static double now_s(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* ------------------------------------------------------------ KMS */

struct kms {
	int fd;
	uint32_t conn_id, crtc_id, plane_id, primary_id, wb_id;
	int crtc_index;
	drmModeModeInfo mode;
	uint32_t mode_blob;
	uint32_t p_fb, p_crtc, p_sx, p_sy, p_sw, p_sh, p_cx, p_cy, p_cw, p_ch, p_enc, p_range;
	uint32_t pp_fb, pp_crtc;
	uint32_t c_mode, c_active, k_crtc, w_crtc, w_fb, w_fence;
	int64_t enc_709, range_lim;
	bool modeset_done;
};

static struct kms K;

static uint32_t prop_id(int fd, uint32_t obj, uint32_t type, const char *name)
{
	drmModeObjectProperties *props = drmModeObjectGetProperties(fd, obj, type);
	uint32_t id = 0;

	for (uint32_t i = 0; props && i < props->count_props && !id; i++) {
		drmModePropertyRes *p = drmModeGetProperty(fd, props->props[i]);

		if (p && !strcmp(p->name, name))
			id = p->prop_id;
		drmModeFreeProperty(p);
	}
	drmModeFreeObjectProperties(props);
	return id;
}

static uint64_t prop_value(int fd, uint32_t obj, uint32_t type, const char *name, bool *found)
{
	drmModeObjectProperties *props = drmModeObjectGetProperties(fd, obj, type);
	uint64_t v = 0;

	*found = false;
	for (uint32_t i = 0; props && i < props->count_props && !*found; i++) {
		drmModePropertyRes *p = drmModeGetProperty(fd, props->props[i]);

		if (p && !strcmp(p->name, name)) {
			v = props->prop_values[i];
			*found = true;
		}
		drmModeFreeProperty(p);
	}
	drmModeFreeObjectProperties(props);
	return v;
}

static int64_t prop_enum(int fd, uint32_t obj, uint32_t type, const char *name, const char *entry)
{
	drmModeObjectProperties *props = drmModeObjectGetProperties(fd, obj, type);
	int64_t v = -1;

	for (uint32_t i = 0; props && i < props->count_props; i++) {
		drmModePropertyRes *p = drmModeGetProperty(fd, props->props[i]);

		if (p && !strcmp(p->name, name))
			for (int j = 0; j < p->count_enums; j++)
				if (!strcmp(p->enums[j].name, entry))
					v = p->enums[j].value;
		drmModeFreeProperty(p);
	}
	drmModeFreeObjectProperties(props);
	return v;
}

/* IN_FORMATS walk (the sysroot libdrm iterator mis-reports pairs, see afbc-kms-play) */
static bool plane_supports(int fd, uint32_t plane, uint32_t fmt, uint64_t mod)
{
	bool found, ok = false;
	uint64_t blob_id = prop_value(fd, plane, DRM_MODE_OBJECT_PLANE, "IN_FORMATS", &found);
	drmModePropertyBlobRes *blob;
	const struct drm_format_modifier_blob *h;
	const uint32_t *fmts;
	const struct drm_format_modifier *mods;

	if (!found || !blob_id || !(blob = drmModeGetPropertyBlob(fd, blob_id)))
		return false;
	h = blob->data;
	fmts = (const uint32_t *)((const char *)h + h->formats_offset);
	mods = (const void *)((const char *)h + h->modifiers_offset);
	for (uint32_t f = 0; f < h->count_formats && !ok; f++) {
		if (fmts[f] != fmt)
			continue;
		for (uint32_t m = 0; m < h->count_modifiers; m++)
			if (mods[m].modifier == mod && f >= mods[m].offset &&
			    f < mods[m].offset + 64 && (mods[m].formats >> (f - mods[m].offset) & 1))
				ok = true;
	}
	drmModeFreePropertyBlob(blob);
	return ok;
}

static bool wb_format_offered(int fd, uint32_t wb_id, uint32_t fmt)
{
	bool found, has = false;
	uint64_t blob_id = prop_value(fd, wb_id, DRM_MODE_OBJECT_CONNECTOR,
				      "WRITEBACK_PIXEL_FORMATS", &found);
	drmModePropertyBlobRes *blob;

	if (!found || !blob_id || !(blob = drmModeGetPropertyBlob(fd, blob_id)))
		return false;
	printf("RESULT wb_formats");
	for (uint32_t i = 0; i < blob->length / 4; i++) {
		uint32_t f = ((uint32_t *)blob->data)[i];

		printf(" %.4s", (char *)&f);
		has |= f == fmt;
	}
	printf("\n");
	drmModeFreePropertyBlob(blob);
	return has;
}

static int kms_init(struct kms *k)
{
	drmModeRes *res;
	drmModeConnector *conn = NULL;
	drmModePlaneRes *pr;
	int ret = 2;

	k->fd = open(o.device, O_RDWR | O_CLOEXEC);
	if (k->fd < 0) {
		perror(o.device);
		return 2;
	}
	if (drmSetClientCap(k->fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) ||
	    drmSetClientCap(k->fd, DRM_CLIENT_CAP_ATOMIC, 1) ||
	    drmSetClientCap(k->fd, DRM_CLIENT_CAP_WRITEBACK_CONNECTORS, 1)) {
		fprintf(stderr, "atomic/writeback client caps not available\n");
		return 2;
	}
	res = drmModeGetResources(k->fd);
	if (!res)
		return 2;
	for (int i = 0; i < res->count_connectors; i++) {
		drmModeConnector *c = drmModeGetConnector(k->fd, res->connectors[i]);
		char name[64];

		if (!c)
			continue;
		snprintf(name, sizeof(name), "%s-%u", drmModeGetConnectorTypeName(c->connector_type),
			 c->connector_type_id);
		if (c->connector_type == DRM_MODE_CONNECTOR_WRITEBACK && !k->wb_id)
			k->wb_id = c->connector_id;
		if (!k->conn_id && !strcmp(name, o.connector)) {
			k->conn_id = c->connector_id;
			conn = c;
			continue;
		}
		drmModeFreeConnector(c);
	}
	printf("RESULT writeback_connector %u\n", k->wb_id);
	if (!k->wb_id || !conn) {
		fprintf(stderr, "no writeback connector or no %s\n", o.connector);
		goto out;
	}
	for (int i = 0; i < conn->count_modes; i++) {
		drmModeModeInfo *m = &conn->modes[i];

		if (m->hdisplay == o.mode_w && m->vdisplay == o.mode_h &&
		    (!o.mode_r || (int)m->vrefresh == o.mode_r)) {
			k->mode = *m;
			break;
		}
	}
	if (k->mode.hdisplay != o.mode_w) {
		fprintf(stderr, "mode %dx%d@%d not offered (force the connector on)\n",
			o.mode_w, o.mode_h, o.mode_r);
		printf("RESULT mode_unavailable 1\n");
		ret = 3;
		goto out;
	}
	printf("RESULT mode %s total %ux%u clock %d\n", k->mode.name, k->mode.htotal,
	       k->mode.vtotal, k->mode.clock);
	for (int e = 0; e < conn->count_encoders && !k->crtc_id; e++) {
		drmModeEncoder *enc = drmModeGetEncoder(k->fd, conn->encoders[e]);

		for (int c = 0; enc && c < res->count_crtcs; c++)
			if (enc->possible_crtcs & (1u << c)) {
				k->crtc_id = res->crtcs[c];
				k->crtc_index = c;
				break;
			}
		drmModeFreeEncoder(enc);
	}
	if (!k->crtc_id)
		goto out;

	/* the plane: the first one on this CRTC that takes 10-bit AFBC; both passes use it */
	pr = drmModeGetPlaneResources(k->fd);
	for (uint32_t i = 0; pr && i < pr->count_planes; i++) {
		drmModePlane *p = drmModeGetPlane(k->fd, pr->planes[i]);
		bool found;

		if (p && (p->possible_crtcs & (1u << k->crtc_index))) {
			if (prop_value(k->fd, p->plane_id, DRM_MODE_OBJECT_PLANE, "type", &found) ==
			    DRM_PLANE_TYPE_PRIMARY && !k->primary_id)
				k->primary_id = p->plane_id;
			if (!k->plane_id && plane_supports(k->fd, p->plane_id, DRM_FORMAT_YUV420_10BIT,
							   AFBC_MOD))
				k->plane_id = p->plane_id;
		}
		drmModeFreePlane(p);
	}
	drmModeFreePlaneResources(pr);
	if (!k->plane_id) {
		fprintf(stderr, "no plane on crtc %u takes YU10/AFBC\n", k->crtc_id);
		printf("RESULT afbc_plane 0\n");
		goto out;
	}
	printf("RESULT crtc %u plane %u primary %u afbc8 %d afbc10 %d nv12 %d p010 %d\n",
	       k->crtc_id, k->plane_id, k->primary_id,
	       plane_supports(k->fd, k->plane_id, DRM_FORMAT_YUV420_8BIT, AFBC_MOD),
	       plane_supports(k->fd, k->plane_id, DRM_FORMAT_YUV420_10BIT, AFBC_MOD),
	       plane_supports(k->fd, k->plane_id, DRM_FORMAT_NV12, DRM_FORMAT_MOD_LINEAR),
	       plane_supports(k->fd, k->plane_id, DRM_FORMAT_P010, DRM_FORMAT_MOD_LINEAR));
#define P(f, n) k->f = prop_id(k->fd, k->plane_id, DRM_MODE_OBJECT_PLANE, n)
	P(p_fb, "FB_ID"); P(p_crtc, "CRTC_ID");
	P(p_sx, "SRC_X"); P(p_sy, "SRC_Y"); P(p_sw, "SRC_W"); P(p_sh, "SRC_H");
	P(p_cx, "CRTC_X"); P(p_cy, "CRTC_Y"); P(p_cw, "CRTC_W"); P(p_ch, "CRTC_H");
	P(p_enc, "COLOR_ENCODING"); P(p_range, "COLOR_RANGE");
#undef P
	k->enc_709 = prop_enum(k->fd, k->plane_id, DRM_MODE_OBJECT_PLANE, "COLOR_ENCODING",
			       "ITU-R BT.709 YCbCr");
	k->range_lim = prop_enum(k->fd, k->plane_id, DRM_MODE_OBJECT_PLANE, "COLOR_RANGE",
				 "YCbCr limited range");
	if (k->primary_id && k->primary_id != k->plane_id) {
		k->pp_fb = prop_id(k->fd, k->primary_id, DRM_MODE_OBJECT_PLANE, "FB_ID");
		k->pp_crtc = prop_id(k->fd, k->primary_id, DRM_MODE_OBJECT_PLANE, "CRTC_ID");
	}
	k->c_mode = prop_id(k->fd, k->crtc_id, DRM_MODE_OBJECT_CRTC, "MODE_ID");
	k->c_active = prop_id(k->fd, k->crtc_id, DRM_MODE_OBJECT_CRTC, "ACTIVE");
	k->k_crtc = prop_id(k->fd, k->conn_id, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID");
	k->w_crtc = prop_id(k->fd, k->wb_id, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID");
	k->w_fb = prop_id(k->fd, k->wb_id, DRM_MODE_OBJECT_CONNECTOR, "WRITEBACK_FB_ID");
	k->w_fence = prop_id(k->fd, k->wb_id, DRM_MODE_OBJECT_CONNECTOR, "WRITEBACK_OUT_FENCE_PTR");
	if (!k->w_crtc || !k->w_fb || !k->w_fence)
		goto out;
	if (!wb_format_offered(k->fd, k->wb_id, o.wb_fmt)) {
		fprintf(stderr, "writeback format %.4s not offered\n", (char *)&o.wb_fmt);
		printf("RESULT wb_format_offered 0\n");
		goto out;
	}
	if (drmModeCreatePropertyBlob(k->fd, &k->mode, sizeof(k->mode), &k->mode_blob))
		goto out;
	ret = 0;
out:
	drmModeFreeConnector(conn);
	drmModeFreeResources(res);
	return ret;
}

struct dumb {
	uint32_t handle, fb_id, pitch;
	uint64_t size;
	uint8_t *map;
};

static int dumb_create(struct kms *k, struct dumb *b, uint32_t fmt, int w, int h)
{
	struct drm_mode_create_dumb c = { .width = w, .height = h, .bpp = 32 };
	struct drm_mode_map_dumb m = { 0 };
	uint32_t handles[4] = { 0 }, pitches[4] = { 0 }, offsets[4] = { 0 };

	if (drmIoctl(k->fd, DRM_IOCTL_MODE_CREATE_DUMB, &c))
		return -1;
	b->handle = handles[0] = c.handle;
	b->pitch = pitches[0] = c.pitch;
	b->size = c.size;
	if (drmModeAddFB2(k->fd, w, h, fmt, handles, pitches, offsets, &b->fb_id, 0))
		return -1;
	m.handle = c.handle;
	if (drmIoctl(k->fd, DRM_IOCTL_MODE_MAP_DUMB, &m))
		return -1;
	b->map = mmap(NULL, c.size, PROT_READ | PROT_WRITE, MAP_SHARED, k->fd, m.offset);
	return b->map == MAP_FAILED ? -1 : 0;
}

static int fence_wait(int fd, int timeout_ms)
{
	struct pollfd pfd = { .fd = fd, .events = POLLIN };
	struct sync_file_info info = { 0 };

	if (poll(&pfd, 1, timeout_ms) <= 0)
		return -ETIMEDOUT;
	if (ioctl(fd, SYNC_IOC_FILE_INFO, &info) == 0 && info.status < 0)
		return info.status;
	return 0;
}

/*
 * blocking commit of @fb_id on the plane (first call: modeset, primary off, wb attached); the source window
 * starts at @sx,@sy in the framebuffer
 */
static int commit_plane(struct kms *k, uint32_t fb_id, unsigned int sx, unsigned int sy)
{
	drmModeAtomicReq *req = drmModeAtomicAlloc();
	uint32_t flags = 0, w = k->mode.hdisplay, h = k->mode.vdisplay;
	int ret;

	drmModeAtomicAddProperty(req, k->plane_id, k->p_fb, fb_id);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_crtc, k->crtc_id);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_sx, (uint64_t)sx << 16);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_sy, (uint64_t)sy << 16);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_sw, (uint64_t)w << 16);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_sh, (uint64_t)h << 16);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_cx, 0);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_cy, 0);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_cw, w);
	drmModeAtomicAddProperty(req, k->plane_id, k->p_ch, h);
	if (k->p_enc && k->enc_709 >= 0)
		drmModeAtomicAddProperty(req, k->plane_id, k->p_enc, k->enc_709);
	if (k->p_range && k->range_lim >= 0)
		drmModeAtomicAddProperty(req, k->plane_id, k->p_range, k->range_lim);
	if (!k->modeset_done) {
		if (k->pp_fb) {
			drmModeAtomicAddProperty(req, k->primary_id, k->pp_fb, 0);
			drmModeAtomicAddProperty(req, k->primary_id, k->pp_crtc, 0);
		}
		drmModeAtomicAddProperty(req, k->crtc_id, k->c_mode, k->mode_blob);
		drmModeAtomicAddProperty(req, k->crtc_id, k->c_active, 1);
		drmModeAtomicAddProperty(req, k->conn_id, k->k_crtc, k->crtc_id);
		/* attach the writeback connector in the modeset (job 30: later = -EINVAL) */
		drmModeAtomicAddProperty(req, k->wb_id, k->w_crtc, k->crtc_id);
		flags |= DRM_MODE_ATOMIC_ALLOW_MODESET;
	}
	ret = drmModeAtomicCommit(k->fd, req, flags, NULL);
	if (ret)
		printf("RESULT plane_commit_error %d %s\n", errno, k->modeset_done ? "flip" : "modeset");
	else
		k->modeset_done = true;
	drmModeAtomicFree(req);
	return ret;
}

/* one writeback capture of the current frame into @cap; 0 = fence signalled ok */
static int capture(struct kms *k, struct dumb *cap, uint8_t poison, double *ms)
{
	drmModeAtomicReq *req = drmModeAtomicAlloc();
	int32_t fence = -1;
	double t0 = now_s();
	int ret;

	memset(cap->map, poison, cap->size);
	drmModeAtomicAddProperty(req, k->wb_id, k->w_crtc, k->crtc_id);
	drmModeAtomicAddProperty(req, k->wb_id, k->w_fb, cap->fb_id);
	drmModeAtomicAddProperty(req, k->wb_id, k->w_fence, (uint64_t)(uintptr_t)&fence);
	ret = drmModeAtomicCommit(k->fd, req, 0, NULL);
	drmModeAtomicFree(req);
	if (ret) {
		printf("RESULT wb_commit_error %d\n", errno);
		return -1000;
	}
	if (fence < 0)
		return -1;
	ret = fence_wait(fence, FENCE_TIMEOUT_MS);
	close(fence);
	*ms = (now_s() - t0) * 1e3;
	return ret;
}

/* ------------------------------------------------------------ FBD register */

static volatile uint32_t *fbd;

static int64_t fbd_ctl(void)
{
	if (!fbd) {
		int fd = open("/dev/mem", O_RDONLY | O_SYNC | O_CLOEXEC);
		void *p = fd < 0 ? MAP_FAILED : mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, FBD_PHYS);

		if (fd >= 0)
			close(fd);
		if (p == MAP_FAILED)
			return -1;
		fbd = p;
	}
	return fbd[0];
}

/* ------------------------------------------------------------ framebuffers */

struct fbinfo {
	ino_t ino;
	uint32_t fb_id;
};

static struct fbinfo fbs[MAX_FB];
static int nfbs;

static uint32_t fb_for_desc(struct kms *k, const AVDRMFrameDescriptor *d, int w, int h)
{
	uint32_t handles[4] = { 0 }, pitches[4] = { 0 }, offsets[4] = { 0 }, handle, fb_id;
	uint64_t mods[4] = { 0 };
	const AVDRMLayerDescriptor *l = &d->layers[0];
	struct stat st;

	if (fstat(d->objects[0].fd, &st))
		return 0;
	for (int i = 0; i < nfbs; i++)
		if (fbs[i].ino == st.st_ino)
			return fbs[i].fb_id;
	if (nfbs == MAX_FB || drmPrimeFDToHandle(k->fd, d->objects[0].fd, &handle))
		return 0;
	for (int i = 0; i < l->nb_planes; i++) {
		handles[i] = handle;
		pitches[i] = l->planes[i].pitch;
		offsets[i] = l->planes[i].offset;
		mods[i] = d->objects[0].format_modifier;
	}
	if (drmModeAddFB2WithModifiers(k->fd, w, h, l->format, handles, pitches, offsets, mods,
				       &fb_id, DRM_MODE_FB_MODIFIERS)) {
		printf("RESULT addfb_error %d %.4s 0x%016" PRIx64 " pitch %u size %zu\n", errno,
		       (char *)&l->format, mods[0], pitches[0], d->objects[0].size);
		return 0;
	}
	fbs[nfbs++] = (struct fbinfo){ st.st_ino, fb_id };
	printf("RESULT fb %u format %.4s modifier 0x%016" PRIx64 " planes %d pitch %u size %zu %dx%d\n",
	       fb_id, (char *)&l->format, mods[0], l->nb_planes, pitches[0], d->objects[0].size, w, h);
	return fb_id;
}

/* md5 of a linear NV12/P010 frame in the packed layout of mkstreams.py (Y rows, CbCr rows) */
static int linear_md5(const AVDRMFrameDescriptor *d, int w, int h, char out[33])
{
	const AVDRMLayerDescriptor *l = &d->layers[0];
	int bps = l->format == DRM_FORMAT_P010 ? 2 : 1, fd = d->objects[0].fd;
	struct dma_buf_sync s = { DMA_BUF_SYNC_START | DMA_BUF_SYNC_READ };
	uint8_t *map, dig[16];
	struct AVMD5 *md5;

	if (l->nb_planes != 2)
		return -1;
	map = mmap(NULL, d->objects[0].size, PROT_READ, MAP_SHARED, fd, 0);
	if (map == MAP_FAILED)
		return -1;
	ioctl(fd, DMA_BUF_IOCTL_SYNC, &s);
	md5 = av_md5_alloc();
	av_md5_init(md5);
	for (int y = 0; y < h; y++)
		av_md5_update(md5, map + l->planes[0].offset + (size_t)y * l->planes[0].pitch, w * bps);
	for (int y = 0; y < h / 2; y++)
		av_md5_update(md5, map + l->planes[1].offset + (size_t)y * l->planes[1].pitch, w * bps);
	av_md5_final(md5, dig);
	av_free(md5);
	s.flags = DMA_BUF_SYNC_END | DMA_BUF_SYNC_READ;
	ioctl(fd, DMA_BUF_IOCTL_SYNC, &s);
	munmap(map, d->objects[0].size);
	for (int i = 0; i < 16; i++)
		sprintf(out + 2 * i, "%02x", dig[i]);
	return 0;
}

/* ------------------------------------------------------------ compare */

static void md5_hex(const uint32_t *p, size_t n, char out[33])
{
	uint8_t dig[16];

	av_md5_sum(dig, (const uint8_t *)p, n * 4);
	for (int i = 0; i < 16; i++)
		sprintf(out + 2 * i, "%02x", dig[i]);
}

/* copy the (write-combined) capture into @dst, packed, X bits cleared */
static void readback(const struct dumb *cap, uint32_t *dst, int w, int h, uint32_t mask)
{
	for (int y = 0; y < h; y++) {
		memcpy(dst + (size_t)y * w, cap->map + (size_t)y * cap->pitch, (size_t)w * 4);
		for (int x = 0; x < w; x++)
			dst[(size_t)y * w + x] &= mask;
	}
}

struct cmp {
	long mism, mism_int, pixels_int;
	int max_dev, max_dev_int, first_x, first_y, first_int_x, first_int_y;
	uint32_t first_a, first_b;
	long dist[33];		/* mismatches by distance to the nearest tile edge (tile mode) */
};

static int edge_dist(int x, int y)
{
	int t = o.tile, dx = x % t, dy = y % t;

	dx = dx < t - 1 - dx ? dx : t - 1 - dx;
	dy = dy < t - 1 - dy ? dy : t - 1 - dy;
	return dx < dy ? dx : dy;
}

static void compare(const uint32_t *a, const uint32_t *b, int w, int h, int bits, struct cmp *r)
{
	uint32_t cm = (1u << bits) - 1;

	memset(r, 0, sizeof(*r));
	r->first_x = r->first_y = r->first_int_x = r->first_int_y = -1;
	for (int y = 0; y < h; y++)
		for (int x = 0; x < w; x++) {
			uint32_t pa = a[(size_t)y * w + x], pb = b[(size_t)y * w + x];
			int d = o.tile ? edge_dist(x, y) : 0, dev = 0;
			bool interior = o.tile && d >= o.band;

			r->pixels_int += interior;
			if (pa == pb)
				continue;
			for (int c = 0; c < 3; c++) {
				int da = (pa >> (c * bits)) & cm, db = (pb >> (c * bits)) & cm;
				int dd = da > db ? da - db : db - da;

				dev = dd > dev ? dd : dev;
			}
			if (!r->mism++) {
				r->first_x = x; r->first_y = y; r->first_a = pa; r->first_b = pb;
			}
			r->max_dev = dev > r->max_dev ? dev : r->max_dev;
			if (o.tile)
				r->dist[d > 32 ? 32 : d]++;
			if (interior) {
				if (!r->mism_int++) {
					r->first_int_x = x; r->first_int_y = y;
				}
				r->max_dev_int = dev > r->max_dev_int ? dev : r->max_dev_int;
			}
		}
}

static void save_raw(const char *dir, const char *name, const uint32_t *p, size_t n)
{
	char path[512];
	FILE *f;

	snprintf(path, sizeof(path), "%s/%s", dir, name);
	f = fopen(path, "wb");
	if (!f || fwrite(p, 4, n, f) != n)
		printf("RESULT save_error %s %d\n", path, errno);
	if (f)
		fclose(f);
}

static int load_raw(const char *dir, const char *name, uint32_t *p, size_t n)
{
	char path[512];
	FILE *f;
	size_t got;

	snprintf(path, sizeof(path), "%s/%s", dir, name);
	f = fopen(path, "rb");
	if (!f)
		return -1;
	got = fread(p, 4, n, f);
	fclose(f);
	return got == n ? 0 : -1;
}

/* ------------------------------------------------------------ decoder */

static enum AVPixelFormat get_format(AVCodecContext *c, const enum AVPixelFormat *f)
{
	for (; *f != AV_PIX_FMT_NONE; f++)
		if (*f == AV_PIX_FMT_DRM_PRIME)
			return *f;
	return AV_PIX_FMT_NONE;
}

static char (*src_md5)[33];
static int n_src_md5;

static void load_src_md5(void)
{
	FILE *f = fopen(o.src_md5, "r");
	int i;
	char m[64];

	if (!f) {
		printf("RESULT src_md5_missing %s\n", o.src_md5);
		return;
	}
	src_md5 = calloc(4096, sizeof(*src_md5));
	while (n_src_md5 < 4096 && fscanf(f, "%d %63s", &i, m) == 2)
		if (i == n_src_md5 && strlen(m) == 32)
			strcpy(src_md5[n_src_md5++], m);
	fclose(f);
}

static void usage(void)
{
	fprintf(stderr,
		"usage: afbc-wb -i STREAM -f AS01|AS12|P010|NV12 (--save DIR | --ref DIR) [options]\n"
		"  -n N            frames (24)\n"
		"  -m WxH@R        mode (1024x768@60), shown 1:1: the plane source is a WxH window\n"
		"  --crop X,Y      source window offset (0,0)\n"
		"  -w XR30|XR24    writeback format (XR30)\n"
		"  --src-md5 FILE  linear pass: per-frame source md5s (mkstreams.py layout)\n"
		"  --tile T --band B  AFBC pass: also compare pixels >= B px from a T x T tile edge\n"
		"  -o DIR          AFBC pass: dump the first %d mismatching capture pairs\n"
		"  -c CONN         display connector (HDMI-A-1)\n", MAX_DUMPS);
}

int main(int argc, char **argv)
{
	static const struct option lo[] = {
		{ "save", 1, 0, 'S' }, { "ref", 1, 0, 'R' }, { "src-md5", 1, 0, 'M' },
		{ "crop", 1, 0, 'C' }, { "tile", 1, 0, 'T' }, { "band", 1, 0, 'B' }, { 0 }
	};
	AVFormatContext *fmt = NULL;
	AVCodecContext *ctx;
	AVBufferRef *hw = NULL;
	const AVCodec *codec;
	AVPacket *pkt;
	AVFrame *f;
	struct dumb cap;
	uint32_t *c1, *c2, *ref, mask;
	int c, ret, stream, w, h, bits, frame = 0, dumps = 0;
	size_t pic_x = 0, pic_y = 0;
	bool afbc, flushing = false;
	long repeat_bad = 0, src_bad = 0, src_ok = 0, wb_err = 0, fmt_bad = 0, fbd_bad = 0;
	long exact = 0, int_exact = 0, compared = 0, ref_missing = 0, mism_sum = 0, mism_int_sum = 0;
	long dist_sum[33] = { 0 };
	int max_dev = 0, max_dev_int = 0;
	double ms_sum = 0;

	while ((c = getopt_long(argc, argv, "i:f:n:m:w:o:c:h", lo, NULL)) != -1) {
		switch (c) {
		case 'i': o.input = optarg; break;
		case 'f': o.pixfmt = optarg; break;
		case 'n': o.frames = atoi(optarg); break;
		case 'm': sscanf(optarg, "%dx%d@%d", &o.mode_w, &o.mode_h, &o.mode_r); break;
		case 'w': o.wb_fmt = !strcmp(optarg, "XR24") ? DRM_FORMAT_XRGB8888 :
				     DRM_FORMAT_XRGB2101010; break;
		case 'o': o.dump = optarg; break;
		case 'c': o.connector = optarg; break;
		case 'S': o.save = optarg; break;
		case 'R': o.ref = optarg; break;
		case 'M': o.src_md5 = optarg; break;
		case 'C': sscanf(optarg, "%d,%d", &o.crop_x, &o.crop_y); break;
		case 'T': o.tile = atoi(optarg); break;
		case 'B': o.band = atoi(optarg); break;
		default: usage(); return 2;
		}
	}
	if (!o.input || !o.pixfmt || strlen(o.pixfmt) != 4 || !o.save == !o.ref) {
		usage();
		return 2;
	}
	afbc = !strncmp(o.pixfmt, "AS", 2);
	if (afbc != !!o.ref) {
		fprintf(stderr, "AFBC formats compare (--ref), linear formats save (--save)\n");
		return 2;
	}
	bits = o.wb_fmt == DRM_FORMAT_XRGB8888 ? 8 : 10;
	mask = bits == 8 ? 0x00ffffff : 0x3fffffff;
	if (o.src_md5)
		load_src_md5();

	ret = kms_init(&K);
	if (ret)
		return ret;
	w = K.mode.hdisplay;
	h = K.mode.vdisplay;
	if (dumb_create(&K, &cap, o.wb_fmt, w, h)) {
		printf("RESULT capture_buffer_error %d\n", errno);
		return 2;
	}
	c1 = malloc((size_t)w * h * 4);
	c2 = malloc((size_t)w * h * 4);
	ref = malloc((size_t)w * h * 4);

	setenv("V4L2REQUEST_PIXFMT", o.pixfmt, 1);
	if (avformat_open_input(&fmt, o.input, NULL, NULL) < 0 ||
	    avformat_find_stream_info(fmt, NULL) < 0) {
		fprintf(stderr, "cannot open %s\n", o.input);
		return 2;
	}
	stream = av_find_best_stream(fmt, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
	if (stream < 0)
		return 2;
	ctx = avcodec_alloc_context3(codec);
	avcodec_parameters_to_context(ctx, fmt->streams[stream]->codecpar);
	if (av_hwdevice_ctx_create(&hw, AV_HWDEVICE_TYPE_V4L2REQUEST, NULL, NULL, 0) < 0) {
		fprintf(stderr, "no v4l2request device\n");
		return 2;
	}
	ctx->hw_device_ctx = av_buffer_ref(hw);
	ctx->get_format = get_format;
	ctx->extra_hw_frames = 4;
	if (avcodec_open2(ctx, codec, NULL) < 0)
		return 2;
	printf("RESULT stream %s %s %dx%d %s pixfmt %s wb %.4s crop %d,%d tile %d band %d\n",
	       o.input, codec->name, ctx->width, ctx->height, av_get_pix_fmt_name(ctx->sw_pix_fmt),
	       o.pixfmt, (char *)&o.wb_fmt, o.crop_x, o.crop_y, o.tile, o.band);
	if (ctx->width < o.crop_x + w || ctx->height < o.crop_y + h) {
		fprintf(stderr, "stream smaller than the %dx%d window at %d,%d\n", w, h, o.crop_x, o.crop_y);
		return 2;
	}

	pkt = av_packet_alloc();
	f = av_frame_alloc();
	while (frame < o.frames) {
		const AVDRMFrameDescriptor *d;
		uint64_t mod;
		uint32_t fb_id;
		int64_t ctl;
		double ms1 = 0, ms2 = 0;
		int r1, r2;
		char m1[33], m2[33], name[64];

		ret = avcodec_receive_frame(ctx, f);
		if (ret == AVERROR(EAGAIN) && !flushing) {
			if (av_read_frame(fmt, pkt) < 0) {
				avcodec_send_packet(ctx, NULL);
				flushing = true;
			} else {
				if (pkt->stream_index == stream)
					avcodec_send_packet(ctx, pkt);
				av_packet_unref(pkt);
			}
			continue;
		}
		if (ret < 0) {
			printf("RESULT decode_end %s at %d\n", av_err2str(ret), frame);
			break;
		}
		d = (const AVDRMFrameDescriptor *)f->data[0];
		mod = d->objects[0].format_modifier;
		if (afbc != ((mod >> 56) == DRM_FORMAT_MOD_VENDOR_ARM)) {
			printf("RESULT frame %d wrong_buffer_kind modifier 0x%016" PRIx64 " format %.4s\n",
			       frame, mod, (char *)&d->layers[0].format);
			fmt_bad++;
		}
		if (o.src_md5 && !afbc) {
			char lm[33];

			if (linear_md5(d, f->width, f->height, lm))
				printf("RESULT frame %d src_md5 unreadable\n", frame);
			else if (frame < n_src_md5 && !strcmp(lm, src_md5[frame]))
				src_ok++;
			else {
				src_bad++;
				printf("RESULT frame %d src_md5_mismatch got %s want %s\n", frame, lm,
				       frame < n_src_md5 ? src_md5[frame] : "-");
			}
		}
		/*
		 * The picture may start at an offset in the buffer (FFmpeg crop_left/crop_top from the V4L2 compose
		 * rectangle: 4 lines for Cedrus H.265 AFBC); the framebuffer covers the whole surface.
		 */
		if (!frame || f->crop_left != pic_x || f->crop_top != pic_y)
			printf("RESULT frame %d pic_offset %u,%u fb %dx%d\n", frame, (unsigned int)f->crop_left,
			       (unsigned int)f->crop_top, f->width, f->height);
		pic_x = f->crop_left;
		pic_y = f->crop_top;
		fb_id = fb_for_desc(&K, d, f->width, f->height);
		if (!fb_id || commit_plane(&K, fb_id, o.crop_x + pic_x, o.crop_y + pic_y)) {
			av_frame_unref(f);
			printf("RESULT verdict setup_error at frame %d\n", frame);
			return 2;
		}
		if (!frame)
			usleep(100000);	/* first frame after the modeset: let the pipe settle */
		ctl = fbd_ctl();
		if (ctl >= 0 && (afbc != (ctl & 1)))
			fbd_bad++;
		r1 = capture(&K, &cap, 0x5a, &ms1);
		if (!r1)
			readback(&cap, c1, w, h, mask);
		r2 = capture(&K, &cap, 0xa5, &ms2);
		if (!r2)
			readback(&cap, c2, w, h, mask);
		av_frame_unref(f);
		if (r1 || r2) {
			printf("RESULT frame %d wb_error %d %d\n", frame, r1, r2);
			wb_err++;
			frame++;
			continue;
		}
		ms_sum += ms1 + ms2;
		md5_hex(c1, (size_t)w * h, m1);
		md5_hex(c2, (size_t)w * h, m2);
		if (strcmp(m1, m2))
			repeat_bad++;
		if (ctl >= 0)
			snprintf(name, sizeof(name), "0x%08" PRIx64, (uint64_t)ctl);
		else
			snprintf(name, sizeof(name), "unreadable");
		printf("RESULT frame %d cap_md5 %s repeat %s fbd_ctl %s fence_ms %.1f %.1f\n",
		       frame, m1, strcmp(m1, m2) ? "DIFFER" : "same", name, ms1, ms2);
		snprintf(name, sizeof(name), "f%03d.cap", frame);
		if (o.save) {
			save_raw(o.save, name, c1, (size_t)w * h);
		} else if (load_raw(o.ref, name, ref, (size_t)w * h)) {
			printf("RESULT frame %d ref_missing\n", frame);
			ref_missing++;
		} else {
			struct cmp r;

			compare(ref, c1, w, h, bits, &r);
			compared++;
			exact += !r.mism;
			int_exact += o.tile && !r.mism_int;
			mism_sum += r.mism;
			mism_int_sum += r.mism_int;
			max_dev = r.max_dev > max_dev ? r.max_dev : max_dev;
			max_dev_int = r.max_dev_int > max_dev_int ? r.max_dev_int : max_dev_int;
			for (int i = 0; i <= 32; i++)
				dist_sum[i] += r.dist[i];
			printf("RESULT frame %d vs_linear mismatches %ld max_dev %d", frame, r.mism, r.max_dev);
			if (o.tile)
				printf(" interior_pixels %ld interior_mismatches %ld interior_max_dev %d",
				       r.pixels_int, r.mism_int, r.max_dev_int);
			if (r.mism)
				printf(" first %d,%d linear %08x afbc %08x", r.first_x, r.first_y,
				       r.first_a, r.first_b);
			if (r.mism_int)
				printf(" first_interior %d,%d", r.first_int_x, r.first_int_y);
			printf("\n");
			if (r.mism && o.dump && dumps < MAX_DUMPS) {
				char n2[64];

				dumps++;
				snprintf(n2, sizeof(n2), "f%03d.linear.cap", frame);
				save_raw(o.dump, n2, ref, (size_t)w * h);
				snprintf(n2, sizeof(n2), "f%03d.afbc.cap", frame);
				save_raw(o.dump, n2, c1, (size_t)w * h);
				printf("RESULT dump %s/f%03d.{linear,afbc}.cap %.4s %dx%d packed\n", o.dump,
				       frame, (char *)&o.wb_fmt, w, h);
			}
		}
		frame++;
	}

	printf("RESULT summary pass %s frames %d wb_errors %ld repeat_differ %ld wrong_buffer_kind %ld fbd_state_wrong %ld fbd_readable %d fence_ms_mean %.1f\n",
	       afbc ? "afbc" : "linear", frame, wb_err, repeat_bad, fmt_bad, fbd_bad, fbd != NULL,
	       frame ? ms_sum / (2.0 * frame) : 0);
	if (o.src_md5 && !afbc)
		printf("RESULT src_md5 ok %ld mismatch %ld of %d\n", src_ok, src_bad, frame);
	if (afbc) {
		printf("RESULT compare frames %ld exact %ld mismatches %ld max_dev %d ref_missing %ld\n",
		       compared, exact, mism_sum, max_dev, ref_missing);
		if (o.tile) {
			printf("RESULT interior frames %ld exact %ld mismatches %ld max_dev %d\n",
			       compared, int_exact, mism_int_sum, max_dev_int);
			printf("RESULT edge_dist_hist");
			for (int i = 0; i <= 32; i++)
				printf(" %ld", dist_sum[i]);
			printf("\n");
		}
	}
	ret = frame != o.frames || wb_err || repeat_bad || fmt_bad || fbd_bad ||
	      (o.src_md5 && !afbc && src_bad) || (afbc && (ref_missing || compared != frame));
	printf("RESULT verdict %s\n", ret ? "pass_checks_failed" : "pass_ok");
	return ret ? 1 : 0;
}
