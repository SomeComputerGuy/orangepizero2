// SPDX-License-Identifier: GPL-2.0
/*
 * h264enc-test: encode raw NV12 frames with a V4L2 stateless H.264 encoder
 * (Paul Kocialkowski's 2026-05 encode uAPI: V4L2_CID_STATELESS_H264_SPS /
 * _PPS / _ENCODE_PARAMS in a request per picture, V4L2_PIX_FMT_H264_SLICE
 * on the CAPTURE queue), as the cedrus encoder of the H616 implements it.
 *
 * Usage: h264enc-test -w W -h H -i in.nv12 -o out.h264 [-n frames] [-q qp]
 *        [-g gop] [-r fps] [-d /dev/videoN] [-m /dev/mediaN] [-P] [-v]
 *   -g 0 (default): every picture is an IDR picture; -g N: an IDR picture
 *   every N pictures, P pictures in between. -P: pic_order_cnt_type 2.
 *
 * Prints one line per picture and a final "RESULT ..." line; exits 0 when
 * every picture was encoded without error.
 */

#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>

#include <linux/media.h>
#include <linux/videodev2.h>

#define NBUF 2

struct buf {
	void *map;
	size_t len;
};

static int verbose;

static int xioctl(int fd, unsigned long req, void *arg)
{
	int ret;

	do {
		ret = ioctl(fd, req, arg);
	} while (ret == -1 && errno == EINTR);

	return ret;
}

static int64_t now_us(void)
{
	struct timeval tv;

	gettimeofday(&tv, NULL);
	return (int64_t)tv.tv_sec * 1000000 + tv.tv_usec;
}

/* The encoder node: an M2M device whose first CAPTURE format is H264_SLICE. */
static int find_video(char *path, size_t len)
{
	int i;

	for (i = 0; i < 64; i++) {
		struct v4l2_capability cap;
		struct v4l2_fmtdesc fmt;
		int fd;

		snprintf(path, len, "/dev/video%d", i);
		fd = open(path, O_RDWR | O_NONBLOCK);
		if (fd < 0)
			continue;

		memset(&cap, 0, sizeof(cap));
		if (xioctl(fd, VIDIOC_QUERYCAP, &cap) ||
		    strcmp((char *)cap.driver, "cedrus") ||
		    !(cap.device_caps & V4L2_CAP_VIDEO_M2M)) {
			close(fd);
			continue;
		}

		memset(&fmt, 0, sizeof(fmt));
		fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		if (!xioctl(fd, VIDIOC_ENUM_FMT, &fmt) &&
		    fmt.pixelformat == V4L2_PIX_FMT_H264_SLICE) {
			close(fd);
			return 0;
		}

		close(fd);
	}

	return -1;
}

static int find_media(char *path, size_t len)
{
	int i;

	for (i = 0; i < 64; i++) {
		struct media_device_info info;
		int fd;

		snprintf(path, len, "/dev/media%d", i);
		fd = open(path, O_RDWR);
		if (fd < 0)
			continue;

		memset(&info, 0, sizeof(info));
		if (!xioctl(fd, MEDIA_IOC_DEVICE_INFO, &info) &&
		    !strcmp(info.driver, "cedrus")) {
			close(fd);
			return 0;
		}

		close(fd);
	}

	return -1;
}

static int set_ctrl(int fd, int req_fd, unsigned int id, int value)
{
	struct v4l2_ext_control ctrl = { .id = id, .value = value };
	struct v4l2_ext_controls ctrls = {
		.count = 1,
		.controls = &ctrl,
	};

	if (req_fd >= 0) {
		ctrls.which = V4L2_CTRL_WHICH_REQUEST_VAL;
		ctrls.request_fd = req_fd;
	}

	if (xioctl(fd, VIDIOC_S_EXT_CTRLS, &ctrls)) {
		fprintf(stderr, "S_EXT_CTRLS 0x%x: %s\n", id, strerror(errno));
		return -1;
	}

	return 0;
}

