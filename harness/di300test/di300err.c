// SPDX-License-Identifier: MIT
/*
 * di300err: error-path checks for the sun50i-di300 mem2mem driver.
 * Streams NV12 720x576 in field mode and checks the
 * V4L2_CID_DEINTERLACING_MODE rules while streaming (items by name): a
 * change of output rate, or to TNR-only, returns EBUSY; a change of
 * method at the same rate is accepted and the control is not grabbed.
 * The formats are locked (EBUSY). Then stops both queues with jobs still
 * queued and checks that every buffer comes back.
 * Usage: di300err [/dev/videoN]
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <linux/videodev2.h>

#define W 720
#define H 576
#define N 4

static int fd, fails;

static void check(const char *what, int ok)
{
	printf("%-50s %s\n", what, ok ? "ok" : "FAIL");
	fails += !ok;
}

/* menu index of a V4L2_CID_DEINTERLACING_MODE item, -1 if absent */
static int mode_index(const char *name)
{
	struct v4l2_queryctrl q = { .id = V4L2_CID_DEINTERLACING_MODE };

	if (ioctl(fd, VIDIOC_QUERYCTRL, &q))
		return -1;
	for (int i = q.minimum; i <= q.maximum; i++) {
		struct v4l2_querymenu m = { .id = q.id, .index = i };

		if (!ioctl(fd, VIDIOC_QUERYMENU, &m) && !strcmp((char *)m.name, name))
			return i;
	}
	return -1;
}

/* set a mode by name, return 0 or errno */
static int set_mode(const char *name)
{
	struct v4l2_control c = { .id = V4L2_CID_DEINTERLACING_MODE, .value = mode_index(name) };

	if (c.value < 0)
		return ENOENT;
	return ioctl(fd, VIDIOC_S_CTRL, &c) ? errno : 0;
}

static int get_mode(void)
{
	struct v4l2_control c = { .id = V4L2_CID_DEINTERLACING_MODE };

	return ioctl(fd, VIDIOC_G_CTRL, &c) ? -1 : c.value;
}

