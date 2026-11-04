#!/usr/bin/env python3
# Usage: python3 -I m4v-sprite.py in.m4v -> VOL sprite fields and, per S(GMC)-VOP (decode order), the sprite
# trajectories du/dv (ISO/IEC 14496-2 6.2.3 / 6.2.5.4, rectangular shape only). Reads the elementary stream only.
import sys, re
b = open(sys.argv[1], 'rb').read()
class BR:
    def __init__(s, d, p): s.d, s.p = d, p * 8
    def u(s, n):
        v = 0
        for _ in range(n): v = (v << 1) | ((s.d[s.p >> 3] >> (7 - (s.p & 7))) & 1); s.p += 1
        return v
vol = None; vop = 0
DMV = [(0b00, 2, 0), (0b010, 3, 1), (0b011, 3, 2), (0b100, 3, 3), (0b101, 3, 4), (0b110, 3, 5),
       (0b1110, 4, 6), (0b11110, 5, 7), (0b111110, 6, 8), (0b1111110, 7, 9), (0b11111110, 8, 10),
       (0b111111110, 9, 11), (0b1111111110, 10, 12), (0b11111111110, 11, 13), (0b111111111110, 12, 14)]
def dmv_len(r):
    for code, n, ln in DMV:
        save = r.p
        if r.u(n) == code: return ln
        r.p = save
    raise ValueError('bad dmv_length')
def dmv(r):
    ln = dmv_len(r)
    v = 0
    if ln:
        c = r.u(ln)
        v = c if c >> (ln - 1) else c - (1 << ln) + 1
    r.u(1)  # marker, also after a zero length
    return v
for m in re.finditer(b'\x00\x00\x01', b):
    i = m.end(); c = b[i]; r = BR(b, i + 1)
    if 0x20 <= c <= 0x2f:
        r.u(1); r.u(8)  # random_accessible_vol, type
        verid = 1
        if r.u(1): verid = r.u(4); r.u(3)  # is_object_layer_identifier
        ar = r.u(4)
        if ar == 15: r.u(8); r.u(8)
        if r.u(1):  # vol_control_parameters
            r.u(2); r.u(1)
            if r.u(1): r.u(15); r.u(1); r.u(15); r.u(1); r.u(15); r.u(1); r.u(3); r.u(11); r.u(1); r.u(15); r.u(1)
        shape = r.u(2); r.u(1); tir = r.u(16); r.u(1)
        nbits = max(1, (tir - 1).bit_length())
        if r.u(1): r.u(nbits)
        r.u(1); w = r.u(13); r.u(1); h = r.u(13); r.u(1)
        il = r.u(1); obmc = r.u(1); se = r.u(1 if verid == 1 else 2)
        pts = acc = 0
        if se == 2:  # GMC
            pts = r.u(6); acc = r.u(2); r.u(1)
        new = dict(w=w, h=h, tir=tir, nbits=nbits, interlaced=il, sprite_enable=se, points=pts, accuracy=acc, verid=verid)
        if new != vol: print('VOL', new)
        vol = new
    elif c == 0xb6 and vol:
        t = r.u(2)
        while r.u(1): pass
        r.u(1); r.u(vol['nbits']); r.u(1)
        if not r.u(1): vop += 1; continue
        if t in (1, 3): r.u(1)  # rounding
        r.u(3)  # intra_dc_vlc_thr
        if vol['interlaced']: r.u(1); r.u(1)
        if t == 3 and vol['sprite_enable'] == 2:
            tr = [(dmv(r), dmv(r)) for _ in range(vol['points'])]
            print(f'S-VOP decode#{vop} du/dv', tr)
        vop += 1
