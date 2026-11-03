#!/usr/bin/env python3
# Usage: python3 -I m1-dpic.py in.m1v > out.nv12
# Reference decoder for MPEG-1 D-pictures (ISO/IEC 11172-2 2.4.2.7/2.4.3.6/2.4.4.1), NV12 out, decode order. A D-picture
# has only intra DC coefficients, so each 8x8 block is flat at dct_recon[0][0]/8. This is exact and does not depend on
# the IDCT. Any non-D picture aborts.
import sys, re
b = open(sys.argv[1], 'rb').read()
class BR:
    def __init__(s, d, p): s.d, s.p, s.n = d, p * 8, len(d) * 8
    def peek(s, n):
        v = 0
        for i in range(n):
            q = s.p + i; v = (v << 1) | (((s.d[q >> 3] >> (7 - (q & 7))) & 1) if q < s.n else 0)
        return v
    def u(s, n): v = s.peek(n); s.p += n; return v
def vlc(r, tab):
    for code, n, val in tab:
        if r.peek(n) == code: r.p += n; return val
    raise ValueError('bad vlc at bit %d' % r.p)
MBA = [(0b1,1,1),(0b011,3,2),(0b010,3,3),(0b0011,4,4),(0b0010,4,5),(0b00011,5,6),(0b00010,5,7),(0b0000111,7,8),
       (0b0000110,7,9),(0b00001011,8,10),(0b00001010,8,11),(0b00001001,8,12),(0b00001000,8,13),(0b00000111,8,14),
       (0b00000110,8,15),(0b0000010111,10,16),(0b0000010110,10,17),(0b0000010101,10,18),(0b0000010100,10,19),
       (0b0000010011,10,20),(0b0000010010,10,21),(0b00000100011,11,22),(0b00000100010,11,23),(0b00000100001,11,24),
       (0b00000100000,11,25),(0b00000011111,11,26),(0b00000011110,11,27),(0b00000011101,11,28),(0b00000011100,11,29),
       (0b00000011011,11,30),(0b00000011010,11,31),(0b00000011001,11,32),(0b00000011000,11,33),
       (0b00000001111,11,'stuff'),(0b00000001000,11,'esc')]
DCL = [(0b100,3,0),(0b00,2,1),(0b01,2,2),(0b101,3,3),(0b110,3,4),(0b1110,4,5),(0b11110,5,6),(0b111110,6,7),(0b1111110,7,8)]
DCC = [(0b00,2,0),(0b01,2,1),(0b10,2,2),(0b110,3,3),(0b1110,4,5 - 1),(0b11110,5,5),(0b111110,6,6),(0b1111110,7,7),(0b11111110,8,8)]
def diff(r, size):
    if size == 0: return 0
    v = r.u(size)
    return v if v >> (size - 1) else v - (1 << size) + 1
W = H = 0; Y = U = V = None; out = sys.stdout.buffer; pic = None; nfr = 0
def flush():
    global nfr
    if Y is None or pic != 4: return
    uv = bytearray(len(U) * 2); uv[0::2] = U; uv[1::2] = V
    out.write(bytes(Y)); out.write(bytes(uv)); nfr += 1
for m in re.finditer(b'\x00\x00\x01', b):
    i = m.end(); c = b[i]; r = BR(b, i + 1)
    if c == 0xb3:
        flush(); pic = None
        W, H = r.u(12), r.u(12); mbw, mbh = (W + 15) // 16, (H + 15) // 16
    elif c == 0x00:
        flush()
        r.u(10); pic = r.u(3)
        if pic != 4: sys.exit('non-D picture (type %d): not a D-only stream' % pic)
        Y = bytearray(W * H); U = bytearray((W // 2) * (H // 2)); V = bytearray((W // 2) * (H // 2))
    elif 0x01 <= c <= 0xaf and pic == 4:
        addr = (c - 1) * mbw - 1; r.u(5)
        while r.u(1): r.u(8)
        past = [1024, 1024, 1024]
        while r.peek(23) != 0 and r.p < r.n:
            inc = 0
            while True:
                v = vlc(r, MBA)
                if v == 'stuff': continue
                if v == 'esc': inc += 33; continue
                inc += v; break
            if inc > 1: past = [1024, 1024, 1024]
            addr += inc; my, mx = divmod(addr, mbw)
            if r.u(1) != 1: raise ValueError('D macroblock_type must be 1')
            for blk in range(6):
                if blk < 4:
                    past[0] += 8 * diff(r, vlc(r, DCL)); val = max(0, min(255, past[0] // 8))
                    x0, y0 = mx * 16 + (blk & 1) * 8, my * 16 + (blk >> 1) * 8
                    for y in range(y0, min(y0 + 8, H)):
                        e = min(x0 + 8, W)
                        if x0 < e: Y[y * W + x0:y * W + e] = bytes([val]) * (e - x0)
                else:
                    k = blk - 3; past[k] += 8 * diff(r, vlc(r, DCC)); val = max(0, min(255, past[k] // 8))
                    P = U if k == 1 else V; cw = W // 2
                    for y in range(my * 8, min(my * 8 + 8, H // 2)):
                        e = min(mx * 8 + 8, cw)
                        P[y * cw + mx * 8:y * cw + e] = bytes([val]) * (e - mx * 8)
            if r.u(1) != 1: raise ValueError('end_of_macroblock missing at mb %d' % addr)
    elif c == 0xb7:
        flush(); pic = None
flush(); sys.stderr.write('%dx%d frames %d\n' % (W, H, nfr))
