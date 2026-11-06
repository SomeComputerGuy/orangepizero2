/*
 * kms-wb: mechanical check of the H616 DE33 writeback connector.
 *
 * Shows a known framebuffer on a CRTC, commits DRM writeback jobs that
 * capture the composed frame into memory and compares the capture with
 * what was shown. Three commands:
 *
 *   probe          list the connectors and the writeback formats
 *   solid RRGGBB   show a solid colour, capture it, compare pixel by pixel
 *   bars           show 8 colour bars, capture, compare
 *   flips N        page-flip between two solid colours N times with a
 *                  capture per flip; a captured frame holding rows of both
 *                  colours is a torn frame
 *   tear N         N page flips, a different full-screen picture every frame,
 *                  a capture of every frame; each capture must hold exactly
 *                  the picture of its own commit (cmd_tear())
 *   selftest       the tear classifier on synthetic captures
 *   memload S T MB DRAM/CPU load for the tear runs
 *
 * Every result is one "RESULT <key> <value>" line on stdout. Exit 0 = the
 * command's checks passed, 1 = a check failed, 2 = usage/setup error,
 * 3 = the mode is not offered (NOT TESTED).
 *
 * libdrm only (no FFmpeg), built by build.sh against the board sysroot.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
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
#include <linux/sync_file.h>

#ifndef DRM_CLIENT_CAP_WRITEBACK_CONNECTORS
#define DRM_CLIENT_CAP_WRITEBACK_CONNECTORS 5
#endif
#ifndef DRM_MODE_CONNECTOR_WRITEBACK
#define DRM_MODE_CONNECTOR_WRITEBACK 18
#endif

#define RING		6	/* flips capture buffers */
#define CHECK_STEP	32	/* flips: every 32nd pixel of a row (+ the last) */
#define FENCE_TIMEOUT_MS 2000

static struct {
	const char *device;
	const char *connector;
	const char *dump_dir;
	int mode_w, mode_h, mode_r;
	uint32_t wb_fmt;
	int commit_delay_us;
	int tolerance;
	int repeat;
} o = {
	.device = "/dev/dri/card0",
	.connector = "HDMI-A-1",
	.wb_fmt = DRM_FORMAT_XRGB8888,
	.tolerance = 3,
	.repeat = 3,
};

static volatile sig_atomic_t quit;
static int commit_errno;	/* errno of the last failed atomic commit */

