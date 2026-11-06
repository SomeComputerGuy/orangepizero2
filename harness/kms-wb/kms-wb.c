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

#define RING		4
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

static int commit(struct kms *k, uint32_t src_fb, struct dumb *cap, int32_t *fence_fd,
		  bool event)
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
	ret = drmModeAtomicCommit(k->fd, req, flags, NULL);
	if (ret)
		fprintf(stderr, "atomic commit (%s%s): %s\n",
			k->modeset_done ? "flip" : "modeset", cap ? " + writeback" : "",
			strerror(errno));
	else
		k->modeset_done = true;
	drmModeAtomicFree(req);
	return ret;
}

/* one blocking capture of the current frame into @cap; 0 = fence signalled ok */
static int capture_once(struct kms *k, uint32_t src_fb, struct dumb *cap, double *ms)
{
	int32_t fence = -1;
	int status, ret;
	double t0;

	poison(cap);
	t0 = now_s();
	if (commit(k, src_fb, cap, &fence, false))
		return -1;
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
	if (dumb_create(&K, &src, DRM_FORMAT_XRGB8888, w, h) ||
	    dumb_create(&K, &cap, o.wb_fmt, w, h)) {
		perror("dumb buffer");
		return 2;
	}
	fill_xr24(&src, bars, solid);

	/* show it first, without a job: the first capture is of a settled frame */
	if (commit(&K, src.fb_id, NULL, NULL, false))
		return 2;
	usleep(50000);

	for (int i = 0; i < o.repeat && !quit; i++) {
		struct cmp r;
		double ms;
		char name[32];

		ret = capture_once(&K, src.fb_id, &cap, &ms);
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
static void classify(struct dumb *c, uint32_t a, uint32_t b, int *rows_a, int *rows_b,
		     int *rows_other, int *boundary)
{
	int last = -1;

	*rows_a = *rows_b = *rows_other = 0;
	*boundary = -1;
	for (int y = 0; y < c->h; y++) {
		uint32_t *row = (uint32_t *)(c->map + y * c->pitch);
		int na = 0, nb = 0;

		for (int x = 0; x < c->w; x++) {
			uint32_t p = row[x] & 0xffffff;

			if (p == a)
				na++;
			else if (p == b)
				nb++;
		}
		if (na == c->w) {
			(*rows_a)++;
			if (last == 1 && *boundary < 0)
				*boundary = y;
			last = 0;
		} else if (nb == c->w) {
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

	ev->done = true;
	ev->seq = seq;
	ev->t = sec + usec * 1e-6;
}

/*
 * N page flips between two solid colours, each with a writeback job into a
 * ring of capture buffers. The fence of flip i-1 is waited for after the
 * flip event of flip i, so one capture is in flight while the next frame
 * is committed. A frame holding rows of both colours (or anything else) is
 * torn.
 */
static int cmd_flips(int n)
{
	const uint32_t col[2] = { 0x40c0e0, 0xe04020 };
	struct dumb src[2], cap[RING];
	int32_t fence[RING];
	int ret = kms_init(&K, false);
	int w, h, frames = 0, pure[2] = { 0 }, torn = 0, bad = 0, ferr = 0, gaps = 0;
	int first_torn = -1;
	drmEventContext ev = { .version = 3, .page_flip_handler2 = flip_handler };
	struct flip_ev fe;
	uint32_t last_seq = 0;
	double t_first = 0, t_last = 0, t_commit = 0, phase_sum = 0, phase_max = 0;
	int phase_n = 0, phase_outside = 0;
	double vbl_ms;

	if (ret)
		return ret;
	vbl_ms = (K.mode.vtotal - K.mode.vdisplay) * (double)K.mode.htotal /
		 (K.mode.clock * 1e3) * 1e3;
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
		fill_xr24(&src[i], false, col[i]);
	}
	for (int i = 0; i < RING; i++) {
		if (dumb_create(&K, &cap[i], DRM_FORMAT_XRGB8888, w, h)) {
			perror("dumb buffer");
			return 2;
		}
		fence[i] = -1;
	}

	if (commit(&K, src[0].fb_id, NULL, NULL, false))
		return 2;
	usleep(50000);

	for (int i = 0; i <= n && !quit; i++) {
		if (i < n) {
			int s = i % RING;

			if (o.commit_delay_us && i)
				usleep(o.commit_delay_us);
			poison(&cap[s]);
			t_commit = now_s();
			if (commit(&K, src[i & 1].fb_id, &cap[s], &fence[s], true)) {
				ret = 2;
				break;
			}
			/* flip event of this commit */
			fe.done = false;
			while (!fe.done && !quit) {
				struct pollfd pfd = { .fd = K.fd, .events = POLLIN };

				if (poll(&pfd, 1, 1000) <= 0) {
					fprintf(stderr, "flip event timed out\n");
					quit = 1;
					break;
				}
				drmHandleEvent(K.fd, &ev);
			}
			if (fe.done) {
				if (!t_first)
					t_first = fe.t;
				if (last_seq && fe.seq - last_seq > 1)
					gaps++;
				last_seq = fe.seq;
				if (t_last) {
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
				t_last = fe.t;
			}
		}
		if (i > 0) {
			/* the capture of the previous flip */
			int s = (i - 1) % RING, status, ra, rb, ro, boundary;

			if (fence_wait(fence[s], FENCE_TIMEOUT_MS, &status) || status < 0) {
				printf("RESULT flip %d fence_error status=%d\n", i - 1, status);
				ferr++;
			} else {
				classify(&cap[s], col[0], col[1], &ra, &rb, &ro, &boundary);
				frames++;
				if (ro) {
					bad++;
					printf("RESULT flip %d BAD rows_a %d rows_b %d rows_other %d first_bad_row %d\n",
					       i - 1, ra, rb, ro, boundary);
					if (first_torn < 0)
						first_torn = i - 1;
					if (bad <= 3) {
						char name[32];

						snprintf(name, sizeof(name), "bad-%d", i - 1);
						dump(&cap[s], name);
					}
				} else if (ra && rb) {
					torn++;
					printf("RESULT flip %d TORN rows_a %d rows_b %d boundary_row %d\n",
					       i - 1, ra, rb, boundary);
					if (first_torn < 0)
						first_torn = i - 1;
					if (torn <= 3) {
						char name[32];

						snprintf(name, sizeof(name), "torn-%d", i - 1);
						dump(&cap[s], name);
					}
				} else {
					pure[rb ? 1 : 0]++;
				}
			}
			close(fence[s]);
			fence[s] = -1;
		}
	}

	printf("RESULT flips %d frames_captured %d frames_a %d frames_b %d frames_torn %d frames_bad %d fence_errors %d\n",
	       n, frames, pure[0], pure[1], torn, bad, ferr);
	printf("RESULT flip_rate %.3f seq_gaps %d\n",
	       t_last > t_first ? (n - 1) / (t_last - t_first) : 0.0, gaps);
	if (phase_n)
		printf("RESULT commit_phase mean_ms %.3f max_ms %.3f outside_blanking %d of %d blanking_ms %.3f\n",
		       phase_sum / phase_n, phase_max, phase_outside, phase_n, vbl_ms);
	if (first_torn >= 0)
		printf("RESULT first_torn_flip %d\n", first_torn);
	if (ret)
		return ret;
	return (torn || bad || ferr || frames < n - 1) ? 1 : 0;
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
"usage: kms-wb [options] probe | solid RRGGBB | bars | flips N\n"
"  -d, --device PATH       DRM device (/dev/dri/card0)\n"
"  -c, --connector NAME    display connector (HDMI-A-1)\n"
"  -m, --mode WxH[@R]      mode (default: preferred)\n"
"  -w, --wb-format FOURCC  capture format: XR24 (default), NV12, XR30\n"
"  -t, --tolerance N       per-component tolerance for NV12/XR30 (3)\n"
"  -r, --repeat N          captures per static image (3)\n"
"  -D, --commit-delay US   flips: sleep US us after each flip event before the\n"
"                          next commit (puts the commit into the active video)\n"
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
	usage();
	return 2;
}
