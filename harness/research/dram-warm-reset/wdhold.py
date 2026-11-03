#!/usr/bin/env python3
# Hardware-watchdog holder for the hot-OOM DRAM warm-reset test.
# usage: wdhold.py TIMEOUT HEAT_SECONDS MODE   (MODE: timed | oom)
#  timed: pet every 0.5 s for HEAT_SECONDS, then stop petting (fd kept open).
#  oom:   pet until the kernel logs "Out of memory" (or HEAT_SECONDS cap), then stop petting.
# Markers go to /dev/kmsg at crit level so they land on the serial console.
import fcntl, os, struct, sys, time, glob, mmap, ctypes
tmo, heat, mode = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
WDIOC_SETTIMEOUT, WDIOC_GETTIMEOUT, WDIOC_KEEPALIVE = 0xC0045706, 0x80045707, 0x80045705
open('/proc/self/oom_score_adj', 'w').write('-1000')
libc = ctypes.CDLL(None, use_errno=True); libc.mlockall(3)
try: os.sched_setscheduler(0, os.SCHED_FIFO, os.sched_param(50)); prio = 'fifo50'
except OSError:
    os.setpriority(os.PRIO_PROCESS, 0, -20); prio = 'nice-20'
kmsg = os.open('/dev/kmsg', os.O_WRONLY)
def log(s): os.write(kmsg, ('<2>wdhold: ' + s).encode())
zones = {open(z + '/type').read().strip(): z + '/temp' for z in glob.glob('/sys/class/thermal/thermal_zone*')}
def temps(): return 'cpu=%d ddr=%d' % tuple(int(open(zones[k]).read()) for k in ('cpu-thermal', 'ddr-thermal'))
if mode == 'mon':
    t0 = time.monotonic(); log('mon start %s' % temps())
    while True:
        time.sleep(2); log('mon t=%ds %s' % (time.monotonic() - t0, temps()))
fd = os.open('/dev/watchdog0', os.O_WRONLY)
fcntl.ioctl(fd, WDIOC_SETTIMEOUT, struct.pack('i', tmo))
got = struct.unpack('i', fcntl.ioctl(fd, WDIOC_GETTIMEOUT, struct.pack('i', 0)))[0]
log('armed /dev/watchdog0 timeout=%ds mode=%s heat=%ss pid=%d %s %s' % (got, mode, heat, os.getpid(), prio, temps()))
kr = None
if mode == 'oom':
    kr = os.open('/dev/kmsg', os.O_RDONLY | os.O_NONBLOCK); os.lseek(kr, 0, os.SEEK_END)
t0 = time.monotonic(); n = 0; reason = 'timer'
while True:
    fcntl.ioctl(fd, WDIOC_KEEPALIVE, struct.pack('i', 0))
    el = time.monotonic() - t0
    if n % 20 == 0: log('pet t=%ds %s' % (el, temps()))
    n += 1
    if el >= heat: break
    if kr is not None:
        hit = False
        while True:
            try: rec = os.read(kr, 8192)
            except BlockingIOError: break
            except OSError: continue   # EPIPE on overrun
            if b'Out of memory' in rec or b'oom-kill' in rec: hit = True
        if hit: reason = 'kernel-OOM'; break
    time.sleep(0.5)
log('STOP petting (%s) at t=%ds; expect HW watchdog reset in %ds; %s' % (reason, time.monotonic() - t0, got, temps()))
ts = time.monotonic()
while True:
    time.sleep(1)
    log('no-pet +%.1fs %s' % (time.monotonic() - ts, temps()))