static double now_s(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* ------------------------------------------------------------ KMS state */

struct kms {
	int fd;
	uint32_t conn_id, crtc_id, plane_id, wb_id;
	int crtc_index;
	drmModeModeInfo mode;
	uint32_t mode_blob;
	uint32_t p_fb, p_crtc, p_sx, p_sy, p_sw, p_sh, p_cx, p_cy, p_cw, p_ch;
	uint32_t c_mode, c_active, k_crtc;
	uint32_t w_crtc, w_fb, w_fence, w_formats;
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

static uint64_t prop_value(int fd, uint32_t obj, uint32_t type, const char *name,
			   bool *found)
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

static void conn_name(drmModeConnector *c, char *buf, size_t n)
{
	snprintf(buf, n, "%s-%u", drmModeGetConnectorTypeName(c->connector_type) ?
		 drmModeGetConnectorTypeName(c->connector_type) : "Unknown",
		 c->connector_type_id);
}

static bool wb_format_offered(int fd, uint32_t wb_id, uint32_t blob_prop, uint32_t fmt,
			      bool print)
{
	bool found;
	uint64_t blob_id = prop_value(fd, wb_id, DRM_MODE_OBJECT_CONNECTOR,
				      "WRITEBACK_PIXEL_FORMATS", &found);
	drmModePropertyBlobRes *blob;
	bool has = false;

	(void)blob_prop;
	if (!found || !blob_id)
		return false;
	blob = drmModeGetPropertyBlob(fd, blob_id);
	if (!blob)
		return false;
	if (print)
		printf("RESULT wb_formats");
	for (uint32_t i = 0; i < blob->length / 4; i++) {
		uint32_t f = ((uint32_t *)blob->data)[i];

		if (print)
			printf(" %.4s", (char *)&f);
		if (f == fmt)
			has = true;
	}
	if (print)
		printf("\n");
	drmModeFreePropertyBlob(blob);
	return has;
}

/* Returns 0, 2 (setup error) or 3 (mode not offered). */
static int kms_init(struct kms *k, bool probe)
{
	drmModeRes *res;
	drmModeConnector *conn = NULL;
	drmModePlaneRes *pr;
	int ret = 2, n_wb = 0;

	k->fd = open(o.device, O_RDWR | O_CLOEXEC);
	if (k->fd < 0) {
		perror(o.device);
		return 2;
	}
	if (drmSetClientCap(k->fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) ||
	    drmSetClientCap(k->fd, DRM_CLIENT_CAP_ATOMIC, 1)) {
		fprintf(stderr, "atomic KMS not available\n");
		return 2;
	}
	if (drmSetClientCap(k->fd, DRM_CLIENT_CAP_WRITEBACK_CONNECTORS, 1)) {
		fprintf(stderr, "writeback connector cap not available\n");
		printf("RESULT writeback_cap 0\n");
		return 2;
	}
	printf("RESULT writeback_cap 1\n");

	res = drmModeGetResources(k->fd);
	if (!res)
		return 2;

	for (int i = 0; i < res->count_connectors; i++) {
		drmModeConnector *c = drmModeGetConnector(k->fd, res->connectors[i]);
		char name[64];

		if (!c)
			continue;
		conn_name(c, name, sizeof(name));
		if (probe)
			printf("RESULT connector %s id=%u type=%u status=%d modes=%d encoders=%d\n",
			       name, c->connector_id, c->connector_type,
			       c->connection, c->count_modes, c->count_encoders);
		if (c->connector_type == DRM_MODE_CONNECTOR_WRITEBACK) {
			n_wb++;
			if (!k->wb_id)
				k->wb_id = c->connector_id;
		}
		if (!k->conn_id && !strcmp(name, o.connector)) {
			k->conn_id = c->connector_id;
			conn = c;
			continue;
		}
		drmModeFreeConnector(c);
	}
	printf("RESULT writeback_connectors %d\n", n_wb);
	if (!k->wb_id) {
		fprintf(stderr, "no writeback connector\n");
		goto out;
	}
	if (!conn) {
		fprintf(stderr, "connector %s not found\n", o.connector);
		goto out;
	}
	if (!conn->count_modes) {
		fprintf(stderr, "connector %s offers no mode (force it on: echo on > status)\n",
			o.connector);
		printf("RESULT mode_unavailable 1\n");
		ret = 3;
		goto out;
	}

	k->mode = conn->modes[0];
	for (int i = 0; i < conn->count_modes; i++) {
		drmModeModeInfo *m = &conn->modes[i];

		if (o.mode_w && (m->hdisplay != o.mode_w || m->vdisplay != o.mode_h ||
				 (o.mode_r && (int)m->vrefresh != o.mode_r)))
			continue;
		if (!o.mode_w && !(m->type & DRM_MODE_TYPE_PREFERRED))
			continue;
		k->mode = *m;
		break;
	}
	if (o.mode_w && (k->mode.hdisplay != o.mode_w || k->mode.vdisplay != o.mode_h)) {
		fprintf(stderr, "mode %dx%d@%d not offered\n", o.mode_w, o.mode_h, o.mode_r);
		printf("RESULT mode_unavailable 1\n");
		ret = 3;
		goto out;
	}
	printf("RESULT mode %s %ux%u total %ux%u clock %d\n", k->mode.name,
	       k->mode.hdisplay, k->mode.vdisplay, k->mode.htotal, k->mode.vtotal,
	       k->mode.clock);

	/* CRTC reachable from the display connector's encoders */
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
	if (!k->crtc_id) {
		fprintf(stderr, "no CRTC for %s\n", o.connector);
		goto out;
	}

	/* the writeback connector must reach the same CRTC */
	{
		drmModeConnector *wc = drmModeGetConnector(k->fd, k->wb_id);
		bool ok = false;

		for (int e = 0; wc && e < wc->count_encoders; e++) {
			drmModeEncoder *enc = drmModeGetEncoder(k->fd, wc->encoders[e]);

			if (enc) {
				printf("RESULT wb_encoder id=%u possible_crtcs=0x%x possible_clones=0x%x\n",
				       enc->encoder_id, enc->possible_crtcs,
				       enc->possible_clones);
				if (enc->possible_crtcs & (1u << k->crtc_index))
					ok = true;
			}
			drmModeFreeEncoder(enc);
		}
		drmModeFreeConnector(wc);
		printf("RESULT wb_reaches_crtc %d\n", ok);
		if (!ok)
			goto out;
	}

	pr = drmModeGetPlaneResources(k->fd);
	for (uint32_t i = 0; pr && i < pr->count_planes && !k->plane_id; i++) {
		drmModePlane *p = drmModeGetPlane(k->fd, pr->planes[i]);
		bool found;

		if (p && (p->possible_crtcs & (1u << k->crtc_index)) &&
		    prop_value(k->fd, p->plane_id, DRM_MODE_OBJECT_PLANE, "type", &found) ==
		    DRM_PLANE_TYPE_PRIMARY)
			k->plane_id = p->plane_id;
		drmModeFreePlane(p);
	}
	drmModeFreePlaneResources(pr);
	if (!k->plane_id) {
		fprintf(stderr, "no primary plane on crtc %u\n", k->crtc_id);
		goto out;
	}
	printf("RESULT crtc %u plane %u wb_connector %u\n", k->crtc_id, k->plane_id, k->wb_id);

#define P(f, n) k->f = prop_id(k->fd, k->plane_id, DRM_MODE_OBJECT_PLANE, n)
	P(p_fb, "FB_ID"); P(p_crtc, "CRTC_ID");
	P(p_sx, "SRC_X"); P(p_sy, "SRC_Y"); P(p_sw, "SRC_W"); P(p_sh, "SRC_H");
	P(p_cx, "CRTC_X"); P(p_cy, "CRTC_Y"); P(p_cw, "CRTC_W"); P(p_ch, "CRTC_H");
#undef P
	k->c_mode = prop_id(k->fd, k->crtc_id, DRM_MODE_OBJECT_CRTC, "MODE_ID");
	k->c_active = prop_id(k->fd, k->crtc_id, DRM_MODE_OBJECT_CRTC, "ACTIVE");
	k->k_crtc = prop_id(k->fd, k->conn_id, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID");
	k->w_crtc = prop_id(k->fd, k->wb_id, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID");
	k->w_fb = prop_id(k->fd, k->wb_id, DRM_MODE_OBJECT_CONNECTOR, "WRITEBACK_FB_ID");
	k->w_fence = prop_id(k->fd, k->wb_id, DRM_MODE_OBJECT_CONNECTOR,
			     "WRITEBACK_OUT_FENCE_PTR");
	printf("RESULT wb_props crtc=%u fb=%u fence=%u\n", k->w_crtc, k->w_fb, k->w_fence);
	if (!k->w_crtc || !k->w_fb || !k->w_fence)
		goto out;
	if (!wb_format_offered(k->fd, k->wb_id, 0, o.wb_fmt, true)) {
		fprintf(stderr, "writeback format %.4s not offered\n", (char *)&o.wb_fmt);
		printf("RESULT wb_format_offered 0\n");
		goto out;
	}
	printf("RESULT wb_format_offered 1\n");
	if (drmModeCreatePropertyBlob(k->fd, &k->mode, sizeof(k->mode), &k->mode_blob))
		goto out;
	ret = 0;
out:
	drmModeFreeConnector(conn);
	drmModeFreeResources(res);
	return ret;
}

/* ---------------------------------------------------------- buffers */

struct dumb {
	uint32_t handle, fb_id, pitch, fmt;
	uint64_t size;
	int w, h;
	uint8_t *map;
};

static int dumb_create(struct kms *k, struct dumb *b, uint32_t fmt, int w, int h)
{
	struct drm_mode_create_dumb c = { .width = w, .bpp = 32, .height = h };
	struct drm_mode_map_dumb m = { 0 };
	uint32_t handles[4] = { 0 }, pitches[4] = { 0 }, offsets[4] = { 0 };

	if (fmt == DRM_FORMAT_NV12) {
		c.bpp = 8;
		c.height = h * 3 / 2;
	}
	if (drmIoctl(k->fd, DRM_IOCTL_MODE_CREATE_DUMB, &c))
		return -1;
	b->handle = c.handle;
	b->pitch = c.pitch;
	b->size = c.size;
	b->fmt = fmt;
	b->w = w;
	b->h = h;
	handles[0] = c.handle;
	pitches[0] = c.pitch;
	if (fmt == DRM_FORMAT_NV12) {
		handles[1] = c.handle;
		pitches[1] = c.pitch;
		offsets[1] = c.pitch * h;
	}
	if (drmModeAddFB2(k->fd, w, h, fmt, handles, pitches, offsets, &b->fb_id, 0))
		return -1;
	m.handle = c.handle;
	if (drmIoctl(k->fd, DRM_IOCTL_MODE_MAP_DUMB, &m))
		return -1;
	b->map = mmap(NULL, c.size, PROT_READ | PROT_WRITE, MAP_SHARED, k->fd, m.offset);
	return b->map == MAP_FAILED ? -1 : 0;
}

static const uint32_t bar_rgb[8] = {
	0xbfbfbf, 0xbfbf00, 0x00bfbf, 0x00bf00,
	0xbf00bf, 0xbf0000, 0x0000bf, 0x101010,
};

/* what the source framebuffer holds at (x, y) */
static uint32_t src_pixel(bool bars, uint32_t solid, int x, int w)
{
	return bars ? bar_rgb[x * 8 / w] : solid;
}

static void fill_xr24(struct dumb *b, bool bars, uint32_t solid)
{
	for (int y = 0; y < b->h; y++) {
		uint32_t *row = (uint32_t *)(b->map + y * b->pitch);

		for (int x = 0; x < b->w; x++)
			row[x] = src_pixel(bars, solid, x, b->w);
	}
}

static void poison(struct dumb *b)
{
	memset(b->map, 0x5a, b->size);
}

/* -------------------------------------------------------- compare */

/* BT.601 limited range, what the DE33 CSC table produces */
static void rgb_to_yuv601(uint32_t rgb, int *y, int *u, int *v)
{
	double r = (rgb >> 16) & 0xff, g = (rgb >> 8) & 0xff, b = rgb & 0xff;

	*y = (int)(16 + (65.481 * r + 128.553 * g + 24.966 * b) / 255 + 0.5);
	*u = (int)(128 + (-37.797 * r - 74.203 * g + 112.0 * b) / 255 + 0.5);
	*v = (int)(128 + (112.0 * r - 93.786 * g - 18.214 * b) / 255 + 0.5);
}

struct cmp {
	long pixels, mismatches;
	int max_dev;
	int first_x, first_y;
	uint32_t first_expect, first_got;
};

/* capture @c against the source content (bars or solid), per format */
static void compare(struct dumb *c, bool bars, uint32_t solid, struct cmp *r)
{
	memset(r, 0, sizeof(*r));
	r->first_x = r->first_y = -1;

	if (c->fmt == DRM_FORMAT_XRGB8888 || c->fmt == DRM_FORMAT_XRGB2101010) {
		for (int y = 0; y < c->h; y++) {
			uint32_t *row = (uint32_t *)(c->map + y * c->pitch);

			for (int x = 0; x < c->w; x++) {
				uint32_t e = src_pixel(bars, solid, x, c->w), g = row[x];
				int dev = 0;

				r->pixels++;
				if (c->fmt == DRM_FORMAT_XRGB8888) {
					if ((g & 0xffffff) != e)
						dev = 1;
				} else {
					/* 10-bit: compare the top 8 bits of each component */
					int d;

					d = abs((int)((g >> 22) & 0xff) - (int)((e >> 16) & 0xff));
					dev = d > dev ? d : dev;
					d = abs((int)((g >> 12) & 0xff) - (int)((e >> 8) & 0xff));
					dev = d > dev ? d : dev;
					d = abs((int)((g >> 2) & 0xff) - (int)(e & 0xff));
					dev = d > dev ? d : dev;
					if (dev <= o.tolerance)
						dev = 0;
				}
				if (dev) {
					r->mismatches++;
					if (dev > r->max_dev)
						r->max_dev = dev;
					if (r->first_x < 0) {
						r->first_x = x;
						r->first_y = y;
						r->first_expect = e;
						r->first_got = g;
					}
				}
			}
		}
	} else if (c->fmt == DRM_FORMAT_NV12) {
		uint8_t *cb = c->map + c->pitch * c->h;

		for (int y = 0; y < c->h; y++)
			for (int x = 0; x < c->w; x++) {
				int ey, eu, ev, d, dev;
				uint32_t e = src_pixel(bars, solid, x, c->w);

				rgb_to_yuv601(e, &ey, &eu, &ev);
				r->pixels++;
				d = abs((int)c->map[y * c->pitch + x] - ey);
				dev = d;
				if (!(y & 1) && !(x & 1)) {
					uint8_t *p = cb + (y / 2) * c->pitch + (x & ~1);

					d = abs((int)p[0] - eu);
					dev = d > dev ? d : dev;
					d = abs((int)p[1] - ev);
					dev = d > dev ? d : dev;
				}
				if (dev > o.tolerance) {
					r->mismatches++;
					if (dev > r->max_dev)
						r->max_dev = dev;
					if (r->first_x < 0) {
						r->first_x = x;
						r->first_y = y;
						r->first_expect = (ey << 16) | (eu << 8) | ev;
						r->first_got = c->map[y * c->pitch + x];
					}
				}
			}
	}
}

static void dump(struct dumb *b, const char *name)
{
	char path[512];
	FILE *f;

	if (!o.dump_dir)
		return;
	snprintf(path, sizeof(path), "%s/%s.raw", o.dump_dir, name);
	f = fopen(path, "wb");
	if (!f)
		return;
	fwrite(b->map, 1, b->size, f);
	fclose(f);
	printf("RESULT dump %s %.4s %dx%d pitch %u\n", path, (char *)&b->fmt, b->w, b->h,
	       b->pitch);
}

/* -------------------------------------------------------- commits */

static int fence_wait(int fd, int timeout_ms, int *status)
{
	struct pollfd pfd = { .fd = fd, .events = POLLIN };
	struct sync_file_info info = { 0 };
	int ret = poll(&pfd, 1, timeout_ms);

	*status = 0;
	if (ret <= 0)
		return -ETIMEDOUT;
	if (ioctl(fd, SYNC_IOC_FILE_INFO, &info) == 0)
		*status = info.status;	/* 1 signaled, <0 error */
	else
		*status = 1;
	return 0;
}

/*
 * @event: the page-flip event's user data (non-NULL = nonblocking commit with
 * DRM_MODE_PAGE_FLIP_EVENT); drmHandleEvent() hands it to flip_handler(),
 * so it must point at the caller's struct flip_ev (job 40: NULL here made
 * flip_handler() write through a NULL pointer on the first flip event).
 */
static int commit(struct kms *k, uint32_t src_fb, struct dumb *cap, int32_t *fence_fd,
		  void *event)
{
	drmModeAtomicReq *req = drmModeAtomicAlloc();
	uint32_t flags = 0;
	int ret;

	drmModeAtomicAddProperty(req, k->plane_id, k->p_fb, src_fb);
	if (!k->modeset_done) {
		drmModeAtomicAddProperty(req, k->plane_id, k->p_crtc, k->crtc_id);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_sx, 0);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_sy, 0);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_sw,
					 (uint64_t)k->mode.hdisplay << 16);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_sh,
					 (uint64_t)k->mode.vdisplay << 16);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_cx, 0);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_cy, 0);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_cw, k->mode.hdisplay);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_ch, k->mode.vdisplay);
		drmModeAtomicAddProperty(req, k->crtc_id, k->c_mode, k->mode_blob);
		drmModeAtomicAddProperty(req, k->crtc_id, k->c_active, 1);
		drmModeAtomicAddProperty(req, k->conn_id, k->k_crtc, k->crtc_id);
		/*
		 * Attach the writeback connector here, in the modeset: adding a
		 * connector to a CRTC changes its connector set, which is a full
		 * modeset, so a later flip commit that attached it would fail
		 * with -EINVAL without ALLOW_MODESET (job 30). From here the
		 * writeback commits only set WRITEBACK_FB_ID and the fence.
		 */
		drmModeAtomicAddProperty(req, k->wb_id, k->w_crtc, k->crtc_id);
		flags |= DRM_MODE_ATOMIC_ALLOW_MODESET;
	}
	if (cap) {
		*fence_fd = -1;
		drmModeAtomicAddProperty(req, k->wb_id, k->w_crtc, k->crtc_id);
		drmModeAtomicAddProperty(req, k->wb_id, k->w_fb, cap->fb_id);
		drmModeAtomicAddProperty(req, k->wb_id, k->w_fence,
					 (uint64_t)(uintptr_t)fence_fd);
	}
	if (event)
		flags |= DRM_MODE_PAGE_FLIP_EVENT | DRM_MODE_ATOMIC_NONBLOCK;
	ret = drmModeAtomicCommit(k->fd, req, flags, event);
	if (ret)
		commit_errno = errno;
	if (ret)
		fprintf(stderr, "atomic commit (%s%s): %s\n",
			k->modeset_done ? "flip" : "modeset", cap ? " + writeback" : "",
			strerror(errno));
	else
		k->modeset_done = true;
	drmModeAtomicFree(req);
	return ret;
}

