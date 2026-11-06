#!/usr/bin/env python3
"""Print the I2C_FUNCS word of /dev/i2c-<bus> in hex (I2C_FUNC_SLAVE = 0x20)."""
import array, fcntl, os, sys
fd = os.open("/dev/i2c-%s" % sys.argv[1], os.O_RDWR)
f = array.array("L", [0]); fcntl.ioctl(fd, 0x0705, f, True); os.close(fd)
print("0x%x" % f[0])