static int set_compound(int fd, int req_fd, unsigned int id, void *p,
			size_t size)
{
	struct v4l2_ext_control ctrl = { .id = id, .size = size, .ptr = p };
	struct v4l2_ext_controls ctrls = {
		.count = 1,
		.controls = &ctrl,
	};

	if (req_fd >= 0) {
		ctrls.which = V4L2_CTRL_WHICH_REQUEST_VAL;
		ctrls.request_fd = req_fd;
	}

	if (xioctl(fd, VIDIOC_S_EXT_CTRLS, &ctrls)) {
		fprintf(stderr, "S_EXT_CTRLS 0x%x (compound): %s\n", id,
			strerror(errno));
		return -1;
	}

	return 0;
}

static int get_request_encode(int fd, int req_fd,
			      struct v4l2_ctrl_h264_encode_params *encode)
{
	struct v4l2_ext_control ctrl = {
		.id = V4L2_CID_STATELESS_H264_ENCODE_PARAMS,
		.size = sizeof(*encode),
		.ptr = encode,
	};
	struct v4l2_ext_controls ctrls = {
		.which = V4L2_CTRL_WHICH_REQUEST_VAL,
		.request_fd = req_fd,
		.count = 1,
		.controls = &ctrl,
	};

	return xioctl(fd, VIDIOC_G_EXT_CTRLS, &ctrls);
}

static int setup_queue(int fd, enum v4l2_buf_type type, struct buf *bufs)
{
	struct v4l2_requestbuffers req = {
		.count = NBUF,
		.type = type,
		.memory = V4L2_MEMORY_MMAP,
	};
	unsigned int i;

	if (xioctl(fd, VIDIOC_REQBUFS, &req)) {
		fprintf(stderr, "REQBUFS type %d: %s\n", type, strerror(errno));
		return -1;
	}

	if (req.count < NBUF) {
		fprintf(stderr, "REQBUFS type %d: only %u buffers\n", type,
			req.count);
		return -1;
	}

	for (i = 0; i < NBUF; i++) {
		struct v4l2_buffer b = {
			.index = i,
			.type = type,
			.memory = V4L2_MEMORY_MMAP,
		};

		if (xioctl(fd, VIDIOC_QUERYBUF, &b)) {
			fprintf(stderr, "QUERYBUF: %s\n", strerror(errno));
			return -1;
		}

		bufs[i].len = b.length;
		bufs[i].map = mmap(NULL, b.length, PROT_READ | PROT_WRITE,
				   MAP_SHARED, fd, b.m.offset);
		if (bufs[i].map == MAP_FAILED) {
			fprintf(stderr, "mmap: %s\n", strerror(errno));
			return -1;
		}
	}

	return 0;
}

static const char *slice_type_name(unsigned int type)
{
	switch (type) {
	case V4L2_H264_SLICE_TYPE_P:
		return "P";
	case V4L2_H264_SLICE_TYPE_I:
		return "I";
	default:
		return "?";
	}
}