/*
 * one blocking capture of the current frame into @cap; 0 = fence signalled ok,
 * -1000 = the commit failed (errno in commit_errno), else a fence error
 */
static int capture_once(struct kms *k, uint32_t src_fb, struct dumb *cap, double *ms)
{
	int32_t fence = -1;
	int status, ret;
	double t0;

	poison(cap);
	t0 = now_s();
	if (commit(k, src_fb, cap, &fence, NULL))
		return -1000;
	if (fence < 0) {
		fprintf(stderr, "no out fence returned\n");
		return -1;
	}
	ret = fence_wait(fence, FENCE_TIMEOUT_MS, &status);
	*ms = (now_s() - t0) * 1e3;
	close(fence);
	if (ret) {
		fprintf(stderr, "writeback fence timed out\n");
		return -2;
	}
	if (status < 0) {
		fprintf(stderr, "writeback fence error %d\n", status);
		return status;
	}
	return 0;
}

/* -------------------------------------------------------- commands */

static int cmd_probe(void)
{
	int ret = kms_init(&K, true);

	printf("RESULT probe %s\n", ret == 0 ? "ok" : ret == 3 ? "mode_unavailable" : "fail");
	return ret;
}

/* solid or bars: static image, @o.repeat captures, every pixel must match */
static int cmd_static(bool bars, uint32_t solid)
{
	struct dumb src, cap;
	int ret = kms_init(&K, false), fails = 0;
	int w, h;

	if (ret)
		return ret;
	w = K.mode.hdisplay;
	h = K.mode.vdisplay;
	if (bars && o.wb_fmt != DRM_FORMAT_XRGB8888) {
		fprintf(stderr, "bars compare needs XR24 capture\n");
		return 2;
	}
	if (dumb_create(&K, &src, DRM_FORMAT_XRGB8888, w, h)) {
		perror("dumb buffer (source)");
		return 2;
	}
	if (dumb_create(&K, &cap, o.wb_fmt, w, h)) {
		printf("RESULT capture_buffer_error %d\n", errno);
		perror("dumb buffer (capture)");
		return 2;
	}
	fill_xr24(&src, bars, solid);

	/* show it first, without a job: the first capture is of a settled frame */
	if (commit(&K, src.fb_id, NULL, NULL, NULL)) {
		printf("RESULT modeset_commit_error %d\n", commit_errno);
		return 2;
	}
	usleep(50000);

	for (int i = 0; i < o.repeat && !quit; i++) {
		struct cmp r;
		double ms;
		char name[32];

		ret = capture_once(&K, src.fb_id, &cap, &ms);
		if (ret == -1000) {
			printf("RESULT capture %d commit_error %d\n", i, commit_errno);
			fails++;
			continue;
		}
		if (ret) {
			printf("RESULT capture %d fence_error %d\n", i, ret);
			fails++;
			continue;
		}
		compare(&cap, bars, solid, &r);
		printf("RESULT capture %d pixels %ld mismatches %ld max_dev %d first %d,%d expect %06x got %08x fence_ms %.1f\n",
		       i, r.pixels, r.mismatches, r.max_dev, r.first_x, r.first_y,
		       r.first_expect, r.first_got, ms);
		if (r.mismatches) {
			fails++;
			snprintf(name, sizeof(name), "%s-%06x-%d", bars ? "bars" : "solid",
				 solid, i);
			dump(&cap, name);
		}
	}
	printf("RESULT %s %06x %.4s captures %d failed %d\n", bars ? "bars" : "solid", solid,
	       (char *)&o.wb_fmt, o.repeat, fails);
	return fails ? 1 : 0;
}