static int qbuf(int type, int i)
{
	struct v4l2_buffer b = { .type = type, .memory = V4L2_MEMORY_MMAP, .index = i };

	if (type == V4L2_BUF_TYPE_VIDEO_OUTPUT)
		b.bytesused = W * H * 3 / 2;
	return ioctl(fd, VIDIOC_QBUF, &b);
}

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "/dev/video1";
	int types[2] = { V4L2_BUF_TYPE_VIDEO_OUTPUT, V4L2_BUF_TYPE_VIDEO_CAPTURE };
	struct v4l2_queryctrl q = { .id = V4L2_CID_DEINTERLACING_MODE };
	struct v4l2_format f;
	int i, t, r, e;

	fd = open(dev, O_RDWR | O_NONBLOCK);
	if (fd < 0) {
		perror(dev);
		return 2;
	}
	check("set \"Motion Adaptive, Field Rate\" before streaming",
	      !set_mode("Motion Adaptive, Field Rate"));
	for (t = 0; t < 2; t++) {
		struct v4l2_requestbuffers rb = { .count = N, .type = types[t], .memory = V4L2_MEMORY_MMAP };

		memset(&f, 0, sizeof(f));
		f.type = types[t];
		f.fmt.pix.width = W;
		f.fmt.pix.height = H;
		f.fmt.pix.pixelformat = V4L2_PIX_FMT_NV12;
		f.fmt.pix.field = t ? V4L2_FIELD_NONE : V4L2_FIELD_INTERLACED_TB;
		if (ioctl(fd, VIDIOC_S_FMT, &f) || ioctl(fd, VIDIOC_REQBUFS, &rb) || rb.count < N) {
			perror("setup");
			return 2;
		}
		for (i = 0; i < N; i++) {
			struct v4l2_buffer b = { .type = types[t], .memory = V4L2_MEMORY_MMAP, .index = i };
			void *p;

			ioctl(fd, VIDIOC_QUERYBUF, &b);
			p = mmap(NULL, b.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, b.m.offset);
			if (p != MAP_FAILED)
				memset(p, 0x80, b.length);
		}
	}
	for (i = 0; i < N; i++)
		qbuf(V4L2_BUF_TYPE_VIDEO_CAPTURE, i);
	for (t = 0; t < 2; t++)
		ioctl(fd, VIDIOC_STREAMON, &types[t]);

	check("streaming: to \"Motion Adaptive, Frame Rate\" (rate): EBUSY",
	      set_mode("Motion Adaptive, Frame Rate") == EBUSY);
	check("streaming: to \"Bob, Frame Rate\" (rate): EBUSY", set_mode("Bob, Frame Rate") == EBUSY);
	check("streaming: to \"Weave\" (rate): EBUSY", set_mode("Weave") == EBUSY);
	check("streaming: to \"Noise Reduction Only\": EBUSY",
	      set_mode("Noise Reduction Only") == EBUSY);
	check("streaming: value unchanged after EBUSY",
	      get_mode() == mode_index("Motion Adaptive, Field Rate"));
	check("streaming: control not grabbed",
	      !ioctl(fd, VIDIOC_QUERYCTRL, &q) && !(q.flags & V4L2_CTRL_FLAG_GRABBED));
	check("streaming: to \"Bob, Field Rate\" (same rate): ok", !set_mode("Bob, Field Rate"));
	check("streaming: value is \"Bob, Field Rate\"", get_mode() == mode_index("Bob, Field Rate"));
	check("streaming: back to \"Motion Adaptive, Field Rate\": ok",
	      !set_mode("Motion Adaptive, Field Rate"));
	f.type = V4L2_BUF_TYPE_VIDEO_OUTPUT;
	ioctl(fd, VIDIOC_G_FMT, &f);
	f.fmt.pix.width = 352;
	r = ioctl(fd, VIDIOC_S_FMT, &f);
	e = errno;
	check("S_FMT(OUTPUT) while streaming: EBUSY", r < 0 && e == EBUSY);

	/* queue all sources, take one result, then stop with work pending */
	for (i = 0; i < N; i++)
		qbuf(V4L2_BUF_TYPE_VIDEO_OUTPUT, i);
	{
		struct pollfd p = { .fd = fd, .events = POLLIN };
		struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP };

		r = poll(&p, 1, 2000);
		check("first capture buffer within 2 s", r > 0 && !ioctl(fd, VIDIOC_DQBUF, &b));
	}
	r = ioctl(fd, VIDIOC_STREAMOFF, &types[0]);
	check("STREAMOFF(OUTPUT) with jobs pending returns", r == 0);
	r = ioctl(fd, VIDIOC_STREAMOFF, &types[1]);
	check("STREAMOFF(CAPTURE) returns", r == 0);
	for (t = 0; t < 2; t++) {
		int queued = 0;

		for (i = 0; i < N; i++) {
			struct v4l2_buffer b = { .type = types[t], .memory = V4L2_MEMORY_MMAP, .index = i };

			ioctl(fd, VIDIOC_QUERYBUF, &b);
			queued += !!(b.flags & (V4L2_BUF_FLAG_QUEUED | V4L2_BUF_FLAG_DONE));
		}
		check(t ? "no CAPTURE buffer left queued" : "no OUTPUT buffer left queued", !queued);
	}
	check("after STREAMOFF: to \"Motion Adaptive, Frame Rate\": ok",
	      !set_mode("Motion Adaptive, Frame Rate"));
	/* restart once to show the context is still usable */
	for (i = 0; i < N; i++)
		qbuf(V4L2_BUF_TYPE_VIDEO_CAPTURE, i);
	for (t = 0; t < 2; t++)
		ioctl(fd, VIDIOC_STREAMON, &types[t]);
	for (i = 0; i < N; i++)
		qbuf(V4L2_BUF_TYPE_VIDEO_OUTPUT, i);
	{
		struct pollfd p = { .fd = fd, .events = POLLIN };
		struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP };

		r = poll(&p, 1, 2000);
		check("restart: capture buffer within 2 s", r > 0 && !ioctl(fd, VIDIOC_DQBUF, &b));
	}
	/* frame-rate class: method changes allowed, field rate not */
	check("frame rate: to \"Bob, Frame Rate\": ok", !set_mode("Bob, Frame Rate"));
	check("frame rate: to \"Weave\": ok", !set_mode("Weave"));
	check("frame rate: to \"Motion Adaptive, Frame Rate\": ok",
	      !set_mode("Motion Adaptive, Frame Rate"));
	check("frame rate: to \"Bob, Field Rate\" (rate): EBUSY", set_mode("Bob, Field Rate") == EBUSY);
	check("frame rate: to \"Noise Reduction Only\": EBUSY", set_mode("Noise Reduction Only") == EBUSY);
	for (i = 0; i < 2; i++) {
		struct pollfd p = { .fd = fd, .events = POLLIN };
		struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP };

		r = poll(&p, 1, 2000);
		check("frame rate: capture buffer after the changes", r > 0 && !ioctl(fd, VIDIOC_DQBUF, &b));
	}
	for (t = 0; t < 2; t++)
		ioctl(fd, VIDIOC_STREAMOFF, &types[t]);
	close(fd);
	printf("%s\n", fails ? "FAIL" : "PASS");
	return !!fails;
}
