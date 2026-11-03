# jpegtest: test client for the cedrus V4L2 JPEG decoder.
CROSS_COMPILE ?= aarch64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter

all: jpegtest

jpegtest: jpegtest.c
	$(CC) $(CFLAGS) -static -o $@ jpegtest.c

clean:
	rm -f jpegtest

.PHONY: all clean
