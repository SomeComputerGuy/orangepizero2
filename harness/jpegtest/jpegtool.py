#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Small JPEG segment editor for decoder test vectors (run with python3 -I).

  jpegtool.py info IN                 print SOF/DQT/DHT/DRI/SOS summary
  jpegtool.py strip-dht IN OUT        drop every DHT segment (decoder must
                                      fall back to the T.81 annex K tables;
                                      only valid if IN used those tables)
  jpegtool.py cr-table IN OUT         copy the chroma DQT table into slot 2
                                      with one entry changed, point Cr at it
                                      (decoder must reject)
  jpegtool.py truncate IN OUT FRAC    keep FRAC of the entropy coded data,
                                      then EOI (decoder must fail cleanly)
  jpegtool.py cr-table-same IN OUT    copy the chroma DQT table unchanged
                                      into slot 2 and point Cr at it (same
                                      content: a decoder with one chroma
                                      table set must still decode)
  jpegtool.py cr-huffman IN OUT       recode Cr with the luma Huffman tables
                                      (slot 0), one interleaved scan: Cb and
                                      Cr tables differ, same picture
  jpegtool.py split-scans IN OUT N    recode the single interleaved scan as
                                      N scans: 3 = Y, Cb, Cr each alone,
                                      2 = Y alone then Cb+Cr interleaved;
                                      drops DRI; same picture
