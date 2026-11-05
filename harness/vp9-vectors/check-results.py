#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Mechanical checks for the VP9 vectors job: check-results.py <logs/runner dir>

Reads out/c1..c4.md (fluster summaries, plain text or emoji) and dmesg-*.txt, prints one line per vector
(name GROUP Success|Fail|...), a per-group table and CHECK lines with PASS/FAIL. The last line is the verdict."""
import glob, os, re, sys

GROUPS = [  # (group, prefixes), first match wins
    ('quantizer', ('vp90-2-00-',)), ('sharpness', ('vp90-2-01-',)),
    ('size-02 (8..66 px)', ('vp90-2-02-size-',)), ('size-03 (196..226 px)', ('vp90-2-03-size-',)),
    ('size-11 (odd)', ('vp90-2-11-size-',)),
    ('resize on key frames (14)', ('vp90-2-14-resize',)),
    ('resize on inter frames (21, 05, 18)', ('vp90-2-21-resize_inter', 'vp90-2-05-resize', 'vp90-2-18-resize')),
    ('svc', ('vp90-2-22-svc',)), ('show-existing-frame', ('vp90-2-10-', 'vp90-2-17-')),
    ('intra-only', ('vp90-2-16-',)), ('profile 1 (4:2:2/4:4:4)', ('vp91-',)),
    ('HIGH 10-bit 4:2:0', ('vp92-2-20-10bit-yuv420',)), ('HIGH unsupported (12-bit, 4:2:2/4:4:0/4:4:4)', ('vp92-', 'vp93-')),
]
# Not decodable by the H616 VE or not handled yet: a Success here is reported, a Fail is expected.
EXPECTED_NOT_SUCCESS = {
    'vp91-2-04-yuv422.webm': 'profile 1, hardware is 4:2:0 only (rejected by the driver)',
    'vp91-2-04-yuv444.webm': 'profile 1, hardware is 4:2:0 only (rejected by the driver)',
    'vp90-2-22-svc_1280x720_3.ivf': 'inter frames grow 320x180 -> 1280x720: needs REMOVE_BUFS + S_FMT while streaming (open)',
    'vp92-2-20-12bit-yuv420.webm': '12-bit, hardware is 10-bit',
    'vp93-2-20-10bit-yuv422.webm': 'profile 3 4:2:2', 'vp93-2-20-10bit-yuv440.webm': 'profile 3 4:4:0',
    'vp93-2-20-10bit-yuv444.webm': 'profile 3 4:4:4', 'vp93-2-20-12bit-yuv422.webm': 'profile 3 12-bit',
    'vp93-2-20-12bit-yuv440.webm': 'profile 3 12-bit', 'vp93-2-20-12bit-yuv444.webm': 'profile 3 12-bit',
}
RESIZE_INTER = 'resize on inter frames (21, 05, 18)'
EXPECTED_TOTAL = {'c1': 71, 'c2': 137, 'c3': 97, 'c4': 6}

def group(name):
    for g, pre in GROUPS:
        if any(name.startswith(p) for p in pre):
            return g
    return 'other'

def main(d):
    res = {}
    missing = []
    for c in ('c1', 'c2', 'c3', 'c4'):
        f = os.path.join(d, 'out', c + '.md')
        if not os.path.exists(f):
            missing.append(c); continue
        n = 0
        for line in open(f, encoding='utf-8', errors='replace'):
            m = re.match(r'^\|(vp9[0-9]-[^|]+)\|([^|]*)\|', line)
            if not m:
                continue
            name, r = m.group(1).strip(), m.group(2).strip()
            r = {'✔️': 'Success', '❌': 'Fail', '☠': 'Error', '⌚': 'Timeout', '〰️': 'Not supported'}.get(r, r)
            res[name] = r; n += 1
        print(f'# {c}: {n} vectors in {f} (expected {EXPECTED_TOTAL[c]})')
    for name in sorted(res):
        print(f'{name} [{group(name)}] {res[name]}')
    print()
    print('| group | success | total | failing |')
    print('|---|---|---|---|')
    checks = []
    bygroup = {}
    for name, r in res.items():
        bygroup.setdefault(group(name), []).append((name, r))
    for g, _ in GROUPS + [('other', ())]:
        if g not in bygroup:
            continue
        v = bygroup[g]; ok = [n for n, r in v if r == 'Success']; bad = [n for n, r in v if r != 'Success']
        print(f'| {g} | {len(ok)} | {len(v)} | {" ".join(sorted(bad))} |')
    print()
    # CHECK 1: all chunks present with all vectors
    checks.append(('1 all four chunks ran (c1..c4.md present, 71/137/97/6 vectors)', not missing and len(res) == 311,
                   f'missing chunks: {missing}; vectors seen: {len(res)} of 311'))
    # CHECK 2: the fix: every inter-frame resize vector decodes bit-exact
    ri = bygroup.get(RESIZE_INTER, [])
    ri_bad = [n for n, r in ri if r != 'Success']
    checks.append(('2 inter-frame resize vectors (24 x vp90-2-21-resize_inter_*, 05-resize, 18-resize) all Success',
                   len(ri) == 26 and not ri_bad, f'{len(ri) - len(ri_bad)}/{len(ri)} Success; failing: {" ".join(ri_bad)}'))
    # CHECK 3: every other vector that the hardware can decode is Success
    other_bad = sorted(n for n, r in res.items() if r != 'Success' and n not in EXPECTED_NOT_SUCCESS and group(n) != RESIZE_INTER)
    checks.append(('3 every other decodable vector Success (302 of the 305 + 10-bit 4:2:0 of HIGH)', not other_bad,
                   f'{len(other_bad)} failing: {" ".join(other_bad)}'))
    # CHECK 4: expected-unsupported vectors (information: a Success is a finding, not a failure)
    unexpected_ok = sorted(n for n in EXPECTED_NOT_SUCCESS if res.get(n) == 'Success')
    checks.append(('4 expected-unsupported vectors (2 x vp91, svc_1280x720_3, 12-bit, vp93) are not Success', not unexpected_ok,
                   f'unexpectedly Success: {" ".join(unexpected_ok)}' if unexpected_ok else 'as expected'))
    # CHECK 5: dmesg clean
    bad_lines = []
    for f in sorted(glob.glob(os.path.join(d, 'dmesg-*.txt'))):
        for line in open(f, errors='replace'):
            if re.search(r'timed out|Oops|BUG:|WARNING|Page fault|iommu.*fault|alloc fail', line, re.I):
                bad_lines.append(os.path.basename(f) + ': ' + line.rstrip())
    checks.append(('5 dmesg: no timeouts, IOMMU faults, Oops or WARNING', not bad_lines, '\n    '.join(bad_lines[:20]) or 'clean'))
    # CHECK 6: no timeouts inside fluster
    timeouts = sorted(n for n, r in res.items() if r == 'Timeout')
    checks.append(('6 no fluster per-vector timeouts (90 s)', not timeouts, ' '.join(timeouts) or 'none'))
    allok = True
    for title, ok, detail in checks:
        print(f'CHECK {title}: {"PASS" if ok else "FAIL"} ({detail})')
        allok = allok and ok
    total = sum(1 for r in res.values() if r == 'Success')
    p0 = sum(1 for n, r in res.items() if r == 'Success' and n.startswith('vp9') and not n.startswith(('vp92', 'vp93')))
    print(f'VERDICT: {"PASS" if allok else "FAIL"}; VP9-TEST-VECTORS {p0}/305 Success, HIGH {total - p0}/6 Success')

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
