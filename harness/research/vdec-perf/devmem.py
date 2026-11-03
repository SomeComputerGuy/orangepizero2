#!/usr/bin/python3 -I
# devmem.py ADDR [VALUE] : 32-bit /dev/mem read (prints 0x%08X) or write, via a uint32 memoryview (word access)
import mmap, os, sys
a = int(sys.argv[1], 0); pg = a & ~0xfff; idx = (a - pg) // 4
fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 4096, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=pg)
v = memoryview(m).cast('I')
if len(sys.argv) > 2:
    v[idx] = int(sys.argv[2], 0) & 0xffffffff
else:
    print('0x%08X' % v[idx])
