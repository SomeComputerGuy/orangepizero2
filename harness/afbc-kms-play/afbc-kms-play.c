// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * afbc-kms-play: zero-copy V4L2-request (cedrus) decode -> DRM/KMS plane,
 * paced by page-flip events, with per-flip timestamp logging.
 *
 * Decoder thread: libavformat demux -> libavcodec with the v4l2request
 * hwaccel -> AV_PIX_FMT_DRM_PRIME frames -> bounded queue.
 * Main thread:    one atomic commit in flight (NONBLOCK | PAGE_FLIP_EVENT);
 *                 on every flip event the next queued frame is committed and
 *                 the frame that left the screen is released to the decoder.
 *
 * Every dmabuf is imported once (drmPrimeFDToHandle) and gets one cached
 * framebuffer (drmModeAddFB2WithModifiers), so steady-state playback does
 * no allocation, no copy and no CPU access to pixel data.
 *
 * Also: --pattern FOURCC (dumb buffers, no decoder) for flip-timing and
 * linear YUV plane checks, and --list for the planes' IN_FORMATS.
 *
 * Build: harness/afbc-kms-play/build.sh (static FFmpeg, dynamic libdrm/libc).
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <inttypes.h>
#include <math.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include <drm_fourcc.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_drm.h>
#include <libavutil/pixdesc.h>

#define MAX_FB		64
#define MAX_QUEUE	16

struct opts {
	const char *input;
	const char *device;
	const char *connector;
	const char *log_path;
	const char *pixfmt;	/* V4L2 CAPTURE fourcc forced in the decoder */
	const char *pattern;	/* DRM fourcc for dumb-buffer pattern mode */
	int mode_w, mode_h, mode_r;
	int plane_id;
	int frames;		/* stop after N displayed frames (0 = all) */
	int queue;		/* decoded-frame queue length */
	int extra_hw_frames;
	double hold;		/* keep the last frame up for N seconds */
	bool keep_primary;
	bool no_scale;
	bool list;
	bool loop;
	int afbc_pitch;		/* -1: use the descriptor pitch */
	int commit_delay_us;	/* pattern mode: wait this long after a flip before the next commit */
};

static struct opts o = {
	.device = "/dev/dri/card0",
	.pixfmt = "AS01",
	.queue = 3,
	.extra_hw_frames = -1,
	.afbc_pitch = -1,
};

static volatile sig_atomic_t quit;