/* classify a captured XR24 frame against the two flip colours */
/*
 * Row classification of a flips capture. The capture buffers are dumb
 * buffers, mapped write-combined (uncached) by the DMA GEM helpers: a CPU
 * read costs a DRAM round trip. Job 41 classified every pixel of every
 * 1024x768 capture (786432 uncached reads, ~120 ms per frame), which held
 * the flip loop to ~7 flips/s (seq_gaps 298 of 299) and hid what the
 * hardware does. @step > 1 reads only every step-th pixel of a row plus the
 * row's last pixel: a torn frame is still caught (whole rows of both
 * colours), as is an unwritten (poisoned) region. @step 1 = every pixel.
 */
static void classify(struct dumb *c, uint32_t a, uint32_t b, int step, int *rows_a,
		     int *rows_b, int *rows_other, int *boundary)
{
	int last = -1;

	*rows_a = *rows_b = *rows_other = 0;
	*boundary = -1;
	for (int y = 0; y < c->h; y++) {
		uint32_t *row = (uint32_t *)(c->map + y * c->pitch);
		int na = 0, nb = 0, nr = 0;

		for (int x = 0; x < c->w; x += step) {
			uint32_t p = row[x] & 0xffffff;

			nr++;
			if (p == a)
				na++;
			else if (p == b)
				nb++;
		}
		if (step > 1 && (c->w - 1) % step) {
			uint32_t p = row[c->w - 1] & 0xffffff;

			nr++;
			if (p == a)
				na++;
			else if (p == b)
				nb++;
		}
		if (na == nr) {
			(*rows_a)++;
			if (last == 1 && *boundary < 0)
				*boundary = y;
			last = 0;
		} else if (nb == nr) {
			(*rows_b)++;
			if (last == 0 && *boundary < 0)
				*boundary = y;
			last = 1;
		} else {
			(*rows_other)++;
			if (*boundary < 0)
				*boundary = y;
		}
	}
}

struct flip_ev {
	bool done;
	uint32_t seq;
	double t;
};

static void flip_handler(int fd, unsigned int seq, unsigned int sec, unsigned int usec,
			 unsigned int crtc, void *data)
{
	struct flip_ev *ev = data;

	if (!ev)	/* an event of a commit without user data: not ours */
		return;
	ev->done = true;
	ev->seq = seq;
	ev->t = sec + usec * 1e-6;
}

struct stat_ms {
	int n;
	double sum, max;
};

static void stat_add(struct stat_ms *s, double ms)
{
	s->n++;
	s->sum += ms;
	if (ms > s->max)
		s->max = ms;
}

static void stat_print(const char *key, const struct stat_ms *s)
{
	printf("RESULT %s mean_ms %.3f max_ms %.3f n %d\n", key,
	       s->n ? s->sum / s->n : 0.0, s->max, s->n);
}

/* sleep until CLOCK_MONOTONIC time @t (s); DRM event times are CLOCK_MONOTONIC */
static void sleep_until(double t)
{
	struct timespec ts = { .tv_sec = (time_t)t,
			       .tv_nsec = (long)((t - (time_t)t) * 1e9) };

	while (clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL) == EINTR && !quit)
		;
}

struct flips_ctx {
	struct dumb cap[RING];
	int32_t fence[RING];
	uint32_t col[2];
	int frames, pure[2], torn, bad, ferr, wrong, first_torn;
	struct stat_ms fence_wait, check;
};

/* wait for and classify the capture of flip @i (sampled rows) */
static void flips_check(struct flips_ctx *f, int i)
{
	int s = i % RING, status, ra, rb, ro, boundary;
	double t0 = now_s();

	if (fence_wait(f->fence[s], FENCE_TIMEOUT_MS, &status) || status < 0) {
		printf("RESULT flip %d fence_error status=%d\n", i, status);
		f->ferr++;
		goto out;
	}
	stat_add(&f->fence_wait, (now_s() - t0) * 1e3);
	t0 = now_s();
	classify(&f->cap[s], f->col[0], f->col[1], CHECK_STEP, &ra, &rb, &ro, &boundary);
	stat_add(&f->check, (now_s() - t0) * 1e3);
	f->frames++;
	if (ro) {
		f->bad++;
		printf("RESULT flip %d BAD rows_a %d rows_b %d rows_other %d first_bad_row %d\n",
		       i, ra, rb, ro, boundary);
		if (f->first_torn < 0)
			f->first_torn = i;
		if (f->bad <= 3) {
			char name[32];

			snprintf(name, sizeof(name), "bad-%d", i);
			dump(&f->cap[s], name);
		}
	} else if (ra && rb) {
		f->torn++;
		printf("RESULT flip %d TORN rows_a %d rows_b %d boundary_row %d\n",
		       i, ra, rb, boundary);
		if (f->first_torn < 0)
			f->first_torn = i;
		if (f->torn <= 3) {
			char name[32];

			snprintf(name, sizeof(name), "torn-%d", i);
			dump(&f->cap[s], name);
		}
	} else {
		/* the expected colour: flip i shows col[i & 1] */
		f->pure[rb ? 1 : 0]++;
		if ((rb ? 1 : 0) != (i & 1)) {
			printf("RESULT flip %d WRONG_FRAME got %c\n", i, rb ? 'b' : 'a');
			f->wrong++;
		}
	}
out:
	close(f->fence[s]);
	f->fence[s] = -1;
}

