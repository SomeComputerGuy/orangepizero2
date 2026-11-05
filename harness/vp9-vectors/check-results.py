#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Mechanical checks for the VP9 vectors jobs: check-results.py <logs dir> [full|upsize]

Reads kernel.txt, out/pre.md, the chunk summaries out/<c>.md (fluster summaries; fluster 0.7.1 writes the plain-text
tokens OK/KO/ER/TO/NS with -ne, the emoji otherwise, the long words in the console log) and dmesg-*.txt, prints one
line per vector (name GROUP Success|Fail|...), a per-group table and CHECK lines with PASS/FAIL. The last line is the
verdict. Job `full` (default, chunks c1 c2 c3 c5 c4 = the 311 vectors, job vp9-vectors) or `upsize` (chunks u1 u2 =
svc_1280x720_3 + the 26 downsize vectors + a 25-vector regression subset, job vp9-upsize)."""
import glob, os, re, subprocess, sys

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
SVC_UPSIZE = 'vp90-2-22-svc_1280x720_3.ivf'
EXPECTED_TOTAL = {'c1': 71, 'c2': 137, 'c3': 59, 'c5': 38, 'c4': 6, 'u1': 27, 'u2': 25}
JOBS = {'full': (['c1', 'c2', 'c3', 'c5', 'c4'], 311), 'upsize': (['u1', 'u2'], 52)}
# armbian-build commit of the upsize fix (fix/sunxi-cedrus-vp9-inter-upsize): svc_1280x720_3 is expected to decode on
# a cumulative kernel that contains it (checked with git in the test-cumulative worktree).
UPSIZE_SHA = '7897dec0864e755260c0ff9db3895cb99fd1f9d7'
ARMBIAN = '/home/aruni/orangepizero2/wt-cumulative'
TOKENS = {'OK': 'Success', 'KO': 'Fail', 'ER': 'Error', 'TO': 'Timeout', 'NS': 'Not supported',
          '✔️': 'Success', '❌': 'Fail', '☠': 'Error', '⌛': 'Timeout', '○': 'Not supported'}
FIX_KERNEL = 10  # cumulative kernel c10 = armbian-build f8be54bac (fix/sunxi-cedrus-vp9-inter-resize)
GOOD = 'vp90-2-00-quantizer-00.webm'  # pre-flight vector

def group(name):
    for g, pre in GROUPS:
        if any(name.startswith(p) for p in pre):
            return g
    return 'other'

def kernel_has(kernel_sha, fix_sha):
    """Whether the test-cumulative commit kernel_sha contains fix_sha (False if git cannot tell)."""
    if not kernel_sha:
        return False
    try:
        return subprocess.run(['git', '-C', ARMBIAN, 'merge-base', '--is-ancestor', fix_sha, kernel_sha],
                              capture_output=True, timeout=30).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False

def read_md(f):
    out = {}
    for line in open(f, encoding='utf-8', errors='replace'):
        m = re.match(r'^\|(vp9[0-9]-[^|]+)\|([^|]*)\|', line)
        if m:
            name, r = m.group(1).strip(), m.group(2).strip()
            out[name] = TOKENS.get(r, r)
    return out

def main(d, job='full'):
    res = {}
    missing = []
    chunks, nvec = JOBS[job]
    kf = os.path.join(d, 'kernel.txt')
    kern = open(kf).read().split('\n') if os.path.exists(kf) else []
    m = re.match(r'cumulative c(\d+) test-cumulative ([0-9a-f]+) ', kern[0]) if kern else None
    kn = int(m.group(1)) if m else None
    upsize_fix = kernel_has(m.group(2) if m else None, UPSIZE_SHA)
    print(f'# job {job}; kernel: {" / ".join(k for k in kern if k)}; contains the upsize fix {UPSIZE_SHA[:9]}: {upsize_fix}')
    expected_not_success = dict(EXPECTED_NOT_SUCCESS)
    if upsize_fix:
        del expected_not_success[SVC_UPSIZE]
    pf = os.path.join(d, 'out', 'pre.md')
    pre = read_md(pf).get(GOOD) if os.path.exists(pf) else None
    print(f'# pre-flight {GOOD}: {pre}')
    for c in chunks:
        f = os.path.join(d, 'out', c + '.md')
        if not os.path.exists(f):
            missing.append(c); continue
        r = read_md(f)
        res.update(r)
        print(f'# {c}: {len(r)} vectors in {f} (expected {EXPECTED_TOTAL[c]})')
    for name in sorted(res):
        print(f'{name} [{group(name)}] {res[name]}')
    print()
    print('| group | success | total | failing |')
    print('|---|---|---|---|')
    if job == 'upsize':
        checks = [(f'0 kernel contains the upsize fix {UPSIZE_SHA[:9]} (fix/sunxi-cedrus-vp9-inter-upsize) and the pre-flight vector decoded',
                   upsize_fix and pre == 'Success',
                   f'kernel.txt: {kern[0] if kern else "missing"}; contains fix: {upsize_fix}; pre-flight {GOOD}: {pre}')]
    else:
        checks = [('0 kernel is a cumulative kernel >= c10 (contains f8be54bac) and the pre-flight vector decoded',
                   kn is not None and kn >= FIX_KERNEL and pre == 'Success',
                   f'kernel.txt: {kern[0] if kern else "missing"}; pre-flight {GOOD}: {pre}')]
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
    exp = '/'.join(str(EXPECTED_TOTAL[c]) for c in chunks)
    checks.append((f'1 all chunks ran ({" ".join(chunks)}.md present, {exp} vectors)', not missing and len(res) == nvec,
                   f'missing chunks: {missing}; vectors seen: {len(res)} of {nvec}'))
    if job == 'upsize':
        # CHECK 2: the upsize fix: svc_1280x720_3 (320x180 -> 640x360 -> 1280x720 on inter frames) decodes bit-exact
        svc = res.get(SVC_UPSIZE)
        checks.append(('2 inter-frame UPSIZE vector vp90-2-22-svc_1280x720_3 Success', svc == 'Success', f'result: {svc}'))
    # CHECK 3 (full: 2): every inter-frame downsize vector decodes bit-exact
    ri = bygroup.get(RESIZE_INTER, [])
    ri_bad = [n for n, r in ri if r != 'Success']
    checks.append((f'{3 if job == "upsize" else 2} inter-frame downsize vectors (24 x vp90-2-21-resize_inter_*, 05-resize, 18-resize) all Success',
                   len(ri) == 26 and not ri_bad, f'{len(ri) - len(ri_bad)}/{len(ri)} Success; failing: {" ".join(ri_bad)}'))
    # every other vector that the hardware can decode is Success
    other_bad = sorted(n for n, r in res.items() if r != 'Success' and n not in expected_not_success
                       and group(n) != RESIZE_INTER and n != SVC_UPSIZE)
    if job == 'upsize':
        checks.append(('4 regression subset (u2, 25 profile-0 vectors) all Success', not other_bad,
                       f'{len(other_bad)} failing: {" ".join(other_bad)}'))
    else:
        checks.append(('3 every other decodable vector Success (302 of the 305 + 10-bit 4:2:0 of HIGH)', not other_bad,
                       f'{len(other_bad)} failing: {" ".join(other_bad)}'))
        # CHECK 4: expected-unsupported vectors (information: a Success is a finding, not a failure)
        unexpected_ok = sorted(n for n in expected_not_success if res.get(n) == 'Success')
        svc_note = '' if upsize_fix else ', svc_1280x720_3'
        checks.append((f'4 expected-unsupported vectors (2 x vp91{svc_note}, 12-bit, vp93) are not Success', not unexpected_ok,
                       f'unexpectedly Success: {" ".join(unexpected_ok)}' if unexpected_ok else 'as expected'))
    # CHECK 5: dmesg clean
    bad_lines = []
    for f in sorted(glob.glob(os.path.join(d, 'dmesg-*.txt'))):
        for line in open(f, errors='replace'):
            if re.search(r'timed out|Oops|BUG:|WARNING|Page fault|iommu.*\bfault|alloc fail', line, re.I):
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
    if job == 'upsize':
        print(f'VERDICT: {"PASS" if allok else "FAIL"}; upsize job {total}/{len(res)} Success (of {nvec}), '
              f'svc_1280x720_3 {res.get(SVC_UPSIZE)}')
    else:
        print(f'VERDICT: {"PASS" if allok else "FAIL"}; VP9-TEST-VECTORS {p0}/305 Success, HIGH {total - p0}/6 Success')

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.', sys.argv[2] if len(sys.argv) > 2 else 'full')
