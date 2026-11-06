#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Job 35 (c31) evidence: put back what the bit writer dropped (32-bit puts: the Annex B start codes and the SPS VUI
# num_units_in_tick/time_scale u(32) fields; SPS/PPS nal_ref_idc set to 3) and write a decodable stream.
#   job35-repair.py <rN.h264> <rN.txt (encoder log, frame sizes)> <out.h264>
# Then: ffmpeg -i out.h264 -f rawvideo -pix_fmt nv12 x.nv12; psnr against runner/clips/<clip>.nv12.
# Result 2026-11-06: r1 49.2 dB, r2 47.6, r3 53.9, r4 44.4 (PSNR-Y), all frames decoded.
import re, sys
d = open(sys.argv[1], 'rb').read()
sizes = [int(s) for s in re.findall(r'frame \d+: \w[ \w]* (\d+) bytes', open(sys.argv[2]).read())]
sc, out, off = b'\0\0\0\1', b'', 0
for s in sizes:
    f = d[off:off + s]; off += s
    if f[0] == 0x07:                                   # SPS (ref_idc 0), then PPS (0x08), then the IDR slice (0x65)
        i = f.index(b'\x08', 5); j = f.index(b'\x65', i + 1)
        bits = ''.join(f'{b:08b}' for b in f[1:i])
        pos = bits.rindex('1') - 5                     # after timing_info_present_flag (fixed, nal/vcl hrd, pic_struct, restriction, stop)
        bits = bits[:pos] + f'{1:032b}' + f'{60:032b}' + bits[pos:]
        sps = bytes(int(bits[k:k + 8], 2) for k in range(0, len(bits), 8))
        out += sc + b'\x67' + sps + sc + b'\x68' + f[i + 1:j] + sc + f[j:]
    else:
        out += sc + f
assert off == len(d), (off, len(d))
open(sys.argv[3], 'wb').write(out)