/*
 * N page flips between two solid colours, each with a writeback job into a
 * ring of capture buffers. Flip i is committed right after the flip event of
 * flip i-1 (or -D us after that event's timestamp); the capture of flip i-2,
 * complete since that same vblank, is then checked, and the buffer of flip
 * i+1 poisoned, while flip i waits for its vblank. So the client keeps up
 * with the display and the run measures the driver: one flip and one
 * capture per frame (the RT-WB finishes a capture by the next vblank, where
 * the driver starts the next one). After the run the last RING captures are
 * compared in full (every pixel).
 */
static int cmd_flips(int n)
{
	static struct flips_ctx f;
	struct dumb src[2];
	int ret = kms_init(&K, false);
	int w, h, gaps = 0, gap_max = 0, first_gap = -1, late = 0, full = 0, full_bad = 0;
	drmEventContext ev = { .version = 3, .page_flip_handler2 = flip_handler };
	struct flip_ev fe = { 0 };
	uint32_t last_seq = 0;
	double t_first = 0, t_last = 0, t_commit, phase_sum = 0, phase_max = 0;
	int phase_n = 0, phase_outside = 0;
	struct stat_ms ioctl_ms = { 0 }, poison_ms = { 0 };
	double vbl_ms, frame_ms;

	if (ret)
		return ret;
	f.col[0] = 0x40c0e0;
	f.col[1] = 0xe04020;
	f.first_torn = -1;
	vbl_ms = (K.mode.vtotal - K.mode.vdisplay) * (double)K.mode.htotal /
		 (K.mode.clock * 1e3) * 1e3;
	frame_ms = K.mode.vtotal * (double)K.mode.htotal / (K.mode.clock * 1e3) * 1e3;
	if (o.wb_fmt != DRM_FORMAT_XRGB8888) {
		fprintf(stderr, "flips needs XR24 capture\n");
		return 2;
	}
	w = K.mode.hdisplay;
	h = K.mode.vdisplay;
	for (int i = 0; i < 2; i++) {
		if (dumb_create(&K, &src[i], DRM_FORMAT_XRGB8888, w, h)) {
			perror("dumb buffer");
			return 2;
		}
		fill_xr24(&src[i], false, f.col[i]);
	}
	for (int i = 0; i < RING; i++) {
		if (dumb_create(&K, &f.cap[i], DRM_FORMAT_XRGB8888, w, h)) {
			perror("dumb buffer");
			return 2;
		}
		f.fence[i] = -1;
	}

	if (commit(&K, src[0].fb_id, NULL, NULL, NULL)) {
		printf("RESULT modeset_commit_error %d\n", commit_errno);
		return 2;
	}
	usleep(50000);
	poison(&f.cap[0]);

	for (int i = 0; i < n && !quit; i++) {
		int s = i % RING;
		double t0;

		if (i > 0) {
			/* the flip event of flip i-1 */
			while (!fe.done && !quit) {
				struct pollfd pfd = { .fd = K.fd, .events = POLLIN };

				if (poll(&pfd, 1, 1000) <= 0) {
					fprintf(stderr, "flip event timed out\n");
					quit = 1;
					break;
				}
				drmHandleEvent(K.fd, &ev);
			}
			if (!fe.done)
				break;
			if (!t_first)
				t_first = fe.t;
			if (last_seq && fe.seq - last_seq > 1) {
				gaps++;
				if ((int)(fe.seq - last_seq - 1) > gap_max)
					gap_max = fe.seq - last_seq - 1;
				if (first_gap < 0)
					first_gap = i - 1;
			}
			last_seq = fe.seq;
			t_last = fe.t;
			if (o.commit_delay_us)
				sleep_until(fe.t + o.commit_delay_us * 1e-6);
		}

		t_commit = now_s();
		fe.done = false;
		if (commit(&K, src[i & 1].fb_id, &f.cap[s], &f.fence[s], &fe)) {
			printf("RESULT flip %d commit_error %d\n", i, commit_errno);
			ret = 2;
			break;
		}
		stat_add(&ioctl_ms, (now_s() - t_commit) * 1e3);
		if (i > 0) {
			double ph = (t_commit - t_last) * 1e3;

			if (ph >= 0) {
				phase_n++;
				phase_sum += ph;
				if (ph > phase_max)
					phase_max = ph;
				if (ph > vbl_ms)
					phase_outside++;
				if (ph > frame_ms)
					late++;
			}
		}

		/* while flip i waits for its vblank */
		if (i >= 2)
			flips_check(&f, i - 2);
		if (i + 1 < n) {
			t0 = now_s();
			poison(&f.cap[(i + 1) % RING]);
			stat_add(&poison_ms, (now_s() - t0) * 1e3);
		}
	}

	/* the last flip's event, then the captures not checked yet */
	while (ret == 0 && !fe.done && !quit) {
		struct pollfd pfd = { .fd = K.fd, .events = POLLIN };

		if (poll(&pfd, 1, 1000) <= 0) {
			fprintf(stderr, "flip event timed out\n");
			break;
		}
		drmHandleEvent(K.fd, &ev);
	}
	if (fe.done) {
		if (last_seq && fe.seq - last_seq > 1) {
			gaps++;
			if ((int)(fe.seq - last_seq - 1) > gap_max)
				gap_max = fe.seq - last_seq - 1;
			if (first_gap < 0)
				first_gap = n - 1;
		}
		t_last = fe.t;
	}
	for (int i = n - 2 < 0 ? 0 : n - 2; i < n; i++)
		if (f.fence[i % RING] >= 0)
			flips_check(&f, i);

	/* the last RING captures, every pixel (their buffers were poisoned in full) */
	for (int i = n - RING < 0 ? 0 : n - RING; i < n && ret == 0 && !quit; i++) {
		int ra, rb, ro, boundary;

		classify(&f.cap[i % RING], f.col[0], f.col[1], 1, &ra, &rb, &ro, &boundary);
		full++;
		if (ro || (ra && rb) || (rb ? 1 : 0) != (i & 1)) {
			full_bad++;
			printf("RESULT flip %d FULL_MISMATCH rows_a %d rows_b %d rows_other %d first_row %d\n",
			       i, ra, rb, ro, boundary);
		}
	}

	printf("RESULT flips %d frames_captured %d frames_a %d frames_b %d frames_torn %d frames_bad %d fence_errors %d\n",
	       n, f.frames, f.pure[0], f.pure[1], f.torn, f.bad, f.ferr);
	printf("RESULT frames_wrong %d full_checked %d full_mismatch %d check_step %d\n",
	       f.wrong, full, full_bad, CHECK_STEP);
	printf("RESULT flip_rate %.3f seq_gaps %d\n",
	       t_last > t_first ? (n - 1) / (t_last - t_first) : 0.0, gaps);
	printf("RESULT seq_gap_max %d first_gap_flip %d commits_after_frame %d frame_ms %.3f\n",
	       gap_max, first_gap, late, frame_ms);
	if (phase_n)
		printf("RESULT commit_phase mean_ms %.3f max_ms %.3f outside_blanking %d of %d blanking_ms %.3f\n",
		       phase_sum / phase_n, phase_max, phase_outside, phase_n, vbl_ms);
	stat_print("commit_ioctl", &ioctl_ms);
	stat_print("fence_wait", &f.fence_wait);
	stat_print("check", &f.check);
	stat_print("poison", &poison_ms);
	if (f.first_torn >= 0)
		printf("RESULT first_torn_flip %d\n", f.first_torn);
	if (ret)
		return ret;
	return (f.torn || f.bad || f.ferr || f.wrong || full_bad || f.frames < n - 1) ? 1 : 0;
}