int main(int argc, char **argv)
{
	char video_path[32] = "", media_path[32] = "";
	const char *in_path = NULL, *out_path = NULL;
	unsigned int width = 0, height = 0, frames = 0, gop = 0, qp = 26;
	unsigned int fps = 30, poc_type = 0;
	struct v4l2_format out_fmt, cap_fmt;
	struct v4l2_streamparm parm;
	struct buf out_bufs[NBUF], cap_bufs[NBUF];
	struct v4l2_ctrl_h264_sps sps;
	struct v4l2_ctrl_h264_pps pps;
	struct v4l2_ctrl_h264_encode_params encode;
	int video_fd, media_fd, req_fd[NBUF], in_fd, out_fd;
	enum v4l2_buf_type type;
	unsigned int i, n, frame_num = 0, poc = 0, idr_pic_id = 0;
	unsigned int keyframes = 0, errors = 0;
	unsigned long long total_bytes = 0;
	int64_t t_start, t_q, t_sum = 0, t_max = 0, t_total;
	size_t frame_size, row;
	uint8_t *frame;
	int opt, ret = 0;

	while ((opt = getopt(argc, argv, "w:h:i:o:n:q:g:r:d:m:Pv")) != -1) {
		switch (opt) {
		case 'w':
			width = atoi(optarg);
			break;
		case 'h':
			height = atoi(optarg);
			break;
		case 'i':
			in_path = optarg;
			break;
		case 'o':
			out_path = optarg;
			break;
		case 'n':
			frames = atoi(optarg);
			break;
		case 'q':
			qp = atoi(optarg);
			break;
		case 'g':
			gop = atoi(optarg);
			break;
		case 'r':
			fps = atoi(optarg);
			break;
		case 'd':
			snprintf(video_path, sizeof(video_path), "%s", optarg);
			break;
		case 'm':
			snprintf(media_path, sizeof(media_path), "%s", optarg);
			break;
		case 'P':
			poc_type = 2;
			break;
		case 'v':
			verbose = 1;
			break;
		default:
			fprintf(stderr, "usage: %s -w W -h H -i in.nv12 -o out.h264 [-n frames] [-q qp] [-g gop] [-r fps] [-d video] [-m media] [-P] [-v]\n",
				argv[0]);
			return 2;
		}
	}

	if (!width || !height || !in_path || !out_path) {
		fprintf(stderr, "missing -w/-h/-i/-o\n");
		return 2;
	}

	if (!video_path[0] && find_video(video_path, sizeof(video_path))) {
		fprintf(stderr, "no cedrus encoder video device\n");
		return 3;
	}

	if (!media_path[0] && find_media(media_path, sizeof(media_path))) {
		fprintf(stderr, "no cedrus media device\n");
		return 3;
	}

	printf("device %s media %s\n", video_path, media_path);

	video_fd = open(video_path, O_RDWR | O_NONBLOCK);
	media_fd = open(media_path, O_RDWR);
	if (video_fd < 0 || media_fd < 0) {
		fprintf(stderr, "open: %s\n", strerror(errno));
		return 3;
	}

	in_fd = open(in_path, O_RDONLY);
	if (in_fd < 0) {
		fprintf(stderr, "open %s: %s\n", in_path, strerror(errno));
		return 3;
	}

	out_fd = open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (out_fd < 0) {
		fprintf(stderr, "open %s: %s\n", out_path, strerror(errno));
		return 3;
	}

	/* Formats: the raw picture first, the coded format follows it. */

	memset(&out_fmt, 0, sizeof(out_fmt));
	out_fmt.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	out_fmt.fmt.pix.width = width;
	out_fmt.fmt.pix.height = height;
	out_fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_NV12;
	out_fmt.fmt.pix.field = V4L2_FIELD_NONE;
	if (xioctl(video_fd, VIDIOC_S_FMT, &out_fmt)) {
		fprintf(stderr, "S_FMT OUTPUT: %s\n", strerror(errno));
		return 4;
	}

	if (out_fmt.fmt.pix.width != width ||
	    out_fmt.fmt.pix.height != height ||
	    out_fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_NV12) {
		fprintf(stderr, "S_FMT OUTPUT changed the format: %ux%u %.4s\n",
			out_fmt.fmt.pix.width, out_fmt.fmt.pix.height,
			(char *)&out_fmt.fmt.pix.pixelformat);
		return 4;
	}

	memset(&cap_fmt, 0, sizeof(cap_fmt));
	cap_fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	cap_fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_H264_SLICE;
	if (xioctl(video_fd, VIDIOC_S_FMT, &cap_fmt)) {
		fprintf(stderr, "S_FMT CAPTURE: %s\n", strerror(errno));
		return 4;
	}

	printf("output %ux%u stride %u size %u, capture %ux%u %.4s size %u\n",
	       out_fmt.fmt.pix.width, out_fmt.fmt.pix.height,
	       out_fmt.fmt.pix.bytesperline, out_fmt.fmt.pix.sizeimage,
	       cap_fmt.fmt.pix.width, cap_fmt.fmt.pix.height,
	       (char *)&cap_fmt.fmt.pix.pixelformat,
	       cap_fmt.fmt.pix.sizeimage);

	memset(&parm, 0, sizeof(parm));
	parm.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	parm.parm.output.timeperframe.numerator = 1;
	parm.parm.output.timeperframe.denominator = fps;
	if (xioctl(video_fd, VIDIOC_S_PARM, &parm))
		fprintf(stderr, "S_PARM: %s (ignored)\n", strerror(errno));

	/* Controls that stay for the stream. */

	if (set_ctrl(video_fd, -1, V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE, 0) ||
	    set_ctrl(video_fd, -1, V4L2_CID_MPEG_VIDEO_H264_I_FRAME_QP, qp) ||
	    set_ctrl(video_fd, -1, V4L2_CID_MPEG_VIDEO_H264_P_FRAME_QP, qp) ||
	    set_ctrl(video_fd, -1, V4L2_CID_MPEG_VIDEO_H264_MIN_QP, 0) ||
	    set_ctrl(video_fd, -1, V4L2_CID_MPEG_VIDEO_H264_MAX_QP, 51) ||
	    set_ctrl(video_fd, -1, V4L2_CID_MPEG_VIDEO_PREPEND_SPSPPS_TO_IDR, 1) ||
	    set_ctrl(video_fd, -1, V4L2_CID_STATELESS_H264_START_CODE,
		     V4L2_STATELESS_H264_START_CODE_ANNEX_B))
		return 4;

	/* Buffers. */

	if (setup_queue(video_fd, V4L2_BUF_TYPE_VIDEO_OUTPUT, out_bufs) ||
	    setup_queue(video_fd, V4L2_BUF_TYPE_VIDEO_CAPTURE, cap_bufs))
		return 4;

	for (i = 0; i < NBUF; i++) {
		if (xioctl(media_fd, MEDIA_IOC_REQUEST_ALLOC, &req_fd[i])) {
			fprintf(stderr, "REQUEST_ALLOC: %s\n", strerror(errno));
			return 4;
		}
	}

	type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	if (xioctl(video_fd, VIDIOC_STREAMON, &type)) {
		fprintf(stderr, "STREAMON OUTPUT: %s\n", strerror(errno));
		return 4;
	}

	type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	if (xioctl(video_fd, VIDIOC_STREAMON, &type)) {
		fprintf(stderr, "STREAMON CAPTURE: %s\n", strerror(errno));
		return 4;
	}

	/* Stream parameters: constrained baseline, one reference. */

	memset(&sps, 0, sizeof(sps));
	sps.profile_idc = 66;
	sps.constraint_set_flags = V4L2_H264_SPS_CONSTRAINT_SET0_FLAG |
				   V4L2_H264_SPS_CONSTRAINT_SET1_FLAG;
	sps.level_idc = 40;
	sps.chroma_format_idc = 1;
	sps.log2_max_frame_num_minus4 = 4;
	sps.pic_order_cnt_type = poc_type;
	sps.log2_max_pic_order_cnt_lsb_minus4 = 4;
	sps.max_num_ref_frames = 1;
	sps.pic_width_in_mbs_minus1 = (width + 15) / 16 - 1;
	sps.pic_height_in_map_units_minus1 = (height + 15) / 16 - 1;
	sps.flags = V4L2_H264_SPS_FLAG_FRAME_MBS_ONLY |
		    V4L2_H264_SPS_FLAG_DIRECT_8X8_INFERENCE;

	memset(&pps, 0, sizeof(pps));
	pps.pic_init_qp_minus26 = (int)qp - 26;
	pps.flags = V4L2_H264_PPS_FLAG_DEBLOCKING_FILTER_CONTROL_PRESENT;

	frame_size = (size_t)width * height * 3 / 2;
	frame = malloc(frame_size);
	if (!frame)
		return 4;

	t_start = now_us();

	for (n = 0; !frames || n < frames; n++) {
		struct v4l2_buffer out_buf, cap_buf;
		struct pollfd pfd = { .fd = video_fd, .events = POLLIN };
		unsigned int idx = n % NBUF;
		uint8_t *dst = out_bufs[idx].map;
		int is_idr, is_p;
		ssize_t got;
		int64_t t;

		got = read(in_fd, frame, frame_size);
		if (got == 0)
			break;
		if (got != (ssize_t)frame_size) {
			fprintf(stderr, "short read at frame %u\n", n);
			break;
		}

		/* NV12 into the stride of the format: luma, then chroma. */
		for (row = 0; row < height; row++)
			memcpy(dst + row * out_fmt.fmt.pix.bytesperline,
			       frame + row * width, width);
		dst += (size_t)out_fmt.fmt.pix.bytesperline * height;
		for (row = 0; row < height / 2; row++)
			memcpy(dst + row * out_fmt.fmt.pix.bytesperline,
			       frame + (size_t)width * height + row * width,
			       width);

		/* Picture type. */
		is_idr = !gop || (n % gop) == 0;
		is_p = !is_idr;

		if (is_idr) {
			frame_num = 0;
			poc = 0;
		}

		memset(&encode, 0, sizeof(encode));
		encode.nal_ref_idc = is_idr ? 3 : 2;
		encode.slice_type = is_p ? V4L2_H264_SLICE_TYPE_P :
					   V4L2_H264_SLICE_TYPE_I;
		encode.frame_num = frame_num;
		encode.idr_pic_id = idr_pic_id;
		encode.pic_order_cnt_lsb = poc;
		if (is_idr)
			encode.flags |= V4L2_H264_ENCODE_FLAG_IDR_PIC;

		/* The request carries this picture's parameters. */
		if (set_compound(video_fd, req_fd[idx],
				 V4L2_CID_STATELESS_H264_SPS, &sps,
				 sizeof(sps)) ||
		    set_compound(video_fd, req_fd[idx],
				 V4L2_CID_STATELESS_H264_PPS, &pps,
				 sizeof(pps)) ||
		    set_compound(video_fd, req_fd[idx],
				 V4L2_CID_STATELESS_H264_ENCODE_PARAMS, &encode,
				 sizeof(encode))) {
			ret = 5;
			break;
		}

		memset(&cap_buf, 0, sizeof(cap_buf));
		cap_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		cap_buf.memory = V4L2_MEMORY_MMAP;
		cap_buf.index = idx;
		if (xioctl(video_fd, VIDIOC_QBUF, &cap_buf)) {
			fprintf(stderr, "QBUF CAPTURE: %s\n", strerror(errno));
			ret = 5;
			break;
		}

		memset(&out_buf, 0, sizeof(out_buf));
		out_buf.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
		out_buf.memory = V4L2_MEMORY_MMAP;
		out_buf.index = idx;
		out_buf.bytesused = out_fmt.fmt.pix.sizeimage;
		out_buf.field = V4L2_FIELD_NONE;
		out_buf.flags = V4L2_BUF_FLAG_REQUEST_FD;
		out_buf.request_fd = req_fd[idx];
		out_buf.timestamp.tv_sec = n;
		out_buf.timestamp.tv_usec = 0;
		if (xioctl(video_fd, VIDIOC_QBUF, &out_buf)) {
			fprintf(stderr, "QBUF OUTPUT: %s\n", strerror(errno));
			ret = 5;
			break;
		}

		t_q = now_us();
		if (xioctl(req_fd[idx], MEDIA_REQUEST_IOC_QUEUE, NULL)) {
			fprintf(stderr, "REQUEST_QUEUE: %s\n", strerror(errno));
			ret = 5;
			break;
		}

		/* One picture at a time: wait for the coded picture. */
		if (poll(&pfd, 1, 2000) <= 0) {
			fprintf(stderr, "frame %u: timeout waiting for the encoder\n",
				n);
			ret = 6;
			break;
		}

		memset(&cap_buf, 0, sizeof(cap_buf));
		cap_buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
		cap_buf.memory = V4L2_MEMORY_MMAP;
		if (xioctl(video_fd, VIDIOC_DQBUF, &cap_buf)) {
			fprintf(stderr, "DQBUF CAPTURE: %s\n", strerror(errno));
			ret = 6;
			break;
		}
		t = now_us() - t_q;
		t_sum += t;
		if (t > t_max)
			t_max = t;

		memset(&out_buf, 0, sizeof(out_buf));
		out_buf.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
		out_buf.memory = V4L2_MEMORY_MMAP;
		if (xioctl(video_fd, VIDIOC_DQBUF, &out_buf)) {
			fprintf(stderr, "DQBUF OUTPUT: %s\n", strerror(errno));
			ret = 6;
			break;
		}

		/* The parameters the encoder actually used. */
		if (!get_request_encode(video_fd, req_fd[idx], &encode) &&
		    verbose)
			printf("  used: type %s frame_num %u poc %u qp_delta %d\n",
			       slice_type_name(encode.slice_type),
			       encode.frame_num, encode.pic_order_cnt_lsb,
			       encode.slice_qp_delta);

		if (cap_buf.flags & V4L2_BUF_FLAG_ERROR || !cap_buf.bytesused) {
			errors++;
			printf("frame %u: ERROR flags 0x%x bytes %u\n", n,
			       cap_buf.flags, cap_buf.bytesused);
		} else {
			if (write(out_fd, cap_bufs[cap_buf.index].map,
				  cap_buf.bytesused) != (ssize_t)cap_buf.bytesused) {
				fprintf(stderr, "write: %s\n", strerror(errno));
				ret = 6;
				break;
			}
			total_bytes += cap_buf.bytesused;
			if (cap_buf.flags & V4L2_BUF_FLAG_KEYFRAME)
				keyframes++;
			printf("frame %u: %s%s %u bytes, %lld us%s\n", n,
			       is_p ? "P" : "I", is_idr ? " IDR" : "",
			       cap_buf.bytesused, (long long)t,
			       cap_buf.flags & V4L2_BUF_FLAG_KEYFRAME ?
			       " keyframe" : "");
		}

		if (xioctl(req_fd[idx], MEDIA_REQUEST_IOC_REINIT, NULL)) {
			fprintf(stderr, "REQUEST_REINIT: %s\n", strerror(errno));
			ret = 6;
			break;
		}

		/* Every picture is a reference: frame_num and POC advance. */
		frame_num = (frame_num + 1) & 0xff;
		poc = (poc + 2) & 0xff;
		if (is_idr)
			idr_pic_id ^= 1;
	}

	type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	xioctl(video_fd, VIDIOC_STREAMOFF, &type);
	type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	xioctl(video_fd, VIDIOC_STREAMOFF, &type);

	t_total = now_us() - t_start;
	printf("RESULT frames=%u bytes=%llu keyframes=%u errors=%u ret=%d avg_us=%lld max_us=%lld fps=%.1f\n",
	       n, total_bytes, keyframes, errors, ret,
	       n ? (long long)(t_sum / n) : 0LL, (long long)t_max,
	       t_total > 0 ? n * 1e6 / t_total : 0.0);

	close(out_fd);
	close(in_fd);
	close(media_fd);
	close(video_fd);
	free(frame);

	if (ret)
		return ret;

	return errors ? 1 : 0;
}
