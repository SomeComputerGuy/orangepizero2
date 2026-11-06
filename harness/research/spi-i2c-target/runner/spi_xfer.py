#!/usr/bin/env python3
"""One full-duplex spidev transfer. Usage: spi_xfer.py <dev> <len> <txhex> [speed_hz]
Prints the received bytes as hex. Blocks until the transfer is done (on a target controller: until
the host clocks it, or the process is signalled)."""
import array, ctypes, fcntl, os, struct, sys

dev, n, txhex = sys.argv[1], int(sys.argv[2]), sys.argv[3]
speed = int(sys.argv[4]) if len(sys.argv) > 4 else 500000
tx = bytes.fromhex(txhex)
tx = (tx * (n // len(tx) + 1))[:n]
SPI_IOC_MESSAGE_1 = 0x40206b00
SPI_IOC_WR_MODE, SPI_IOC_WR_BITS, SPI_IOC_WR_MAX_SPEED = 0x40016b01, 0x40016b03, 0x40046b04
fd = os.open(dev, os.O_RDWR)
fcntl.ioctl(fd, SPI_IOC_WR_MODE, struct.pack("B", 0))
fcntl.ioctl(fd, SPI_IOC_WR_BITS, struct.pack("B", 8))
fcntl.ioctl(fd, SPI_IOC_WR_MAX_SPEED, struct.pack("I", speed))
txb = ctypes.create_string_buffer(tx, n)
rxb = ctypes.create_string_buffer(n)
xfer = struct.pack("QQIIHBBBBBB", ctypes.addressof(txb), ctypes.addressof(rxb), n, speed, 0, 8, 0, 0, 0, 0, 0)
buf = array.array("B", xfer)
fcntl.ioctl(fd, SPI_IOC_MESSAGE_1, buf, True)
os.close(fd)
print(rxb.raw.hex())