/* ------------------------------------------------- tear (per-frame unique) */

/*
 * tear N: N page flips, every frame a different full-screen picture, a
 * writeback capture of every frame. Pixel (x, y) of frame i is
 * (i & 0xff) << 16 | y: the red byte tags the commit, green/blue hold the
 * row. A capture must hold exactly one tag, the one of its own commit, on
 * every row, with every row at its place:
 *   OK     one tag, the expected one
 *   WRONG  one tag, another commit's (stale = i-1: captured before the
 *          commit was latched; early = i+1: the next commit was latched
 *          in its place, e.g. a client woken before the latch)
 *   MIXED  rows of two or more commits: a frame scanned out while the
 *          registers changed, i.e. a torn frame
 *   BAD    a row whose samples disagree or sit at the wrong row (partial
 *          row, shifted picture, unwritten buffer)
 * No poisoning is needed: a capture buffer that was not written holds the
 * tag of the frame RING flips earlier.
 * Source buffers: a ring of TEAR_SRC; frame i+2 is drawn into its buffer
 * right after commit i (that buffer last showed frame i-2, off screen
 * since flip i-1 was reported).
 */
#define TEAR_SRC	4
#define TEAR_MAX	20000

enum { TEAR_OK, TEAR_WRONG, TEAR_MIXED, TEAR_BAD };
static const char *const tear_name[] = { "OK", "WRONG", "MIXED", "BAD" };

struct tear_cls {
	int verdict, tag_top, tag_bottom, ntags, boundary, bad_rows, first_bad_row;
	uint32_t first_bad_px;
};

static inline uint32_t tear_px(int frame, int y)
{
	return ((uint32_t)(frame & 0xff) << 16) | ((uint32_t)y & 0xffff);
}

static void tear_fill(uint8_t *map, uint32_t pitch, int w, int h, int frame)
{
	for (int y = 0; y < h; y++) {
		uint32_t *row = (uint32_t *)(map + (size_t)y * pitch), v = tear_px(frame, y);

		for (int x = 0; x < w; x++)
			row[x] = v;
	}
}

static inline void tear_px_check(uint32_t p, int y, int *tag, bool *bad, uint32_t *badpx)
{
	p &= 0xffffff;
	if ((p & 0xffff) != ((uint32_t)y & 0xffff) ||
	    (*tag >= 0 && (int)(p >> 16) != *tag)) {
		if (!*bad)
			*badpx = p;
		*bad = true;
		return;
	}
	*tag = p >> 16;
}

/* @step > 1: every step-th pixel of a row plus its last one (uncached reads, see classify()) */
static void tear_classify(const uint8_t *map, uint32_t pitch, int w, int h, int step,
			  int expect, struct tear_cls *r)
{
	int tags[8], prev = -1;

	memset(r, 0, sizeof(*r));
	r->tag_top = r->tag_bottom = r->boundary = r->first_bad_row = -1;
	for (int y = 0; y < h; y++) {
		const uint32_t *row = (const uint32_t *)(map + (size_t)y * pitch);
		uint32_t badpx = 0;
		bool bad = false;
		int tag = -1, k;

		for (int x = 0; x < w; x += step)
			tear_px_check(row[x], y, &tag, &bad, &badpx);
		if (step > 1 && (w - 1) % step)
			tear_px_check(row[w - 1], y, &tag, &bad, &badpx);
		if (bad || tag < 0) {
			if (r->first_bad_row < 0) {
				r->first_bad_row = y;
				r->first_bad_px = badpx;
			}
			r->bad_rows++;
			continue;
		}
		for (k = 0; k < r->ntags; k++)
			if (tags[k] == tag)
				break;
		if (k == r->ntags && r->ntags < 8)
			tags[r->ntags++] = tag;
		if (r->tag_top < 0)
			r->tag_top = tag;
		r->tag_bottom = tag;
		if (prev >= 0 && tag != prev && r->boundary < 0)
			r->boundary = y;
		prev = tag;
	}
	if (r->bad_rows || !r->ntags)
		r->verdict = TEAR_BAD;
	else if (r->ntags > 1)
		r->verdict = TEAR_MIXED;
	else
		r->verdict = r->tag_top == (expect & 0xff) ? TEAR_OK : TEAR_WRONG;
}

/* the classifier on synthetic captures in normal memory: it must tell every case apart */
static int cmd_selftest(void)
{
	const int w = 1024, h = 768, expect = 10;
	const uint32_t pitch = w * 4;
	uint8_t *m = malloc((size_t)pitch * h);
	int fails = 0;

	if (!m)
		return 2;
	for (int c = 0; c < 7; c++) {
		static const char *const cname[] = { "pure", "stale", "torn300", "shift4",
						     "poison", "halfrow400", "row500" };
		static const int want[] = { TEAR_OK, TEAR_WRONG, TEAR_MIXED, TEAR_BAD,
					    TEAR_BAD, TEAR_BAD, TEAR_MIXED };

		tear_fill(m, pitch, w, h, c == 1 ? expect - 1 : expect);
		if (c == 2)
			tear_fill(m, pitch, w, 300, expect - 1);
		if (c == 3)
			for (int y = 0; y < h; y++)
				for (int x = 0; x < w; x++)
					((uint32_t *)(m + (size_t)y * pitch))[x] = tear_px(expect, y + 4);
		if (c == 4)
			memset(m, 0x5a, (size_t)pitch * h);
		if (c == 5)
			for (int x = w / 2; x < w; x++)
				((uint32_t *)(m + 400 * pitch))[x] = tear_px(expect - 1, 400);
		if (c == 6)
			for (int x = 0; x < w; x++)
				((uint32_t *)(m + 500 * pitch))[x] = tear_px(expect + 1, 500);
		for (int s = 0; s < 2; s++) {
			struct tear_cls r;
			int step = s ? CHECK_STEP : 1;

			tear_classify(m, pitch, w, h, step, expect, &r);
			printf("RESULT selftest %s step %d verdict %s want %s boundary %d bad_rows %d\n",
			       cname[c], step, tear_name[r.verdict], tear_name[want[c]], r.boundary,
			       r.bad_rows);
			if (r.verdict != want[c] || (c == 2 && r.boundary != 300))
				fails++;
		}
	}
	free(m);
	printf("RESULT selftest %s fails %d\n", fails ? "fail" : "pass", fails);
	return fails ? 1 : 0;
}

struct tear_rec {
	uint32_t seq;
	double t_vbl, t_commit;
	int8_t verdict;
	int16_t tag;
};

