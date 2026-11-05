// SPDX-License-Identifier: MIT
// For every control of a V4L2 device: G_EXT_CTRLS the current value, TRY_EXT_CTRLS it back,
// and print the result (v4l2-compliance stops at the first failure). Usage: ctrltry /dev/videoN
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <linux/videodev2.h>
int main(int argc, char **argv)
{
	int fd = open(argc > 1 ? argv[1] : "/dev/video0", O_RDWR);
	struct v4l2_query_ext_ctrl q = { .id = V4L2_CTRL_FLAG_NEXT_CTRL | V4L2_CTRL_FLAG_NEXT_COMPOUND };
	int bad = 0;
	if (fd < 0) { perror("open"); return 1; }
	while (!ioctl(fd, VIDIOC_QUERY_EXT_CTRL, &q)) {
		if (q.type != V4L2_CTRL_TYPE_CTRL_CLASS && !(q.flags & (V4L2_CTRL_FLAG_READ_ONLY | V4L2_CTRL_FLAG_WRITE_ONLY))) {
			struct v4l2_ext_control c = { .id = q.id };
			struct v4l2_ext_controls cs = { .which = V4L2_CTRL_WHICH_CUR_VAL, .count = 1, .controls = &c };
			void *buf = NULL;
			if (q.flags & V4L2_CTRL_FLAG_HAS_PAYLOAD) {
				c.size = q.elem_size * q.elems; buf = calloc(1, c.size); c.ptr = buf;
			}
			int g = ioctl(fd, VIDIOC_G_EXT_CTRLS, &cs) ? errno : 0;
			int t = ioctl(fd, VIDIOC_TRY_EXT_CTRLS, &cs) ? errno : 0;
			int s = ioctl(fd, VIDIOC_S_EXT_CTRLS, &cs) ? errno : 0;
			if (g || t || s) bad++;
			printf("%-8s %08x type 0x%04x %-45s G %d TRY %d S %d\n", (g || t || s) ? "FAIL" : "ok", q.id, q.type, q.name, g, t, s);
			free(buf);
		}
		q.id |= V4L2_CTRL_FLAG_NEXT_CTRL | V4L2_CTRL_FLAG_NEXT_COMPOUND;
	}
	printf("%d failing\n", bad);
	return 0;
}
