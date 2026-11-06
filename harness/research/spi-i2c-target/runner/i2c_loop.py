#!/usr/bin/env python3
"""I2C host side of the loopback: write a pattern into the slave-24c02 at <addr> on <bus>, read it back.
Usage: i2c_loop.py <bus> <addr> <nbytes>   -> prints 'OK <hex>' or 'MISMATCH wrote <hex> read <hex>'"""
import fcntl, os, sys, time

bus, addr, n = int(sys.argv[1]), int(sys.argv[2], 0), int(sys.argv[3])
I2C_SLAVE = 0x0703
pat = bytes((0xa5 + 7 * i) & 0xff for i in range(n))
fd = os.open("/dev/i2c-%d" % bus, os.O_RDWR)
fcntl.ioctl(fd, I2C_SLAVE, addr)
os.write(fd, b"\x00" + pat)          # pointer 0 + data (one write transaction)
time.sleep(0.01)
os.write(fd, b"\x00")                # set the pointer
rd = os.read(fd, n)                  # separate read transaction (STOP in between)
os.close(fd)
print(("OK " + rd.hex()) if rd == pat else ("MISMATCH wrote %s read %s" % (pat.hex(), rd.hex())))
sys.exit(0 if rd == pat else 1)
