#!/usr/bin/env python3
# Usage: python3 -I m2v-structure.py file... -> per file: size, MPEG-1/2, picture_structure counts (frame/top/bottom),
# progressive_sequence, picture types, chroma format. Reads elementary streams only.
import sys, re
for fn in sys.argv[1:]:
    b = open(fn, 'rb').read(); st = {1: 0, 2: 0, 3: 0}; ty = {1: 0, 2: 0, 3: 0, 4: 0}; mpeg2 = False; prog = None; w = h = cf = None
    for m in re.finditer(b'\x00\x00\x01', b):
        i = m.end()
        if i + 6 > len(b): break
        c = b[i]
        if c == 0xB3: w = (b[i+1] << 4) | (b[i+2] >> 4); h = ((b[i+2] & 15) << 8) | b[i+3]
        elif c == 0x00: ty[(b[i+2] >> 3) & 7] = ty.get((b[i+2] >> 3) & 7, 0) + 1
        elif c == 0xB5:
            ext = b[i+1] >> 4
            if ext == 1: mpeg2 = True; prog = (b[i+2] >> 3) & 1; cf = (b[i+2] >> 1) & 3
            elif ext == 8: st[b[i+3] & 3] = st.get(b[i+3] & 3, 0) + 1
    print(f"{fn.split('/')[-1]}\t{w}x{h}\t{'MPEG-2' if mpeg2 else 'MPEG-1'}\tprog_seq={prog}\tchroma={cf}\tframe={st[3]} top={st[1]} bot={st[2]}\tI/P/B/D={ty[1]}/{ty[2]}/{ty[3]}/{ty[4]}")
