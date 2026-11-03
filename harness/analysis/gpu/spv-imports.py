#!/usr/bin/env python3
"""List SPIR-V Import-linkage (unresolved) symbols in a libclc .spv. Usage: spv-imports.py file.spv"""
import sys, struct
d = open(sys.argv[1], "rb").read(); i = d.find(b"\x03\x02\x23\x07"); d = d[i:]
w = struct.unpack("<%dI" % (len(d) // 4), d[:len(d) // 4 * 4]); p = 5; imp = []
while p < len(w):
    op, n = w[p] & 0xffff, w[p] >> 16
    if n == 0: break
    if op == 71 and w[p + 2] == 41 and w[p + n - 1] == 1:
        imp.append(struct.pack("<%dI" % (n - 3), *w[p + 3:p + n]).split(b"\0")[0].decode())
    p += n
print(len(imp), "imports:", " ".join(sorted(imp)))