static int cmd_tear(int n)
{
	static struct dumb cap[RING], src[TEAR_SRC];
	static int32_t fence[RING];
	static struct tear_rec rec[TEAR_MAX];
	int ret, w, h, cnt[4] = { 0 }, stale = 0, early = 0, ferr = 0, checked = 0;
	int gaps = 0, gap_max = 0, first_gap = -1, full = 0, full_bad = 0, dumped = 0;
	int phase_n = 0, phase_outside = 0;
	drmEventContext ev = { .version = 3, .page_flip_handler2 = flip_handler };
	struct flip_ev fe = { 0 };
	uint32_t last_seq = 0, lcg = 12345;
	double t_first = 0, t_last = 0, t_commit, phase_sum = 0, phase_max = 0, vbl_ms, frame_ms;
	struct stat_ms ioctl_ms = { 0 }, fence_ms = { 0 }, check_ms = { 0 }, draw_ms = { 0 };

	if (n < 3 || n > TEAR_MAX) {
		fprintf(stderr, "tear: N must be 3..%d\n", TEAR_MAX);
		return 2;
	}
	if (cmd_selftest())
		return 2;
	ret = kms_init(&K, false);
	if (ret)
		return ret;
	if (o.wb_fmt != DRM_FORMAT_XRGB8888) {
		fprintf(stderr, "tear needs XR24 capture\n");
		return 2;
	}
	vbl_ms = (K.mode.vtotal - K.mode.vdisplay) * (double)K.mode.htotal /
		 (K.mode.clock * 1e3) * 1e3;
	frame_ms = K.mode.vtotal * (double)K.mode.htotal / (K.mode.clock * 1e3) * 1e3;
	w = K.mode.hdisplay;
	h = K.mode.vdisplay;
	for (int i = 0; i < TEAR_SRC; i++) {
		if (dumb_create(&K, &src[i], DRM_FORMAT_XRGB8888, w, h)) {
			perror("dumb buffer");
			return 2;
		}
		tear_fill(src[i].map, src[i].pitch, w, h, i);
	}
	for (int i = 0; i < RING; i++) {
		if (dumb_create(&K, &cap[i], DRM_FORMAT_XRGB8888, w, h)) {
			perror("dumb buffer");
			return 2;
		}
		poison(&cap[i]);
		fence[i] = -1;
	}
	/* modeset onto a picture no flip uses (tag 0xff), then settle */
	{
		struct dumb *b = &src[TEAR_SRC - 1];

		tear_fill(b->map, b->pitch, w, h, 0xff);
		if (commit(&K, b->fb_id, NULL, NULL, NULL)) {
			printf("RESULT modeset_commit_error %d\n", commit_errno);
			return 2;
		}
		usleep(100000);
		tear_fill(b->map, b->pitch, w, h, TEAR_SRC - 1);
	}

	for (int i = 0; i < n && !quit; i++) {
		int s = i % RING;
		double t0;

		if (i > 0) {
			while (!fe.done && !quit) {
				struct pollfd pfd = { .fd = K.fd, .events = POLLIN };

				if (poll(&pfd, 1, 1000) <= 0) {
					fprintf(stderr, "flip event timed out\n");
					quit = 1;
					break;
				}
				drmHandleEvent(K.fd, &ev);
			}
			if (!fe.done)
				break;
			if (!t_first)
				t_first = fe.t;
			if (last_seq && fe.seq - last_seq > 1) {
				gaps++;
				if ((int)(fe.seq - last_seq - 1) > gap_max)
					gap_max = fe.seq - last_seq - 1;
				if (first_gap < 0)
					first_gap = i - 1;
			}
			last_seq = fe.seq;
			t_last = fe.t;
			rec[i - 1].seq = fe.seq;
			rec[i - 1].t_vbl = fe.t;
			if (o.commit_delay_us > 0) {
				sleep_until(fe.t + o.commit_delay_us * 1e-6);
			} else if (o.commit_delay_us < 0) {
				/* random phase over the frame, minus 2 ms for the commit itself */
				lcg = lcg * 1103515245 + 12345;
				sleep_until(fe.t + ((lcg >> 8) % (int)((frame_ms - 2) * 1000)) * 1e-6);
			}
		}

		t_commit = now_s();
		rec[i].t_commit = t_commit;
		fe.done = false;
		if (commit(&K, src[i % TEAR_SRC].fb_id, &cap[s], &fence[s], &fe)) {
			printf("RESULT flip %d commit_error %d\n", i, commit_errno);
			ret = 2;
			break;
		}
		stat_add(&ioctl_ms, (now_s() - t_commit) * 1e3);
		if (i > 0) {
			double ph = (t_commit - t_last) * 1e3;

			if (ph >= 0) {
				phase_n++;
				phase_sum += ph;
				if (ph > phase_max)
					phase_max = ph;
				if (ph > vbl_ms)
					phase_outside++;
			}
		}

		/* while flip i waits for its vblank: check capture i-2, draw frame i+2 */
		for (int j = i - 2; j <= i - 2 + (i == n - 1 ? 2 : 0) && j >= 0 && j < n; j++) {
			struct tear_cls r;
			int st, sj = j % RING;

			if (j > i - 2 && !fe.done) {
				/* the last two: wait for the last flip first */
				while (!fe.done && !quit) {
					struct pollfd pfd = { .fd = K.fd, .events = POLLIN };

					if (poll(&pfd, 1, 1000) <= 0)
						break;
					drmHandleEvent(K.fd, &ev);
				}
				if (fe.done) {
					if (last_seq && fe.seq - last_seq > 1) {
						gaps++;
						if ((int)(fe.seq - last_seq - 1) > gap_max)
							gap_max = fe.seq - last_seq - 1;
						if (first_gap < 0)
							first_gap = i;
					}
					last_seq = fe.seq;
					t_last = fe.t;
					rec[i].seq = fe.seq;
					rec[i].t_vbl = fe.t;
				}
			}
			t0 = now_s();
			if (fence_wait(fence[sj], FENCE_TIMEOUT_MS, &st) || st < 0) {
				printf("RESULT flip %d fence_error status=%d\n", j, st);
				ferr++;
				rec[j].verdict = -1;
			} else {
				stat_add(&fence_ms, (now_s() - t0) * 1e3);
				t0 = now_s();
				tear_classify(cap[sj].map, cap[sj].pitch, w, h, CHECK_STEP, j, &r);
				stat_add(&check_ms, (now_s() - t0) * 1e3);
				checked++;
				cnt[r.verdict]++;
				rec[j].verdict = r.verdict;
				rec[j].tag = r.tag_top;
				if (r.verdict == TEAR_WRONG) {
					if (r.tag_top == ((j - 1) & 0xff))
						stale++;
					else if (r.tag_top == ((j + 1) & 0xff))
						early++;
				}
				if (r.verdict != TEAR_OK) {
					printf("RESULT flip %d %s tag_top %d tag_bottom %d ntags %d boundary_row %d bad_rows %d first_bad_row %d first_bad_px %06x expect %d\n",
					       j, tear_name[r.verdict], r.tag_top, r.tag_bottom, r.ntags,
					       r.boundary, r.bad_rows, r.first_bad_row, r.first_bad_px,
					       j & 0xff);
					if (dumped < 4) {
						char name[32];

						snprintf(name, sizeof(name), "tear-%s-%d",
							 tear_name[r.verdict], j);
						dump(&cap[sj], name);
						dumped++;
					}
				}
			}
			close(fence[sj]);
			fence[sj] = -1;
		}
		if (i + 2 < n && i >= 2) {
			struct dumb *b = &src[(i + 2) % TEAR_SRC];

			t0 = now_s();
			tear_fill(b->map, b->pitch, w, h, i + 2);
			stat_add(&draw_ms, (now_s() - t0) * 1e3);
		}
	}

	/* the last RING captures, every pixel */
	for (int j = n - RING < 0 ? 0 : n - RING; j < n && ret == 0 && !quit; j++) {
		struct tear_cls r;

		tear_classify(cap[j % RING].map, cap[j % RING].pitch, w, h, 1, j, &r);
		full++;
		if (r.verdict != TEAR_OK) {
			full_bad++;
			printf("RESULT flip %d FULL_%s tag_top %d boundary_row %d bad_rows %d\n",
			       j, tear_name[r.verdict], r.tag_top, r.boundary, r.bad_rows);
		}
	}

	if (o.dump_dir) {
		char path[512];
		FILE *f;

		snprintf(path, sizeof(path), "%s/tear.csv", o.dump_dir);
		f = fopen(path, "w");
		if (f) {
			fprintf(f, "# flip,seq,vblank_s,commit_s,commit_phase_ms,verdict,tag\n");
			for (int j = 0; j < n; j++)
				fprintf(f, "%d,%u,%.6f,%.6f,%.3f,%s,%d\n", j, rec[j].seq, rec[j].t_vbl,
					rec[j].t_commit,
					j ? (rec[j].t_commit - rec[j - 1].t_vbl) * 1e3 : 0.0,
					rec[j].verdict < 0 ? "FENCE" : tear_name[rec[j].verdict],
					rec[j].tag);
			fclose(f);
		}
	}

	printf("RESULT tear flips %d frames_checked %d ok %d wrong %d stale %d early %d mixed %d bad %d fence_errors %d\n",
	       n, checked, cnt[TEAR_OK], cnt[TEAR_WRONG], stale, early, cnt[TEAR_MIXED],
	       cnt[TEAR_BAD], ferr);
	printf("RESULT tear_full full_checked %d full_bad %d check_step %d\n", full, full_bad,
	       CHECK_STEP);
	printf("RESULT flip_rate %.3f seq_gaps %d\n",
	       t_last > t_first ? (n - 1) / (t_last - t_first) : 0.0, gaps);
	printf("RESULT seq_gap_max %d first_gap_flip %d frame_ms %.3f\n", gap_max, first_gap,
	       frame_ms);
	if (phase_n)
		printf("RESULT commit_phase mean_ms %.3f max_ms %.3f outside_blanking %d of %d blanking_ms %.3f\n",
		       phase_sum / phase_n, phase_max, phase_outside, phase_n, vbl_ms);
	stat_print("commit_ioctl", &ioctl_ms);
	stat_print("fence_wait", &fence_ms);
	stat_print("check", &check_ms);
	stat_print("draw", &draw_ms);
	if (ret)
		return ret;
	return (cnt[TEAR_WRONG] || cnt[TEAR_MIXED] || cnt[TEAR_BAD] || ferr || full_bad ||
		checked < n) ? 1 : 0;
}

