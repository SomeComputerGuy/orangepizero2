#!/usr/bin/env python3
# Usage: python3 -I m4v-retraj.py in.m4v out.m4v <decode#>=<du0>,<dv0>,<du1>,<dv1>,... ...
# Rewrites the sprite trajectories of the given S(GMC)-VOPs (decode order), re-aligning the rest of each VOP
# (rectangular shape, the VOL parsing of m4v-sprite.py). The decode is still valid: only the warp changes.
import sys, re, importlib.util
src = open(sys.argv[1], 'rb').read()
want = {int(k): [int(x) for x in v.split(',')] for k, v in (a.split('=') for a in sys.argv[3:])}
spec = importlib.util.spec_from_file_location('sp', __file__.replace('m4v-retraj.py', 'm4v-sprite.py'))
def bits(d): return ''.join(f'{x:08b}' for x in d)
def dmv_bits(v):
    if v == 0: return '001'
    ln = abs(v).bit_length()
    code = {1: '010', 2: '011', 3: '100', 4: '101', 5: '110'}.get(ln) or ('1' * (ln - 2) + '0')
    c = v if v > 0 else v + (1 << ln) - 1
    return code + format(c, f'0{ln}b') + '1'
# Parse with the reader of m4v-sprite.py, but record bit positions.
import types
sp = types.ModuleType('sp'); code = open(spec.origin).read()
pre = code.split('for m in re.finditer')[0].replace("b = open(sys.argv[1], 'rb').read()", 'b = SRC')
ns = {'SRC': src}; exec(pre, ns)
BR, dmv = ns['BR'], ns['dmv']
starts = [m.start() for m in re.finditer(b'\x00\x00\x01', src)] + [len(src)]
out = bytearray(); vol = None; vop = 0
for si in range(len(starts) - 1):
    a, e = starts[si], starts[si + 1]; c = src[a + 3]; r = BR(src, a + 4); seg = src[a:e]
    if 0x20 <= c <= 0x2f:
        r.u(1); r.u(8); verid = 1
        if r.u(1): verid = r.u(4); r.u(3)
        if r.u(4) == 15: r.u(16)
        if r.u(1):
            r.u(3)
            if r.u(1): r.u(79)
        r.u(3); tir = r.u(16); r.u(1); nbits = max(1, (tir - 1).bit_length())
        if r.u(1): r.u(nbits)
        r.u(29); il = r.u(1); r.u(1); se = r.u(1 if verid == 1 else 2); pts = r.u(6) if se == 2 else 0
        vol = dict(nbits=nbits, il=il, se=se, pts=pts)
    elif c == 0xb6 and vol:
        t = r.u(2)
        while r.u(1): pass
        r.u(1); r.u(vol['nbits']); r.u(1)
        if r.u(1):
            if t in (1, 3): r.u(1)
            r.u(3)
            if vol['il']: r.u(2)
            if t == 3 and vol['se'] == 2:
                p0 = r.p - a * 8; old = [dmv(r) for _ in range(2 * vol['pts'])]; p1 = r.p - a * 8
                if vop in want:
                    sb = bits(seg); body = sb[p1:]
                    k = len(body) - len(body.rstrip('1')); assert k <= 7 and body[-k - 1] == '0', 'stuffing'
                    body = body[:-k - 1]
                    nb = sb[:p0] + ''.join(dmv_bits(v) for v in want[vop]) + body
                    nb += '0' + '1' * ((8 - (len(nb) + 1) % 8) % 8)
                    seg = bytes(int(nb[i:i + 8], 2) for i in range(0, len(nb), 8))
                    print(f'decode#{vop}: {old} -> {want[vop]}', file=sys.stderr)
        vop += 1
    out += seg
open(sys.argv[2], 'wb').write(out)
