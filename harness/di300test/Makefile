# di300test: test client for the sun50i-di300 V4L2 deinterlacer.
CROSS_COMPILE ?= aarch64-linux-gnu-
CC := $(CROSS_COMPILE)gcc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Wno-unused-parameter

all: di300test

di300test: di300test.c
	$(CC) $(CFLAGS) -static -o $@ di300test.c

clean:
	rm -f di300test

.PHONY: all clean