static double now_s(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/* ------------------------------------------------------------------ KMS */

struct kms {
	int fd;
	uint32_t conn_id, crtc_id, plane_id, primary_id;
	int crtc_index;
	drmModeModeInfo mode;
	uint32_t mode_blob;
	/* property ids */
	uint32_t p_fb, p_crtc, p_sx, p_sy, p_sw, p_sh, p_cx, p_cy, p_cw, p_ch;
	uint32_t p_zpos, p_enc, p_range;
	uint32_t pp_fb, pp_crtc;		/* primary */
	uint32_t c_mode, c_active;		/* crtc */
	uint32_t k_crtc;			/* connector */
	bool modeset_done;
};

static uint32_t prop_id(int fd, uint32_t obj, uint32_t type, const char *name)
{
	drmModeObjectProperties *props;
	uint32_t id = 0;

	props = drmModeObjectGetProperties(fd, obj, type);
	if (!props)
		return 0;
	for (uint32_t i = 0; i < props->count_props && !id; i++) {
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
	drmModeObjectProperties *props;
	uint64_t v = 0;

	*found = false;
	props = drmModeObjectGetProperties(fd, obj, type);
	if (!props)
		return 0;
	for (uint32_t i = 0; i < props->count_props; i++) {
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

/* value of the enum entry @entry of property @name, or -1 */
static int64_t prop_enum(int fd, uint32_t obj, uint32_t type, const char *name,
			 const char *entry)
{
	drmModeObjectProperties *props;
	int64_t v = -1;

	props = drmModeObjectGetProperties(fd, obj, type);
	if (!props)
		return -1;
	for (uint32_t i = 0; i < props->count_props; i++) {
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

/*
 * IN_FORMATS blob walk. The sysroot libdrm's drmModeFormatModifierBlobIterNext()
 * mis-reports format/modifier pairs (e.g. YTR on YUYV), so parse it here.
 */
static bool blob_has(const drmModePropertyBlobRes *blob, uint32_t fmt, uint64_t mod)
{
	const struct drm_format_modifier_blob *h = blob->data;
	const uint32_t *fmts = (const uint32_t *)((const char *)h + h->formats_offset);
	const struct drm_format_modifier *mods =
		(const void *)((const char *)h + h->modifiers_offset);

	for (uint32_t f = 0; f < h->count_formats; f++) {
		if (fmts[f] != fmt)
			continue;
		for (uint32_t m = 0; m < h->count_modifiers; m++)
			if (mods[m].modifier == mod && f >= mods[m].offset &&
			    f < mods[m].offset + 64 &&
			    (mods[m].formats >> (f - mods[m].offset) & 1))
				return true;
	}
	return false;
}

static bool plane_supports(int fd, uint32_t plane, uint32_t fmt, uint64_t mod)
{
	drmModePropertyBlobRes *blob;
	bool found, ok = false;
	uint64_t blob_id;

	blob_id = prop_value(fd, plane, DRM_MODE_OBJECT_PLANE, "IN_FORMATS", &found);
	if (!found || !blob_id) {
		/* no modifier info: linear only */
		drmModePlane *p = drmModeGetPlane(fd, plane);

		if (p && mod == DRM_FORMAT_MOD_LINEAR)
			for (uint32_t i = 0; i < p->count_formats; i++)
				ok |= p->formats[i] == fmt;
		drmModeFreePlane(p);
		return ok;
	}
	blob = drmModeGetPropertyBlob(fd, blob_id);
	if (!blob)
		return false;
	ok = blob_has(blob, fmt, mod);
	drmModeFreePropertyBlob(blob);
	return ok;
}

static void list_planes(int fd)
{
	drmModePlaneRes *pr = drmModeGetPlaneResources(fd);

	if (!pr)
		return;
	for (uint32_t i = 0; i < pr->count_planes; i++) {
		drmModePropertyBlobRes *blob;
		drmModePlane *p = drmModeGetPlane(fd, pr->planes[i]);
		uint64_t type, blob_id;
		bool found;

		type = prop_value(fd, p->plane_id, DRM_MODE_OBJECT_PLANE, "type", &found);
		printf("plane %u possible_crtcs 0x%x type %s formats %u\n", p->plane_id,
		       p->possible_crtcs,
		       type == DRM_PLANE_TYPE_PRIMARY ? "primary" :
		       type == DRM_PLANE_TYPE_CURSOR ? "cursor" : "overlay",
		       p->count_formats);
		blob_id = prop_value(fd, p->plane_id, DRM_MODE_OBJECT_PLANE, "IN_FORMATS", &found);
		if (found && blob_id && (blob = drmModeGetPropertyBlob(fd, blob_id))) {
			/*
			 * Walk the blob by hand: the sysroot libdrm's
			 * drmModeFormatModifierBlobIterNext() mis-reports
			 * format/modifier pairs on this kernel.
			 */
			const struct drm_format_modifier_blob *h = blob->data;
			const uint32_t *fmts = (const uint32_t *)((const char *)h + h->formats_offset);
			const struct drm_format_modifier *mods =
				(const void *)((const char *)h + h->modifiers_offset);

			for (uint32_t f = 0; f < h->count_formats; f++)
				for (uint32_t m = 0; m < h->count_modifiers; m++) {
					const struct drm_format_modifier *md = &mods[m];
					char *mn;

					if (f < md->offset || f >= md->offset + 64 ||
					    !(md->formats >> (f - md->offset) & 1))
						continue;
					mn = drmGetFormatModifierName(md->modifier);
					printf("  %.4s 0x%016" PRIx64 " %s\n", (const char *)&fmts[f],
					       (uint64_t)md->modifier, mn ? mn : "?");
					free(mn);
				}
			drmModeFreePropertyBlob(blob);
		}
		drmModeFreePlane(p);
	}
	drmModeFreePlaneResources(pr);
}

static int kms_init(struct kms *k, uint32_t fmt, uint64_t mod)
{
	drmModeRes *res;
	drmModeConnector *conn = NULL;
	drmModePlaneRes *pr;
	int ret = -1;

	k->fd = open(o.device, O_RDWR | O_CLOEXEC);
	if (k->fd < 0) {
		perror(o.device);
		return -1;
	}
	if (drmSetClientCap(k->fd, DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1) ||
	    drmSetClientCap(k->fd, DRM_CLIENT_CAP_ATOMIC, 1)) {
		fprintf(stderr, "atomic KMS not available\n");
		return -1;
	}
	if (o.list) {
		list_planes(k->fd);
		return 1;
	}
	res = drmModeGetResources(k->fd);
	if (!res)
		return -1;

	for (int i = 0; i < res->count_connectors && !k->conn_id; i++) {
		char name[64];

		conn = drmModeGetConnector(k->fd, res->connectors[i]);
		if (!conn)
			continue;
		snprintf(name, sizeof(name), "%s-%u",
			 drmModeGetConnectorTypeName(conn->connector_type),
			 conn->connector_type_id);
		if ((o.connector && !strcmp(name, o.connector)) ||
		    (!o.connector && conn->connection == DRM_MODE_CONNECTED &&
		     conn->count_modes)) {
			k->conn_id = conn->connector_id;
			fprintf(stderr, "connector %s (%u) %s, %d modes\n", name,
				conn->connector_id,
				conn->connection == DRM_MODE_CONNECTED ?
				"connected" : "not connected", conn->count_modes);
			break;
		}
		drmModeFreeConnector(conn);
		conn = NULL;
	}
	if (!conn || !conn->count_modes) {
		fprintf(stderr, "no usable connector\n");
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
		goto out;
	}
	fprintf(stderr, "mode %s %d kHz %ux%u total %ux%u -> %.4f Hz\n",
		k->mode.name, k->mode.clock, k->mode.hdisplay, k->mode.vdisplay,
		k->mode.htotal, k->mode.vtotal,
		k->mode.clock * 1000.0 / (k->mode.htotal * k->mode.vtotal));

	/* CRTC: the first one reachable from the connector's encoders */
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

	pr = drmModeGetPlaneResources(k->fd);
	for (uint32_t i = 0; pr && i < pr->count_planes; i++) {
		drmModePlane *p = drmModeGetPlane(k->fd, pr->planes[i]);
		bool found;
		uint64_t type;

		if (!(p->possible_crtcs & (1u << k->crtc_index))) {
			drmModeFreePlane(p);
			continue;
		}
		type = prop_value(k->fd, p->plane_id, DRM_MODE_OBJECT_PLANE, "type", &found);
		if (type == DRM_PLANE_TYPE_PRIMARY && !k->primary_id)
			k->primary_id = p->plane_id;
		if (!k->plane_id && (o.plane_id ? p->plane_id == (uint32_t)o.plane_id :
				     plane_supports(k->fd, p->plane_id, fmt, mod)))
			k->plane_id = p->plane_id;
		drmModeFreePlane(p);
	}
	drmModeFreePlaneResources(pr);
	if (!k->plane_id) {
		fprintf(stderr, "no plane on crtc %u supports %.4s/0x%016" PRIx64 "\n",
			k->crtc_id, (char *)&fmt, mod);
		goto out;
	}
	fprintf(stderr, "crtc %u, plane %u (primary %u), format %.4s modifier 0x%016" PRIx64 "\n",
		k->crtc_id, k->plane_id, k->primary_id, (char *)&fmt, mod);

#define P(f, n) k->f = prop_id(k->fd, k->plane_id, DRM_MODE_OBJECT_PLANE, n)
	P(p_fb, "FB_ID"); P(p_crtc, "CRTC_ID");
	P(p_sx, "SRC_X"); P(p_sy, "SRC_Y"); P(p_sw, "SRC_W"); P(p_sh, "SRC_H");
	P(p_cx, "CRTC_X"); P(p_cy, "CRTC_Y"); P(p_cw, "CRTC_W"); P(p_ch, "CRTC_H");
	P(p_zpos, "zpos"); P(p_enc, "COLOR_ENCODING"); P(p_range, "COLOR_RANGE");
#undef P
	if (k->primary_id && k->primary_id != k->plane_id) {
		k->pp_fb = prop_id(k->fd, k->primary_id, DRM_MODE_OBJECT_PLANE, "FB_ID");
		k->pp_crtc = prop_id(k->fd, k->primary_id, DRM_MODE_OBJECT_PLANE, "CRTC_ID");
	}
	k->c_mode = prop_id(k->fd, k->crtc_id, DRM_MODE_OBJECT_CRTC, "MODE_ID");
	k->c_active = prop_id(k->fd, k->crtc_id, DRM_MODE_OBJECT_CRTC, "ACTIVE");
	k->k_crtc = prop_id(k->fd, k->conn_id, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID");
	if (drmModeCreatePropertyBlob(k->fd, &k->mode, sizeof(k->mode), &k->mode_blob))
		goto out;
	ret = 0;
out:
	drmModeFreeConnector(conn);
	drmModeFreeResources(res);
	return ret;
}

struct fbinfo {
	ino_t ino;		/* dmabuf inode identifies the buffer */
	uint32_t handle, fb_id;
};

static struct fbinfo fbs[MAX_FB];
static int nfbs;

static uint32_t fb_for_desc(struct kms *k, const AVDRMFrameDescriptor *d,
			    int w, int h)
{
	uint32_t handles[4] = { 0 }, pitches[4] = { 0 }, offsets[4] = { 0 };
	uint64_t mods[4] = { 0 };
	const AVDRMLayerDescriptor *l = &d->layers[0];
	struct stat st;
	uint32_t handle, fb_id;

	if (fstat(d->objects[0].fd, &st))
		return 0;
	for (int i = 0; i < nfbs; i++)
		if (fbs[i].ino == st.st_ino)
			return fbs[i].fb_id;
	if (nfbs == MAX_FB) {
		fprintf(stderr, "fb cache full\n");
		return 0;
	}
	if (drmPrimeFDToHandle(k->fd, d->objects[0].fd, &handle)) {
		perror("drmPrimeFDToHandle");
		return 0;
	}
	for (int i = 0; i < l->nb_planes; i++) {
		handles[i] = handle;
		pitches[i] = l->planes[i].pitch;
		offsets[i] = l->planes[i].offset;
		mods[i] = d->objects[0].format_modifier;
	}
	if ((mods[0] >> 56) == DRM_FORMAT_MOD_VENDOR_ARM && o.afbc_pitch >= 0)
		pitches[0] = o.afbc_pitch;
	if (drmModeAddFB2WithModifiers(k->fd, w, h, l->format, handles, pitches,
				       offsets, mods, &fb_id, DRM_MODE_FB_MODIFIERS)) {
		fprintf(stderr, "AddFB2 %dx%d %.4s mod 0x%016" PRIx64 " pitch %u size %zu: %s\n",
			w, h, (char *)&l->format, mods[0], pitches[0],
			d->objects[0].size, strerror(errno));
		return 0;
	}
	fbs[nfbs++] = (struct fbinfo){ st.st_ino, handle, fb_id };
	fprintf(stderr, "fb %u for dmabuf ino %lu (%zu bytes) desc %.4s mod 0x%016" PRIx64
		" planes %d pitch %u\n", fb_id, (unsigned long)st.st_ino, d->objects[0].size,
		(const char *)&l->format, mods[0], l->nb_planes, pitches[0]);
	if (o.pixfmt && !strncmp(o.pixfmt, "AS", 2) &&
	    (mods[0] >> 56) != DRM_FORMAT_MOD_VENDOR_ARM)
		fprintf(stderr, "WARNING: %s requested but the decoder exported a non-AFBC buffer\n",
			o.pixfmt);
	return fb_id;
}

/* commit @fb_id (w x h source) to the plane; first call does the modeset */
static int kms_commit(struct kms *k, uint32_t fb_id, int w, int h,
		      int enc, int range, void *user)
{
	drmModeAtomicReq *req = drmModeAtomicAlloc();
	uint32_t flags = DRM_MODE_PAGE_FLIP_EVENT | DRM_MODE_ATOMIC_NONBLOCK;
	int dw = k->mode.hdisplay, dh = k->mode.vdisplay, dx = 0, dy = 0, ret;

	if (o.no_scale) {
		dw = w < dw ? w : dw;
		dh = h < dh ? h : dh;
	} else if ((int64_t)w * dh != (int64_t)h * dw) {
		/* keep the aspect ratio */
		if ((int64_t)w * dh > (int64_t)h * dw)
			dh = (int64_t)h * dw / w;
		else
			dw = (int64_t)w * dh / h;
		dx = (k->mode.hdisplay - dw) / 2;
		dy = (k->mode.vdisplay - dh) / 2;
	}

	drmModeAtomicAddProperty(req, k->plane_id, k->p_fb, fb_id);
	if (!k->modeset_done) {
		drmModeAtomicAddProperty(req, k->plane_id, k->p_crtc, k->crtc_id);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_sx, 0);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_sy, 0);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_sw, (uint64_t)w << 16);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_sh, (uint64_t)h << 16);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_cx, dx);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_cy, dy);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_cw, dw);
		drmModeAtomicAddProperty(req, k->plane_id, k->p_ch, dh);
		if (k->p_enc && enc >= 0)
			drmModeAtomicAddProperty(req, k->plane_id, k->p_enc, enc);
		if (k->p_range && range >= 0)
			drmModeAtomicAddProperty(req, k->plane_id, k->p_range, range);
		if (k->p_zpos && o.keep_primary)
			drmModeAtomicAddProperty(req, k->plane_id, k->p_zpos, 2);
		if (k->pp_fb && !o.keep_primary) {
			drmModeAtomicAddProperty(req, k->primary_id, k->pp_fb, 0);
			drmModeAtomicAddProperty(req, k->primary_id, k->pp_crtc, 0);
		}
		drmModeAtomicAddProperty(req, k->crtc_id, k->c_mode, k->mode_blob);
		drmModeAtomicAddProperty(req, k->crtc_id, k->c_active, 1);
		drmModeAtomicAddProperty(req, k->conn_id, k->k_crtc, k->crtc_id);
		flags = DRM_MODE_PAGE_FLIP_EVENT | DRM_MODE_ATOMIC_ALLOW_MODESET;
	}
	ret = drmModeAtomicCommit(k->fd, req, flags, user);
	if (ret)
		fprintf(stderr, "atomic commit (fb %u, %s): %s\n", fb_id,
			k->modeset_done ? "flip" : "modeset", strerror(errno));
	else
		k->modeset_done = true;
	drmModeAtomicFree(req);
	return ret;
}

