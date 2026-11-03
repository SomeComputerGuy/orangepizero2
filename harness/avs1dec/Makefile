# avs1dec: AVS1/AVS+ test decoder for the cedrus V4L2 stateless AVS uAPI.
#
# The uAPI headers come from the patched kernel tree, installed with
#   make -C <linux> ARCH=arm64 headers_install INSTALL_HDR_PATH=<dir>
# and passed as UAPI=<dir>/include.
#
#   make UAPI=... CROSS_COMPILE=aarch64-linux-gnu-   # static board binary
#   make UAPI=... host                               # host binary, --dry-run

UAPI ?= /tmp/avs-hdr/include
CROSS_COMPILE ?= aarch64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter -isystem $(UAPI)

all: avs1dec

avs1dec: avs1dec.c
	$(CC) $(CFLAGS) -static -o $@ avs1dec.c

host: avs1dec-host

avs1dec-host: avs1dec.c
	gcc $(CFLAGS) -o $@ avs1dec.c

clean:
	rm -f avs1dec avs1dec-host

.PHONY: all host clean
