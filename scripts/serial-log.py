#!/usr/bin/env python3
"""Log the Orange Pi Zero2 serial console (/dev/ttyUSB1 @115200) to harness/serial.log, timestamped.
Optionally send a line first:  serial-log.py --send 'command'
Run as a background task; it keeps running until killed and reconnects if the adapter disappears."""
import os, sys, time, datetime
import serial

PORT = os.environ.get("OPIZ2_TTY", "/dev/ttyUSB1")
LOG = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), "harness", "serial.log")

def ts():
    return datetime.datetime.now().strftime("%H:%M:%S.%f")[:-3]

def main():
    send = None
    if len(sys.argv) >= 3 and sys.argv[1] == "--send":
        send = sys.argv[2]
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "ab", buffering=0) as log:
        while True:
            try:
                s = serial.Serial(PORT, 115200, timeout=0.5)
                log.write(f"\n[{ts()}] === serial-log attached to {PORT} ===\n".encode())
                if send is not None:
                    s.write((send + "\n").encode()); send = None
                line = b""; at_line_start = True
                while True:
                    data = s.read(4096)
                    if not data:
                        if line:  # prompt without newline: flush it so readers see it
                            log.write((f"[{ts()}] ".encode() if at_line_start else b"") + line)
                            line = b""; at_line_start = False
                        continue
                    for ch in data:
                        line += bytes([ch])
                        if ch == 10:
                            log.write((f"[{ts()}] ".encode() if at_line_start else b"") + line)
                            line = b""; at_line_start = True
            except (serial.SerialException, OSError) as e:
                log.write(f"[{ts()}] === serial error: {e}; retrying in 2s ===\n".encode())
                time.sleep(2)

if __name__ == "__main__":
    main()