/* ------------------------------------------------------------ decoder */

struct qframe {
	AVFrame *f;		/* NULL for pattern mode */
	uint32_t fb_id;
	int64_t index;
	double t_decoded;
	double dec_ms;		/* avcodec_receive_frame() latency */
};

static struct {
	pthread_mutex_t lock;
	pthread_cond_t space;
	struct qframe q[MAX_QUEUE];
	int head, count;
	bool eos;
	int efd;		/* signals the main thread */
} Q = { .lock = PTHREAD_MUTEX_INITIALIZER, .space = PTHREAD_COND_INITIALIZER };

static void q_push(struct qframe *qf)
{
	uint64_t one = 1;

	pthread_mutex_lock(&Q.lock);
	while (Q.count == o.queue && !quit)
		pthread_cond_wait(&Q.space, &Q.lock);
	if (quit) {
		pthread_mutex_unlock(&Q.lock);
		av_frame_free(&qf->f);
		return;
	}
	Q.q[(Q.head + Q.count) % MAX_QUEUE] = *qf;
	Q.count++;
	pthread_mutex_unlock(&Q.lock);
	if (write(Q.efd, &one, sizeof(one)) < 0)
		perror("eventfd");
}

static bool q_pop(struct qframe *qf, int *depth)
{
	bool ok = false;

	pthread_mutex_lock(&Q.lock);
	*depth = Q.count;
	if (Q.count) {
		*qf = Q.q[Q.head];
		Q.head = (Q.head + 1) % MAX_QUEUE;
		Q.count--;
		ok = true;
		pthread_cond_signal(&Q.space);
	}
	pthread_mutex_unlock(&Q.lock);
	return ok;
}

