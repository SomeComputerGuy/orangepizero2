#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Minimal Matroska video track extractor (own code): writes the frames of
# the first video track, concatenated, to an elementary stream file.
import sys
MASTER = {0x18538067, 0x1F43B675, 0xA0, 0x1654AE6B, 0xAE}
def vint(b, i, keep_marker=False):
    first = b[i]; n = 1; m = 0x80
    while n <= 8 and not (first & m): n += 1; m >>= 1
    v = first if keep_marker else first & (m - 1)
    for k in range(1, n): v = (v << 8) | b[i + k]
    return v, n
def main(src, dst):
    b = open(src, 'rb').read()
    out = open(dst, 'wb')
    tracks = {}; cur = {}; vtrack = None; nframes = 0
    def walk(i, end):
        nonlocal vtrack, nframes, cur
        while i < end:
            eid, n1 = vint(b, i, True); size, n2 = vint(b, i + n1)
            i += n1 + n2
            unknown = size == (1 << (7 * n2)) - 1
            stop = end if unknown else min(i + size, end)
            if eid in MASTER:
                if eid == 0xAE: cur = {}
                walk(i, stop)
                if eid == 0xAE: tracks[cur.get('num')] = cur.get('codec')
            elif eid == 0xD7: cur['num'] = int.from_bytes(b[i:stop], 'big')
            elif eid == 0x86: cur['codec'] = b[i:stop].decode('latin1')
            elif eid in (0xA3, 0xA1):
                tn, n = vint(b, i)
                if vtrack is None:
                    vtrack = next((t for t, c in tracks.items() if c and c.startswith('V_')), None)
                    print('tracks', tracks, 'video', vtrack)
                if tn == vtrack:
                    flags = b[i + n + 2]
                    if flags & 0x06: sys.exit('laced video block not supported')
                    out.write(b[i + n + 3:stop]); nframes += 1
            i = stop
    walk(0, len(b))
    print('frames', nframes)
main(sys.argv[1], sys.argv[2])
