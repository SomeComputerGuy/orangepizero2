# avs2dec: AVS2 test decoder for the cedrus V4L2 stateless AVS2 uAPI.
#
# The uAPI headers come from the patched kernel tree (the AVS2 patches of
# patch/kernel/archive/sunxi-7.3/patches.media/h616-vdec), installed with
#   make -C <linux> ARCH=arm64 headers_install INSTALL_HDR_PATH=<dir>
# and passed as UAPI=<dir>/include.
#
#   make UAPI=... CROSS_COMPILE=aarch64-linux-gnu-   # board binary
#   make UAPI=... host                               # host binary, -p only

UAPI ?= ../../kernel-check/avs2-uapi/include
CROSS_COMPILE ?= aarch64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -isystem $(UAPI)

all: avs2dec

avs2dec: avs2dec.c avs2_wq_tables.h
	$(CC) $(CFLAGS) -o $@ avs2dec.c

host: avs2dec-host

avs2dec-host: avs2dec.c avs2_wq_tables.h
	gcc $(CFLAGS) -o $@ avs2dec.c

clean:
	rm -f avs2dec avs2dec-host

.PHONY: all host clean