static void q_eos(void)
{
	uint64_t one = 1;

	pthread_mutex_lock(&Q.lock);
	Q.eos = true;
	pthread_mutex_unlock(&Q.lock);
	if (write(Q.efd, &one, sizeof(one)) < 0)
		perror("eventfd");
}

static enum AVPixelFormat get_format(AVCodecContext *c, const enum AVPixelFormat *f)
{
	for (; *f != AV_PIX_FMT_NONE; f++)
		if (*f == AV_PIX_FMT_DRM_PRIME)
			return *f;
	fprintf(stderr, "decoder offers no DRM_PRIME output\n");
	return AV_PIX_FMT_NONE;
}

struct dec {
	AVFormatContext *fmt;
	AVCodecContext *ctx;
	AVBufferRef *hw;
	int stream;
	int64_t decoded;
	double dec_ms_sum, dec_ms_max;
};

static int dec_open(struct dec *d)
{
	const AVCodec *codec;
	AVStream *st;
	int ret;

	if (o.pixfmt && *o.pixfmt)
		setenv("V4L2REQUEST_PIXFMT", o.pixfmt, 1);
	ret = avformat_open_input(&d->fmt, o.input, NULL, NULL);
	if (ret < 0 || avformat_find_stream_info(d->fmt, NULL) < 0) {
		fprintf(stderr, "cannot open %s: %s\n", o.input, av_err2str(ret));
		return -1;
	}
	d->stream = av_find_best_stream(d->fmt, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
	if (d->stream < 0)
		return -1;
	st = d->fmt->streams[d->stream];
	d->ctx = avcodec_alloc_context3(codec);
	avcodec_parameters_to_context(d->ctx, st->codecpar);
	ret = av_hwdevice_ctx_create(&d->hw, AV_HWDEVICE_TYPE_V4L2REQUEST, NULL, NULL, 0);
	if (ret < 0) {
		fprintf(stderr, "v4l2request device: %s\n", av_err2str(ret));
		return -1;
	}
	d->ctx->hw_device_ctx = av_buffer_ref(d->hw);
	d->ctx->get_format = get_format;
	/* frames held outside the decoder: queue + on screen + pending flip */
	d->ctx->extra_hw_frames = o.extra_hw_frames >= 0 ? o.extra_hw_frames : o.queue + 3;
	ret = avcodec_open2(d->ctx, codec, NULL);
	if (ret < 0) {
		fprintf(stderr, "avcodec_open2: %s\n", av_err2str(ret));
		return -1;
	}
	fprintf(stderr, "%s %dx%d %s, extra_hw_frames %d, CAPTURE override %s\n",
		codec->name, d->ctx->width, d->ctx->height,
		av_get_pix_fmt_name(d->ctx->sw_pix_fmt), d->ctx->extra_hw_frames,
		o.pixfmt && *o.pixfmt ? o.pixfmt : "none");
	return 0;
}

static struct kms K;

static void *dec_thread(void *arg)
{
	struct dec *d = arg;
	AVPacket *pkt = av_packet_alloc();
	AVFrame *f = av_frame_alloc();
	bool flushing = false;

	while (!quit) {
		double t0 = now_s();
		int ret = avcodec_receive_frame(d->ctx, f);

		if (ret == 0) {
			struct qframe qf = { .f = av_frame_clone(f), .index = d->decoded++ };
			double ms = (now_s() - t0) * 1e3;

			av_frame_unref(f);
			qf.t_decoded = now_s();
			qf.dec_ms = ms;
			d->dec_ms_sum += ms;
			if (ms > d->dec_ms_max)
				d->dec_ms_max = ms;
			q_push(&qf);
			if (o.frames && d->decoded >= o.frames)
				break;
			continue;
		}
		if (ret == AVERROR_EOF) {
			if (!o.loop)
				break;
			av_seek_frame(d->fmt, d->stream, 0, AVSEEK_FLAG_BACKWARD);
			avcodec_flush_buffers(d->ctx);
			flushing = false;
			continue;
		}
		if (ret != AVERROR(EAGAIN)) {
			fprintf(stderr, "receive_frame: %s\n", av_err2str(ret));
			break;
		}
		if (flushing)
			continue;
		ret = av_read_frame(d->fmt, pkt);
		if (ret < 0) {
			avcodec_send_packet(d->ctx, NULL);
			flushing = true;
			continue;
		}
		if (pkt->stream_index == d->stream) {
			ret = avcodec_send_packet(d->ctx, pkt);
			if (ret < 0 && ret != AVERROR(EAGAIN))
				fprintf(stderr, "send_packet: %s\n", av_err2str(ret));
		}
		av_packet_unref(pkt);
	}
	av_frame_free(&f);
	av_packet_free(&pkt);
	q_eos();
	return NULL;
}

/* ------------------------------------------------- dumb-buffer pattern */

struct dumb {
	uint32_t handle, fb_id, pitch;
	uint64_t size;
	uint8_t *map;
};

static int pattern_fourcc(void)
{
	const char *s = o.pattern;

	return fourcc_code(s[0], s[1], s[2], s[3]);
}

/*
 * 8 colour bars (BT.709 limited) plus a moving bar per frame. Only columns
 * [x0, x1) are (re)drawn, so a flip costs a 16-column stripe rather than a
 * full 4K repaint through the uncached dumb-buffer mapping (which took
 * 70-110 ms per frame on the A53s and made flip timing client-bound).
 */
static void pattern_cols(struct dumb *b, uint32_t fmt, int w, int h, int frame,
			 int x0, int x1)
{
	static const uint8_t yuv[8][3] = {
		{180, 128, 128}, {168, 44, 136}, {145, 147, 44}, {133, 63, 52},
		{63, 193, 204}, {51, 109, 212}, {28, 212, 120}, {16, 128, 128},
	};
	static const uint32_t rgb[8] = {
		0xbfbfbf, 0xbfbf00, 0x00bfbf, 0x00bf00,
		0xbf00bf, 0xbf0000, 0x0000bf, 0x000000,
	};
	int bar = (frame * 8) % w;

	x0 = x0 < 0 ? 0 : x0 & ~1;
	x1 = x1 > w ? w : x1;
	for (int y = 0; y < h; y++)
		for (int x = x0; x < x1; x++) {
			int i = (x >= bar && x < bar + 16) ? 0 : x * 8 / w;

			if (fmt == DRM_FORMAT_XRGB8888)
				((uint32_t *)(b->map + y * b->pitch))[x] = rgb[i];
			else
				b->map[y * b->pitch + x] = yuv[i][0];
		}
	if (fmt == DRM_FORMAT_NV12)
		for (int y = 0; y < h / 2; y++)
			for (int x = x0 / 2; x < (x1 + 1) / 2; x++) {
				int i = (2 * x >= bar && 2 * x < bar + 16) ? 0 : 2 * x * 8 / w;
				uint8_t *c = b->map + (h + y) * b->pitch + 2 * x;

				c[0] = yuv[i][1];
				c[1] = yuv[i][2];
			}
}

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

/* -------------------------------------------------------------- stats */

struct flip {
	uint32_t seq;
	double t;		/* vblank timestamp (CLOCK_MONOTONIC) */
	double t_commit;	/* when the commit for this flip was issued */
	int64_t index;
	int depth;
	double dec_ms;
};

static struct flip *flips;
static size_t nflips, cap_flips;
static int underruns;

struct pending {
	bool busy;
	struct qframe on_screen, in_flight;
	double t_commit;
	int depth;
};

static struct pending S;

static void page_flip_handler(int fd, unsigned int seq, unsigned int sec,
			      unsigned int usec, unsigned int crtc, void *data)
{
	if (nflips == cap_flips) {
		cap_flips = cap_flips ? cap_flips * 2 : 4096;
		flips = realloc(flips, cap_flips * sizeof(*flips));
	}
	flips[nflips++] = (struct flip){
		.seq = seq, .t = sec + usec * 1e-6, .t_commit = S.t_commit,
		.index = S.in_flight.index, .depth = S.depth,
		.dec_ms = S.in_flight.dec_ms,
	};
	av_frame_free(&S.on_screen.f);	/* left the screen: back to the decoder */
	S.on_screen = S.in_flight;
	S.in_flight = (struct qframe){ 0 };
	S.busy = false;
}

static void report(struct dec *d)
{
	FILE *log = o.log_path ? fopen(o.log_path, "w") : NULL;
	int gaps = 0, missed = 0, hist[7] = { 0 };
	static const char *hn[7] = { "<15", "15-16.2", "16.2-17.2", "17.2-18",
				     "18-34", "34-51", ">=51" };
	double sum = 0, sum2 = 0, fps = 0;

	if (log) {
		fprintf(log, "# flip,seq,vblank_s,commit_s,commit_to_vblank_ms,frame,queue_depth,decode_ms\n");
		for (size_t i = 0; i < nflips; i++)
			fprintf(log, "%zu,%u,%.6f,%.6f,%.3f,%" PRId64 ",%d,%.3f\n", i,
				flips[i].seq, flips[i].t, flips[i].t_commit,
				(flips[i].t - flips[i].t_commit) * 1e3, flips[i].index,
				flips[i].depth, flips[i].dec_ms);
		fclose(log);
	}
	for (size_t i = 1; i < nflips; i++) {
		double dt = (flips[i].t - flips[i - 1].t) * 1e3;
		uint32_t ds = flips[i].seq - flips[i - 1].seq;

		if (ds > 1) {
			gaps++;
			missed += ds - 1;
		}
		sum += dt;
		sum2 += dt * dt;
		hist[dt < 15 ? 0 : dt < 16.2 ? 1 : dt < 17.2 ? 2 : dt < 18 ? 3 :
		     dt < 34 ? 4 : dt < 51 ? 5 : 6]++;
	}
	if (nflips > 1)
		fps = (nflips - 1) / (flips[nflips - 1].t - flips[0].t);
	{
		/*
		 * Without RCQ the DE33 registers are written at commit time.
		 * Report where in the frame the commits landed: after the
		 * previous vblank event, inside the vertical blanking or not.
		 */
		double vbl = (K.mode.vtotal - K.mode.vdisplay) * (double)K.mode.htotal /
			     (K.mode.clock * 1e3) * 1e3, pmax = 0, psum = 0;
		int outside = 0, n = 0;

		for (size_t i = 1; i < nflips; i++) {
			double ph = (flips[i].t_commit - flips[i - 1].t) * 1e3;

			if (ph < 0)
				continue;
			n++;
			psum += ph;
			if (ph > pmax)
				pmax = ph;
			if (ph > vbl)
				outside++;
		}
		if (n)
			printf("commit phase after previous vblank: mean %.3f ms max %.3f ms, "
			       "%d of %d later than the %.3f ms vertical blanking\n",
			       psum / n, pmax, outside, n, vbl);
	}
	printf("flips %zu, %.3f flips/s over %.3f s, mode refresh %.4f Hz\n", nflips, fps,
	       nflips > 1 ? flips[nflips - 1].t - flips[0].t : 0.0,
	       K.mode.clock * 1000.0 / (K.mode.htotal * K.mode.vtotal));
	if (nflips > 1) {
		double n = nflips - 1, mean = sum / n;

		printf("frame interval mean %.3f ms, sd %.3f ms\n", mean,
		       sqrt(fmax(0, sum2 / n - mean * mean)));
	}
	printf("vblank sequence gaps >1: %d (%d vblanks repeated a frame)\n", gaps, missed);
	printf("queue empty at flip (decoder late): %d\n", underruns);
	printf("dt histogram:");
	for (int i = 0; i < 7; i++)
		printf(" [%s ms] %d", hn[i], hist[i]);
	printf("\n");
	if (d && d->decoded)
		printf("decoded %" PRId64 ", receive_frame mean %.2f ms max %.2f ms\n",
		       d->decoded, d->dec_ms_sum / d->decoded, d->dec_ms_max);
}

/* --------------------------------------------------------------- main */

static void on_signal(int sig)
{
	quit = 1;
}

static void usage(void)
{
	fprintf(stderr,
"usage: afbc-kms-play [options] <file|url>\n"
"       afbc-kms-play --pattern NV12|XR24 [options]\n"
"       afbc-kms-play --list\n"
"  -d, --device PATH      DRM device (/dev/dri/card0)\n"
"  -c, --connector NAME   e.g. HDMI-A-1 (default: first connected)\n"
"  -m, --mode WxH[@R]     mode (default: preferred)\n"
"  -p, --plane ID         plane (default: first one taking the format)\n"
"  -n, --frames N         stop after N frames\n"
"  -q, --queue N          decoded-frame queue (3)\n"
"  -x, --extra-hw-frames N  decoder pool extra (queue + 3)\n"
"  -f, --pixfmt FOURCC    V4L2 CAPTURE format to force: AS01 (AFBC10, default),\n"
"                         AS12 (AFBC8), P010/NV12 (linear); '' = driver default\n"
"  -o, --log FILE         per-flip CSV log\n"
"  -H, --hold SECONDS     keep the last frame on screen\n"
"  -k, --keep-primary     leave the primary plane on (VI plane zpos 2)\n"
"  -s, --no-scale         1:1, top-left\n"
"  -l, --loop             loop the input\n"
"      --afbc-pitch N     pitch passed with AFBC framebuffers (descriptor's)\n"
"  -D, --commit-delay US  pattern mode: sleep US us after each flip event before\n"
"                         the next commit (puts the commit at a chosen scanout phase)\n");
	exit(2);
}

int main(int argc, char **argv)
{
	static const struct option lo[] = {
		{ "device", 1, 0, 'd' }, { "connector", 1, 0, 'c' }, { "mode", 1, 0, 'm' },
		{ "plane", 1, 0, 'p' }, { "frames", 1, 0, 'n' }, { "queue", 1, 0, 'q' },
		{ "extra-hw-frames", 1, 0, 'x' }, { "pixfmt", 1, 0, 'f' },
		{ "log", 1, 0, 'o' }, { "hold", 1, 0, 'H' }, { "keep-primary", 0, 0, 'k' },
		{ "no-scale", 0, 0, 's' }, { "loop", 0, 0, 'l' }, { "list", 0, 0, 'L' },
		{ "pattern", 1, 0, 'P' }, { "afbc-pitch", 1, 0, 'A' },
		{ "commit-delay", 1, 0, 'D' }, { 0 }
	};
	struct dec d = { 0 };
	struct dumb dumbs[2];
	pthread_t thr;
	drmEventContext ev = { .version = 3, .page_flip_handler2 = page_flip_handler };
	uint32_t fmt = DRM_FORMAT_YUV420_10BIT;
	uint64_t mod = DRM_FORMAT_MOD_ARM_AFBC(AFBC_FORMAT_MOD_BLOCK_SIZE_16x16 |
					       AFBC_FORMAT_MOD_SPARSE | AFBC_FORMAT_MOD_SPLIT);
	int c, w = 0, h = 0, enc = -1, range = -1, ret;
	double t_end_hold = 0;
	bool eos = false, first = true, starved = false;
	int64_t pat_frame = 0;

	while ((c = getopt_long(argc, argv, "d:c:m:p:n:q:x:f:o:H:kslLP:A:D:", lo, NULL)) != -1) {
		switch (c) {
		case 'd': o.device = optarg; break;
		case 'c': o.connector = optarg; break;
		case 'm':
			if (sscanf(optarg, "%dx%d@%d", &o.mode_w, &o.mode_h, &o.mode_r) < 2)
				usage();
			break;
		case 'p': o.plane_id = atoi(optarg); break;
		case 'n': o.frames = atoi(optarg); break;
		case 'q': o.queue = atoi(optarg); break;
		case 'x': o.extra_hw_frames = atoi(optarg); break;
		case 'f': o.pixfmt = optarg; break;
		case 'o': o.log_path = optarg; break;
		case 'H': o.hold = atof(optarg); break;
		case 'k': o.keep_primary = true; break;
		case 's': o.no_scale = true; break;
		case 'l': o.loop = true; break;
		case 'L': o.list = true; break;
		case 'P': o.pattern = optarg; break;
		case 'A': o.afbc_pitch = atoi(optarg); break;
		case 'D': o.commit_delay_us = atoi(optarg); break;
		default: usage();
		}
	}
	if (optind < argc)
		o.input = argv[optind];
	if (!o.list && !o.input == !o.pattern)
		usage();
	if (o.queue < 1 || o.queue > MAX_QUEUE)
		usage();
	if (o.pattern && strlen(o.pattern) != 4)
		usage();
	signal(SIGINT, on_signal);
	signal(SIGTERM, on_signal);
	Q.efd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);

	if (o.pattern) {
		fmt = pattern_fourcc();
		mod = DRM_FORMAT_MOD_LINEAR;
	} else if (!o.list && dec_open(&d)) {
		return 1;
	}
	if (!o.pattern && !o.list && o.pixfmt && !strcmp(o.pixfmt, "AS12")) {
		fmt = DRM_FORMAT_YUV420_8BIT;	/* 8-bit AFBC, same modifier */
	} else if (!o.pattern && !o.list && (!o.pixfmt || strcmp(o.pixfmt, "AS01"))) {
		/* linear output: P010 for 10-bit, NV12 otherwise */
		fmt = d.ctx->sw_pix_fmt == AV_PIX_FMT_P010 ||
		      av_pix_fmt_desc_get(d.ctx->sw_pix_fmt)->comp[0].depth > 8 ?
		      DRM_FORMAT_P010 : DRM_FORMAT_NV12;
		mod = DRM_FORMAT_MOD_LINEAR;
	}
	ret = kms_init(&K, fmt, mod);
	if (ret)
		return ret < 0 ? 1 : 0;

	if (o.pattern) {
		w = o.mode_w ? o.mode_w : K.mode.hdisplay;
		h = o.mode_h ? o.mode_h : K.mode.vdisplay;
		for (int i = 0; i < 2; i++)
			if (dumb_create(&K, &dumbs[i], fmt, w, h)) {
				perror("dumb buffer");
				return 1;
			}
	} else {
		enum AVColorSpace cs = d.ctx->colorspace;

		enc = prop_enum(K.fd, K.plane_id, DRM_MODE_OBJECT_PLANE, "COLOR_ENCODING",
				cs == AVCOL_SPC_BT2020_NCL || cs == AVCOL_SPC_BT2020_CL ?
				"ITU-R BT.2020 YCbCr" :
				cs == AVCOL_SPC_BT470BG || cs == AVCOL_SPC_SMPTE170M ?
				"ITU-R BT.601 YCbCr" : "ITU-R BT.709 YCbCr");
		range = prop_enum(K.fd, K.plane_id, DRM_MODE_OBJECT_PLANE, "COLOR_RANGE",
				  d.ctx->color_range == AVCOL_RANGE_JPEG ?
				  "YCbCr full range" : "YCbCr limited range");
		pthread_create(&thr, NULL, dec_thread, &d);
	}

	while (!quit) {
		struct pollfd pfd[2] = {
			{ .fd = K.fd, .events = POLLIN },
			{ .fd = Q.efd, .events = POLLIN },
		};
		uint64_t junk;

		if (!S.busy) {
			struct qframe qf = { 0 };
			int depth = 0;
			bool have;

			if (o.pattern) {
				struct dumb *b = &dumbs[pat_frame & 1];

				have = !o.frames || pat_frame < o.frames;
				if (have) {
					/* this buffer last showed pat_frame - 2 */
					int ob = ((pat_frame - 2) * 8) % w, nb = (pat_frame * 8) % w;

					if (pat_frame < 2) {
						pattern_cols(b, fmt, w, h, pat_frame, 0, w);
					} else {
						pattern_cols(b, fmt, w, h, pat_frame, ob, ob + 16);
						pattern_cols(b, fmt, w, h, pat_frame, nb, nb + 16);
					}
					qf.fb_id = b->fb_id;
					qf.index = pat_frame++;
					depth = 1;
				}
			} else {
				have = q_pop(&qf, &depth);
				if (have) {
					const AVDRMFrameDescriptor *desc =
						(const AVDRMFrameDescriptor *)qf.f->data[0];

					w = qf.f->width;
					h = qf.f->height;
					qf.fb_id = fb_for_desc(&K, desc, w, h);
					if (!qf.fb_id) {
						av_frame_free(&qf.f);
						break;
					}
				}
			}
			if (have) {
				starved = false;
				if (o.pattern && o.commit_delay_us && !first)
					usleep(o.commit_delay_us);
				S.t_commit = now_s();
				S.depth = depth;
				S.in_flight = qf;
				if (kms_commit(&K, qf.fb_id, w, h, enc, range, NULL)) {
					av_frame_free(&S.in_flight.f);
					break;
				}
				S.busy = true;
				first = false;
			} else {
				pthread_mutex_lock(&Q.lock);
				eos = Q.eos && !Q.count;
				pthread_mutex_unlock(&Q.lock);
				if (o.pattern)
					eos = true;
				if (eos) {
					if (!t_end_hold)
						t_end_hold = now_s() + o.hold;
					if (now_s() >= t_end_hold)
						break;
				} else if (!first && !starved) {
					underruns++;	/* flip came, nothing to show */
					starved = true;
				}
			}
		}
		if (poll(pfd, 2, eos ? 100 : 1000) < 0 && errno != EINTR)
			break;
		if (pfd[0].revents & POLLIN)
			drmHandleEvent(K.fd, &ev);
		if (pfd[1].revents & POLLIN && read(Q.efd, &junk, sizeof(junk)) < 0)
			perror("eventfd read");
	}
	quit = 1;
	pthread_mutex_lock(&Q.lock);
	pthread_cond_broadcast(&Q.space);
	pthread_mutex_unlock(&Q.lock);
	while (S.busy && poll(&(struct pollfd){ K.fd, POLLIN, 0 }, 1, 200) > 0)
		drmHandleEvent(K.fd, &ev);
	if (!o.pattern) {
		struct qframe qf;
		int depth;

		while (q_pop(&qf, &depth))
			av_frame_free(&qf.f);
		pthread_join(thr, NULL);
		while (q_pop(&qf, &depth))
			av_frame_free(&qf.f);
	}
	report(o.pattern ? NULL : &d);
	/* the planes keep scanning out the last fb until the next client/fbcon */
	av_frame_free(&S.on_screen.f);
	av_frame_free(&S.in_flight.f);
	for (int i = 0; i < nfbs; i++) {
		drmModeRmFB(K.fd, fbs[i].fb_id);
		drmCloseBufferHandle(K.fd, fbs[i].handle);
	}
	if (!o.pattern) {
		avcodec_free_context(&d.ctx);
		avformat_close_input(&d.fmt);
		av_buffer_unref(&d.hw);
	}
	close(K.fd);
	return 0;
}
