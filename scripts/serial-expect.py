#!/usr/bin/env python3
"""Drive the OPi Zero2 serial console: wait for regexes in harness/serial.log, send replies on the port.
serial-log.py must be running (it owns reading); this script only writes to the port and tails the log.

  serial-expect.py STEP [STEP ...]     STEP = 'regex=>reply'  (reply '' sends just Enter; reply '-' sends nothing)
  serial-expect.py --timeout 30 ...
Prints each matched line. Exits 1 on a timeout."""
import os, re, sys, time
import serial

TOP = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
LOG = os.path.join(TOP, "harness", "serial.log")
PORT = os.environ.get("OPIZ2_TTY", "/dev/ttyOPIZ2" if os.path.exists("/dev/ttyOPIZ2") else "/dev/ttyUSB1")
STRIP = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]|\x1b[()][A-Z0-9]|\r")


def main(argv):
    timeout = 60.0
    if argv and argv[0] == "--timeout":
        timeout = float(argv[1]); argv = argv[2:]
    steps = [a.split("=>", 1) for a in argv]
    port = serial.Serial(PORT, 115200, timeout=0)
    with open(LOG, "rb") as log:
        log.seek(0, os.SEEK_END)
        for pat, reply in steps:
            rx = re.compile(pat.encode())
            t0 = time.time(); buf = b""
            while True:
                chunk = log.read()
                if chunk:
                    buf += STRIP.sub(b"", chunk)
                    m = rx.search(buf)
                    if m:
                        line = buf[max(0, buf.rfind(b"\n", 0, m.start()) + 1):m.end()].decode("utf-8", "replace")
                        print(f"[match] {line.strip()[-160:]}  -> {'(nothing)' if reply == '-' else repr(reply)}")
                        if reply != "-":
                            time.sleep(0.3)
                            port.write(reply.encode() + b"\n"); port.flush()
                        break
                if time.time() - t0 > timeout:
                    print(f"[timeout] waiting for /{pat}/; last output:\n{buf[-800:].decode('utf-8','replace')}")
                    return 1
                time.sleep(0.2)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
