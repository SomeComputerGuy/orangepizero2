#!/usr/bin/env python3
"""Read Mali-G31 config via panfrost GET_PARAM ioctl and (optionally) raw MMIO via /dev/mem.
Usage: gpu-regs.py [--mmio]   (MMIO mode holds a runtime-PM ref via power/control=on, restores after)"""
import fcntl, mmap, os, struct, sys, time
NAMES = ["GPU_PROD_ID","GPU_REVISION","SHADER_PRESENT","TILER_PRESENT","L2_PRESENT","STACK_PRESENT",
 "AS_PRESENT","JS_PRESENT","L2_FEATURES","CORE_FEATURES","TILER_FEATURES","MEM_FEATURES","MMU_FEATURES",
 "THREAD_FEATURES","MAX_THREADS","THREAD_MAX_WORKGROUP_SZ","THREAD_MAX_BARRIER_SZ","COHERENCY_FEATURES",
 "TEXTURE_FEATURES0","TEXTURE_FEATURES1","TEXTURE_FEATURES2","TEXTURE_FEATURES3"]
IOC = 0xC0106444  # DRM_IOWR(0x40+0x04, struct drm_panfrost_get_param)
fd = os.open("/dev/dri/renderD128", os.O_RDWR)
for i, n in enumerate(NAMES):
    buf = bytearray(struct.pack("<IIQ", i, 0, 0))
    try:
        fcntl.ioctl(fd, IOC, buf); print(f"ioctl {n:26s} 0x{struct.unpack('<IIQ', buf)[2]:08x}")
    except OSError as e:
        print(f"ioctl {n:26s} err {e}")
os.close(fd)
if "--mmio" in sys.argv:
    ctl = "/sys/devices/platform/soc/1800000.gpu/power/control"
    old = open(ctl).read().strip()
    open(ctl, "w").write("on"); time.sleep(0.2)
    try:
        st = open("/sys/devices/platform/soc/1800000.gpu/power/runtime_status").read().strip()
        print("runtime_status during read:", st)
        if st == "active":
            m = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
            mm = mmap.mmap(m, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0x01800000)
            r = lambda o: struct.unpack_from("<I", mm, o)[0]
            for o, n in [(0x000,"GPU_ID"),(0x004,"L2_FEATURES"),(0x008,"CORE_FEATURES"),(0x00c,"TILER_FEATURES"),
                         (0x0a0,"THREAD_MAX_THREADS"),(0x0a4,"THREAD_MAX_WG_SIZE"),(0x0ac,"THREAD_FEATURES"),
                         (0x100,"SHADER_PRESENT_LO"),(0x104,"SHADER_PRESENT_HI"),(0x110,"TILER_PRESENT_LO"),
                         (0x120,"L2_PRESENT_LO"),(0x140,"SHADER_READY_LO"),(0x150,"TILER_READY_LO"),
                         (0x160,"L2_READY_LO")]:
                print(f"mmio  0x{o:03x} {n:22s} 0x{r(o):08x}")
            mm.close(); os.close(m)
    finally:
        open(ctl, "w").write(old)
        print("power/control restored to", old)
