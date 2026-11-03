#!/usr/bin/env python3
"""Write a synthetic HDMI 2.0 EDID (base block + CEA-861 extension) for
drm.edid_firmware= testing without a sink: preferred 3840x2160@60 (CEA VIC 97,
594 MHz), 1920x1080@60 (VIC 16), an HDMI 1.4 VSDB and an HF-VSDB with
600 MHz max TMDS character rate and SCDC present. RGB only (no YCbCr bits),
which is all Stage A needs.

usage: mkedid.py OUT.bin
"""
import struct
import sys


def dtd(clk_khz, ha, hfp, hs, hbp, va, vfp, vs, vbp, hmm, vmm, flags=0x1e):
    hb, vb = hfp + hs + hbp, vfp + vs + vbp
    return bytes([
        (clk_khz // 10) & 0xff, (clk_khz // 10) >> 8,
        ha & 0xff, hb & 0xff, ((ha >> 8) << 4) | (hb >> 8),
        va & 0xff, vb & 0xff, ((va >> 8) << 4) | (vb >> 8),
        hfp & 0xff, hs & 0xff, ((vfp & 0xf) << 4) | (vs & 0xf),
        ((hfp >> 8) << 6) | ((hs >> 8) << 4) | ((vfp >> 4) << 2) | (vs >> 4),
        hmm & 0xff, vmm & 0xff, ((hmm >> 8) << 4) | (vmm >> 8),
        0, 0, flags,  # border 0, digital separate sync, +h +v
    ])


def text_desc(tag, s):
    b = s.encode()[:13]
    b += b'\n' + b' ' * (12 - len(b)) if len(b) < 13 else b''
    return bytes([0, 0, 0, tag, 0]) + b[:13]


def finish(block):
    assert len(block) == 127
    return block + bytes([(-sum(block)) & 0xff])


T4K = (594000, 3840, 176, 88, 296, 2160, 8, 10, 72, 1210, 680)
T1080 = (148500, 1920, 88, 44, 148, 1080, 4, 5, 36, 1210, 680)

base = bytearray()
base += bytes([0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0])
mfg = ((ord('O') - 64) << 10) | ((ord('P') - 64) << 5) | (ord('Z') - 64)
base += struct.pack('>H', mfg) + struct.pack('<HI', 0x4b60, 2)
base += bytes([44, 2026 - 1990, 1, 3])       # week, year, EDID 1.3
base += bytes([0x80, 121, 68, 120, 0x0a])    # digital, 121x68 cm, gamma 2.2, RGB
base += bytes([0xee, 0x91, 0xa3, 0x54, 0x4c, 0x99, 0x26, 0x0f, 0x50, 0x54])  # sRGB-ish
base += bytes([0, 0, 0])                     # no established timings
base += bytes([1, 1] * 8)                    # no standard timings
base += dtd(*T4K)
base += dtd(*T1080)
# range limits: 24-75 Hz, 15-160 kHz, 600 MHz, no GTF
base += bytes([0, 0, 0, 0xfd, 0, 24, 75, 15, 160, 60, 0x01, 0x0a]) + b' ' * 6
base += text_desc(0xfc, 'OPZ2-FAKE4K')
base += bytes([1])                           # one extension
base = finish(bytes(base))

dbs = bytearray()
vics = [97, 16 | 0x80, 4, 3]                 # 2160p60, 1080p60 (native), 720p60, 480p
dbs += bytes([(2 << 5) | len(vics)]) + bytes(vics)
hdmi_vsdb = bytes([0x03, 0x0c, 0x00, 0x10, 0x00, 0x00, 340 // 5])
dbs += bytes([(3 << 5) | len(hdmi_vsdb)]) + hdmi_vsdb
hf_vsdb = bytes([0xd8, 0x5d, 0xc4, 0x01, 600 // 5, 0x80, 0x00])  # SCDC present
dbs += bytes([(3 << 5) | len(hf_vsdb)]) + hf_vsdb

ext = bytearray([0x02, 0x03, 4 + len(dbs), 0x00 | 1])  # rev 3, 1 native DTD
ext += dbs
ext += dtd(*T4K)
ext += bytes(127 - len(ext))
ext = finish(bytes(ext))

with open(sys.argv[1], 'wb') as f:
    f.write(base + ext)
