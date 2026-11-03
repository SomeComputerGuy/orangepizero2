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
    else:
        sys.exit(__doc__)
    open(sys.argv[3], 'wb').write(r)


main()