/* --------------------------------------------- memload (DRAM/CPU stress) */

struct memload_arg {
	size_t bytes;
	double until;
	double moved;
};

static void *memload_thread(void *p)
{
	struct memload_arg *a = p;
	uint8_t *x = malloc(a->bytes), *y = malloc(a->bytes);

	if (!x || !y)
		return NULL;
	memset(x, 1, a->bytes);
	memset(y, 2, a->bytes);
	while (!quit && now_s() < a->until) {
		memcpy(y, x, a->bytes);
		memcpy(x, y, a->bytes);
		a->moved += 4.0 * a->bytes;	/* read + write, twice */
	}
	free(x);
	free(y);
	return NULL;
}

/* memload SECONDS THREADS MB: memcpy between two MB-MiB buffers per thread */
static int cmd_memload(int secs, int threads, int mb)
{
	pthread_t t[16];
	struct memload_arg a[16];
	double t0 = now_s(), total = 0;

	if (threads < 1 || threads > 16 || mb < 1 || secs < 1)
		return 2;
	for (int i = 0; i < threads; i++) {
		a[i] = (struct memload_arg){ .bytes = (size_t)mb << 20, .until = t0 + secs };
		pthread_create(&t[i], NULL, memload_thread, &a[i]);
	}
	for (int i = 0; i < threads; i++) {
		pthread_join(t[i], NULL);
		total += a[i].moved;
	}
	printf("RESULT memload threads %d mb %d secs %.1f GBps %.3f\n", threads, mb,
	       now_s() - t0, total / (now_s() - t0) / 1e9);
	return 0;
}

/* ------------------------------------------------------------- main */

static void on_signal(int sig)
{
	(void)sig;
	quit = 1;
}

static void usage(void)
{
	fprintf(stderr,
"usage: kms-wb [options] probe | solid RRGGBB | bars | flips N | tear N | selftest |\n"
"       memload SECONDS THREADS MB\n"
"  -d, --device PATH       DRM device (/dev/dri/card0)\n"
"  -c, --connector NAME    display connector (HDMI-A-1)\n"
"  -m, --mode WxH[@R]      mode (default: preferred)\n"
"  -w, --wb-format FOURCC  capture format: XR24 (default), NV12, XR30\n"
"  -t, --tolerance N       per-component tolerance for NV12/XR30 (3)\n"
"  -r, --repeat N          captures per static image (3)\n"
"  -D, --commit-delay US   flips: commit US us after each flip event's vblank\n"
"                          timestamp (puts the commit into the active video)\n"
"                          tear: -1 = a random phase every frame\n"
"  -o, --dump DIR          write mismatching captures as DIR/<name>.raw\n");
	exit(2);
}

int main(int argc, char **argv)
{
	static const struct option lo[] = {
		{ "device", 1, 0, 'd' }, { "connector", 1, 0, 'c' }, { "mode", 1, 0, 'm' },
		{ "wb-format", 1, 0, 'w' }, { "tolerance", 1, 0, 't' },
		{ "repeat", 1, 0, 'r' }, { "commit-delay", 1, 0, 'D' }, { "dump", 1, 0, 'o' },
		{ 0 }
	};
	int c;

	while ((c = getopt_long(argc, argv, "d:c:m:w:t:r:D:o:", lo, NULL)) != -1) {
		switch (c) {
		case 'd': o.device = optarg; break;
		case 'c': o.connector = optarg; break;
		case 'm':
			if (sscanf(optarg, "%dx%d@%d", &o.mode_w, &o.mode_h, &o.mode_r) < 2)
				usage();
			break;
		case 'w':
			if (strlen(optarg) != 4)
				usage();
			o.wb_fmt = fourcc_code(optarg[0], optarg[1], optarg[2], optarg[3]);
			break;
		case 't': o.tolerance = atoi(optarg); break;
		case 'r': o.repeat = atoi(optarg); break;
		case 'D': o.commit_delay_us = atoi(optarg); break;
		case 'o': o.dump_dir = optarg; break;
		default: usage();
		}
	}
	if (optind >= argc)
		usage();
	/* stdout is a file on the board: line-buffer it so a crash keeps the RESULT lines */
	setvbuf(stdout, NULL, _IOLBF, 0);
	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);

	if (!strcmp(argv[optind], "probe"))
		return cmd_probe();
	if (!strcmp(argv[optind], "solid") && optind + 1 < argc)
		return cmd_static(false, strtoul(argv[optind + 1], NULL, 16) & 0xffffff);
	if (!strcmp(argv[optind], "bars"))
		return cmd_static(true, 0);
	if (!strcmp(argv[optind], "flips") && optind + 1 < argc)
		return cmd_flips(atoi(argv[optind + 1]));
	if (!strcmp(argv[optind], "tear") && optind + 1 < argc)
		return cmd_tear(atoi(argv[optind + 1]));
	if (!strcmp(argv[optind], "selftest"))
		return cmd_selftest();
	if (!strcmp(argv[optind], "memload") && optind + 3 < argc)
		return cmd_memload(atoi(argv[optind + 1]), atoi(argv[optind + 2]),
				   atoi(argv[optind + 3]));
	usage();
	return 2;
}
