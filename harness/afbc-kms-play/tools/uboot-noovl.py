#!/usr/bin/env python3
"""Interrupt U-Boot on the Zero2 (writes /dev/ttyOPIZ2 only, reads harness/serial.log)
and boot the installed kernel with armbianEnv.txt settings but WITHOUT DT overlays.
Recovery helper for an overlay that hangs the kernel."""
import os, re, sys, time
LOG = '/home/aruni/orangepizero2/harness/serial.log'
PORT = '/dev/ttyOPIZ2'
def size(): return os.path.getsize(LOG)
def read_from(off):
    with open(LOG, 'rb') as f:
        f.seek(off); return f.read().decode('utf-8', 'replace')
def wait(pat, off, timeout, poll=0.05):
    end = time.time() + timeout
    while time.time() < end:
        if re.search(pat, read_from(off)): return True
        time.sleep(poll)
    return False
fd = os.open(PORT, os.O_WRONLY | os.O_NOCTTY)
def w(b): os.write(fd, b if isinstance(b, bytes) else b.encode())
off = size()
print('waiting for autoboot prompt', flush=True)
if 'now' not in sys.argv and not wait(r'Hit any key to stop autoboot|U-Boot 20\d\d', off, 240):
    print('no U-Boot seen'); sys.exit(2)
for _ in range(60):
    w(b'\x03 ')
    if wait(r'=> ', off, 0.1): break
else:
    print('no prompt'); sys.exit(3)
time.sleep(0.3); w(b'\x03'); time.sleep(0.3)
cmds = [
    'setenv load_addr 0x45000000',
    'load mmc 0 ${load_addr} /boot/armbianEnv.txt',
    'env import -t ${load_addr} ${filesize}',
    'setenv bootargs "root=${rootdev} rootwait rootfstype=${rootfstype} console=ttyS0,115200 console=tty1 consoleblank=0 loglevel=1 usb-storage.quirks=${usbstoragequirks} ${extraargs}"',
    'load mmc 0 ${fdt_addr_r} /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb',
    'load mmc 0 ${ramdisk_addr_r} /boot/uInitrd',
    'load mmc 0 ${kernel_addr_r} /boot/Image',
    'booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}',
]
for c in cmds:
    off = size(); w(c + '\r'); print('>', c, flush=True)
    if c.startswith('booti'):
        ok = wait(r'Starting kernel', off, 30); print('kernel started' if ok else 'booti: no start'); break
    if not wait(r'=> ', off, 20): print('timeout after', c); sys.exit(4)
    time.sleep(0.2)
