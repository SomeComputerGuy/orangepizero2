/* SPDX-License-Identifier: MIT */
/* kbtrace record format: file = "KBTRACE1" then records {kbt_rec, header, payload}. */
#pragma once
#include <stdint.h>
#define KBT_MAGIC "KBTRACE1"
enum { KBT_OPEN = 1, KBT_IOCTL_PRE, KBT_IOCTL_POST, KBT_MMAP, KBT_MUNMAP, KBT_MEM, KBT_SUBMIT, KBT_EVENT,
       KBT_MARKER, KBT_SNAP_BEGIN, KBT_SNAP_END, KBT_CLOSE, KBT_GPUPROPS, KBT_SOFT };
struct kbt_rec { uint32_t type, len; uint64_t seq; uint64_t ns; };
struct kbt_ioctl { int32_t fd; uint32_t req; int32_t ret; int32_t err; };
struct kbt_mmap { uint64_t addr, len; int32_t prot, flags, fd, pad; uint64_t off, ret, gpu; };
struct kbt_munmap { uint64_t addr, len, gpu; };
struct kbt_mem { uint64_t gpu, cpu, len; };
struct kbt_submit { uint32_t nr, stride; };
struct kbt_soft { uint64_t jc; uint32_t core_req; uint8_t atom_nr, nr_extres; uint16_t pad; };  /* + up to 512 bytes at jc */