The last three need a baseline/extended sequential 8-bit YCbCr image with one
interleaved scan (what gen.sh makes); they are checked by decoding OUT and IN
with ffmpeg and comparing.
"""
import struct
import sys


def segments(d):
    assert d[:2] == b'\xff\xd8', 'not a JPEG'
    i = 2
    while i < len(d):
        assert d[i] == 0xff, 'lost sync at %d' % i
        m = d[i + 1]
        if m == 0xd9:
            yield m, i, i + 2
            return
        ln = struct.unpack('>H', d[i + 2:i + 4])[0]
        yield m, i, i + 2 + ln
        if m == 0xda:
            yield 0x100, i + 2 + ln, len(d)  # entropy coded data + rest
            return
        i += 2 + ln


def info(d):
    for m, a, b in segments(d):
        p = d[a + 4:b]
        if m == 0xc0 or m == 0xc1:
            prec, h, w, nf = struct.unpack('>BHHB', p[:6])
            comps = [(p[6 + 3 * k], p[7 + 3 * k] >> 4, p[7 + 3 * k] & 15, p[8 + 3 * k])
                     for k in range(nf)]
            print('SOF%d %dx%d P=%d comps(id,H,V,Tq)=%s' % (m - 0xc0, w, h, prec, comps))
        elif m == 0xdb:
            k = 0
            while k < len(p):
                print('DQT Pq=%d Tq=%d' % (p[k] >> 4, p[k] & 15))
                k += 65 if p[k] >> 4 == 0 else 129
        elif m == 0xc4:
            k = 0
            while k < len(p):
                n = sum(p[k + 1:k + 17])
                print('DHT Tc=%d Th=%d count=%d' % (p[k] >> 4, p[k] & 15, n))
                k += 17 + n
        elif m == 0xdd:
            print('DRI %d' % struct.unpack('>H', p[:2]))
        elif m == 0xda:
            ns = p[0]
            print('SOS comps(id,Td,Ta)=%s' % [(p[1 + 2 * k], p[2 + 2 * k] >> 4, p[2 + 2 * k] & 15)
                                               for k in range(ns)])


def strip_dht(d):
    out = bytearray(d[:2])
    for m, a, b in segments(d):
        if m != 0xc4:
            out += d[a:b]
    return bytes(out)


def cr_table(d):
    out = bytearray(d[:2])
    for m, a, b in segments(d):
        seg = bytearray(d[a:b])
        if m == 0xdb and not hasattr(cr_table, 'done'):
            p = seg[4:]
            k = 0
            while k < len(p):
                if p[k] == 0x01:
                    t = bytearray(p[k:k + 65])
                    t[0] = 0x02
                    t[10] = t[10] + 1 if t[10] < 255 else 254
                    seg += t
                    cr_table.done = True
                    break
                k += 65
            struct.pack_into('>H', seg, 2, len(seg) - 2)
        if m in (0xc0, 0xc1):
            nf = seg[9]
            assert nf == 3
            seg[10 + 3 * 2 + 2] = 2
        out += seg
    assert getattr(cr_table, 'done', False), 'no DQT table 1'
    return bytes(out)


def cr_table_same(d):
    out = bytearray(d[:2])
    done = False
    for m, a, b in segments(d):
        seg = bytearray(d[a:b])
        if m == 0xdb and not done:
            p = seg[4:]
            k = 0
            while k < len(p):
                if p[k] == 0x01:
                    t = bytearray(p[k:k + 65])
                    t[0] = 0x02
                    seg += t
                    done = True
                    break
                k += 65 if p[k] >> 4 == 0 else 129
            struct.pack_into('>H', seg, 2, len(seg) - 2)
        if m in (0xc0, 0xc1):
            assert seg[9] == 3
            seg[10 + 3 * 2 + 2] = 2
        out += seg
    assert done, 'no DQT table 1'
    return bytes(out)


# --- entropy transcoding (T.81 F.1.2 / F.2.2, sequential DCT, Huffman) ---

class Huff:
    """One DHT table: decode by (length, code), encode by symbol."""

    def __init__(self, bits, vals):
        assert len(bits) == 16 and len(vals) == sum(bits), 'bad DHT table'
        self.bits, self.vals = bits, vals
        self.dec, self.enc = {}, {}
        code, k = 0, 0
        for ln in range(1, 17):
            for _ in range(bits[ln - 1]):
                self.dec[(ln, code)] = vals[k]
                self.enc[vals[k]] = (ln, code)
                code += 1
                k += 1
            code <<= 1


def parse_dht(p):
    tabs = {}
    k = 0
    while k < len(p):
        tc, th = p[k] >> 4, p[k] & 15
        bits = list(p[k + 1:k + 17])
        n = sum(bits)
        tabs[(tc, th)] = Huff(bits, list(p[k + 17:k + 17 + n]))
        k += 17 + n
    return tabs


# ITU-T T.81 annex K.3 default tables, used when the image has no DHT
K3 = {
    (0, 0): ([0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0], list(range(12))),
    (0, 1): ([0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0], list(range(12))),
    (1, 0): ([0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 0x7d], [
        0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07,
        0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xa1, 0x08, 0x23, 0x42, 0xb1, 0xc1, 0x15, 0x52, 0xd1, 0xf0,
        0x24, 0x33, 0x62, 0x72, 0x82, 0x09, 0x0a, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x25, 0x26, 0x27, 0x28,
        0x29, 0x2a, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49,
        0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69,
        0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
        0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7,
        0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3, 0xc4, 0xc5,
        0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xe1, 0xe2,
        0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
        0xf9, 0xfa]),
    (1, 1): ([0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 0x77], [
        0x00, 0x01, 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71,
        0x13, 0x22, 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xa1, 0xb1, 0xc1, 0x09, 0x23, 0x33, 0x52, 0xf0,
        0x15, 0x62, 0x72, 0xd1, 0x0a, 0x16, 0x24, 0x34, 0xe1, 0x25, 0xf1, 0x17, 0x18, 0x19, 0x1a, 0x26,
        0x27, 0x28, 0x29, 0x2a, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48,
        0x49, 0x4a, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68,
        0x69, 0x6a, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
        0x88, 0x89, 0x8a, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9a, 0xa2, 0xa3, 0xa4, 0xa5,
        0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xc2, 0xc3,
        0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xca, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda,
        0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8,
        0xf9, 0xfa]),
}


class BitReader:
    """Entropy coded segment reader: unstuffs FF00, stops at markers."""

    def __init__(self, d, pos):
        self.d, self.pos, self.acc, self.n = d, pos, 0, 0

    def fill(self):
        while self.n <= 24:
            b = self.d[self.pos]
            if b == 0xff:
                nxt = self.d[self.pos + 1]
                if nxt == 0x00:
                    self.pos += 2
                elif 0xd0 <= nxt <= 0xd7 or nxt == 0xd9:
                    b = 0  # marker: feed zeros, do not advance
                else:
                    raise ValueError('unexpected marker %02x' % nxt)
            else:
                self.pos += 1
            self.acc = (self.acc << 8) | b
            self.n += 8

    def bits(self, k):
        if k == 0:
            return 0
        if self.n < k:
            self.fill()
        v = (self.acc >> (self.n - k)) & ((1 << k) - 1)
        self.n -= k
        self.acc &= (1 << self.n) - 1
        return v

    def huff(self, h):
        if self.n < 16:
            self.fill()
        code, ln = 0, 0
        while ln < 16:
            code = (code << 1) | ((self.acc >> (self.n - 1)) & 1)
            self.n -= 1
            ln += 1
            v = h.dec.get((ln, code))
            if v is not None:
                return v
        raise ValueError('bad Huffman code')

    def restart(self):
        """Byte-align and consume the RSTn marker."""
        self.acc, self.n = 0, 0
        while not (self.d[self.pos] == 0xff and self.d[self.pos + 1] != 0x00):
            self.pos += 1
        assert 0xd0 <= self.d[self.pos + 1] <= 0xd7, 'RST marker expected'
        self.pos += 2


class BitWriter:
    def __init__(self):
        self.out, self.acc, self.n = bytearray(), 0, 0

    def put(self, v, k):
        self.acc = (self.acc << k) | v
        self.n += k
        while self.n >= 8:
            b = (self.acc >> (self.n - 8)) & 0xff
            self.out.append(b)
            if b == 0xff:
                self.out.append(0)
            self.n -= 8
            self.acc &= (1 << self.n) - 1

    def huff(self, h, sym):
        ln, code = h.enc[sym]
        self.put(code, ln)

    def flush(self):
        if self.n:
            self.put((1 << (8 - self.n)) - 1, 8 - self.n)
        return bytes(self.out)


def extend(v, t):
    return v - (1 << t) + 1 if t and v < (1 << (t - 1)) else v


def category(v):
    return abs(v).bit_length()


def decode_block(br, dc, ac):
    """-> (dc difference value, [(rs, extra bits value), ...])"""
    t = br.huff(dc)
    diff = extend(br.bits(t), t)
    syms = []
    k = 1
    while k < 64:
        rs = br.huff(ac)
        s = rs & 15
        syms.append((rs, br.bits(s)))
        if rs == 0x00:
            break
        k += (rs >> 4) + 1 if rs != 0xf0 else 16
    return diff, syms


def encode_block(bw, dc, ac, diff, syms):
    t = category(diff)
    bw.huff(dc, t)
    if t:
        bw.put(diff if diff > 0 else diff + (1 << t) - 1, t)
    for rs, extra in syms:
        bw.huff(ac, rs)
        bw.put(extra, rs & 15)


def read_image(d):
    """Parse the headers and decode the single interleaved scan into
    per-component block arrays (absolute DC, AC symbol list)."""
    comps, dqt, dht, dri, sos = [], [], {}, 0, None
    w = h = 0
    for m, a, b in segments(d):
        p = d[a + 4:b]
        if m in (0xc0, 0xc1):
            prec, h, w, nf = struct.unpack('>BHHB', p[:6])
            assert prec == 8 and nf == 3, 'need an 8-bit 3-component image'
            comps = [dict(cid=p[6 + 3 * k], hs=p[7 + 3 * k] >> 4, vs=p[7 + 3 * k] & 15,
                          tq=p[8 + 3 * k]) for k in range(nf)]
        elif m == 0xc4:
            dht.update(parse_dht(p))
        elif m == 0xdd:
            dri = struct.unpack('>H', p[:2])[0]
        elif m == 0xda:
            ns = p[0]
            assert ns == 3, 'need one interleaved scan'
            sos = [(p[1 + 2 * k], p[2 + 2 * k] >> 4, p[2 + 2 * k] & 15) for k in range(ns)]
            ecs = b
        elif m == 0xc2 or (0xc3 <= m <= 0xcf and m != 0xc4):
            raise SystemExit('not a sequential Huffman image')
    assert comps and sos
    for k, (cid, td, ta) in enumerate(sos):
        assert cid == comps[k]['cid'], 'scan order differs from the frame'
        comps[k]['td'], comps[k]['ta'] = td, ta
    for c in comps:
        c['dc'] = dht.get((0, c['td'])) or Huff(*K3[(0, c['td'])])
        c['ac'] = dht.get((1, c['ta'])) or Huff(*K3[(1, c['ta'])])
    hmax = max(c['hs'] for c in comps)
    vmax = max(c['vs'] for c in comps)
    mcux = -(-w // (8 * hmax))
    mcuy = -(-h // (8 * vmax))
    for c in comps:
        c['bw'], c['bh'] = mcux * c['hs'], mcuy * c['vs']  # interleaved block grid
        cw = -(-w * c['hs'] // hmax)
        ch = -(-h * c['vs'] // vmax)
        c['nbw'], c['nbh'] = -(-cw // 8), -(-ch // 8)  # non-interleaved grid
        c['blocks'] = [None] * (c['bw'] * c['bh'])
    br = BitReader(d, ecs)
    pred = [0, 0, 0]
    n = 0
    for my in range(mcuy):
        for mx in range(mcux):
            if dri and n and n % dri == 0:
                br.restart()
                pred = [0, 0, 0]
            for k, c in enumerate(comps):
                for v in range(c['vs']):
                    for u in range(c['hs']):
                        diff, syms = decode_block(br, c['dc'], c['ac'])
                        pred[k] += diff
                        c['blocks'][(my * c['vs'] + v) * c['bw'] + mx * c['hs'] + u] = (pred[k], syms)
            n += 1
    return dict(w=w, h=h, comps=comps, mcux=mcux, mcuy=mcuy, dht=dht)


def write_scan(bw_comps, img, members):
    """Entropy code the components `members` (indexes) as one scan."""
    bw = BitWriter()
    comps = img['comps']
    pred = {k: 0 for k in members}
    if len(members) == 1:
        c = comps[members[0]]
        for by in range(c['nbh']):
            for bx in range(c['nbw']):
                dcv, syms = c['blocks'][by * c['bw'] + bx]
                encode_block(bw, bw_comps[members[0]][0], bw_comps[members[0]][1], dcv - pred[members[0]], syms)
                pred[members[0]] = dcv
    else:
        for my in range(img['mcuy']):
            for mx in range(img['mcux']):
                for k in members:
                    c = comps[k]
                    for v in range(c['vs']):
                        for u in range(c['hs']):
                            dcv, syms = c['blocks'][(my * c['vs'] + v) * c['bw'] + mx * c['hs'] + u]
                            encode_block(bw, bw_comps[k][0], bw_comps[k][1], dcv - pred[k], syms)
                            pred[k] = dcv
    return bw.flush()


def sos_segment(comps, members, sel):
    seg = bytearray(b'\xff\xda\x00\x00' + bytes([len(members)]))
    for k in members:
        seg += bytes([comps[k]['cid'], sel[k][0] << 4 | sel[k][1]])
    seg += b'\x00\x3f\x00'
    struct.pack_into('>H', seg, 2, len(seg) - 2)
    return bytes(seg)


def rewrite(d, img, groups, sel):
    """Headers of IN up to (not including) its SOS, without DRI, then the
    scans `groups` (lists of component indexes) with table selectors `sel`
    (per component (Td, Ta)), then EOI."""
    out = bytearray(d[:2])
    for m, a, b in segments(d):
        if m == 0xda:
            break
        if m != 0xdd:
            out += d[a:b]
    tabs = {}
    for k, c in enumerate(img['comps']):
        tabs[k] = (img['dht'].get((0, sel[k][0])) or Huff(*K3[(0, sel[k][0])]),
                   img['dht'].get((1, sel[k][1])) or Huff(*K3[(1, sel[k][1])]))
    for members in groups:
        out += sos_segment(img['comps'], members, sel)
        out += write_scan(tabs, img, members)
    out += b'\xff\xd9'
    return bytes(out)


def cr_huffman(d):
    img = read_image(d)
    c = img['comps']
    sel = {0: (c[0]['td'], c[0]['ta']), 1: (c[1]['td'], c[1]['ta']), 2: (c[0]['td'], c[0]['ta'])}
    assert sel[2] != sel[1], 'Cr already uses the luma tables'
    return rewrite(d, img, [[0, 1, 2]], sel)


def split_scans(d, n):
    img = read_image(d)
    c = img['comps']
    sel = {k: (c[k]['td'], c[k]['ta']) for k in range(3)}
    groups = {3: [[0], [1], [2]], 2: [[0], [1, 2]]}[n]
    return rewrite(d, img, groups, sel)


def truncate(d, frac):
    out = bytearray(d[:2])
    for m, a, b in segments(d):
        if m == 0x100:
            out += d[a:a + int((b - a) * frac)] + b'\xff\xd9'
            return bytes(out)
        out += d[a:b]
    return bytes(out)


def main():
    cmd = sys.argv[1]
    d = open(sys.argv[2], 'rb').read()
    if cmd == 'info':
        info(d)
        return
    if cmd == 'strip-dht':
        r = strip_dht(d)
    elif cmd == 'cr-table':
        r = cr_table(d)
    elif cmd == 'truncate':
        r = truncate(d, float(sys.argv[4]))
    elif cmd == 'cr-table-same':
        r = cr_table_same(d)
    elif cmd == 'cr-huffman':
        r = cr_huffman(d)
    elif cmd == 'split-scans':
        r = split_scans(d, int(sys.argv[4]))
    else:
        sys.exit(__doc__)
    open(sys.argv[3], 'wb').write(r)


main()
