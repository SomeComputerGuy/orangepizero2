#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Compare the board FFmpeg AVS2 results (board-avs2-ffmpeg.sh) with the references.

  cmp-avs2-ffmpeg.py <outdir> <board-log>

PKU streams: whole-stream md5 against repo/ES/<name>/md5.txt and per-frame md5s against the
avs2dec board run (kernel-check/avs2-board/out8/<name>.txt). xavs2-made streams: per-frame md5s
against davs2 (kernel-check/avs2-es/<name>.davs2-8.framemd5); cctv4k-10bit: against the avs2dec P010
self-consistency run (kernel-check/avs2-board/out10/cctv4k-10bit.p010-a.txt, 16-bit LE 10-bit samples). Prints one row per stream:
name, frames, md5 match, frame match, fps (frames / rtime of the DRM_PRIME null run).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__)) + '/../..'
PKU = ROOT + '/kernel-check/dl-avs2/streams-gitee-hwren/repo/ES'
OUT8 = ROOT + '/kernel-check/avs2-board/out8'
ES = ROOT + '/kernel-check/avs2-es'


def framemd5(path):
    """ffmpeg framemd5 output -> list of md5s in output order."""
    res = []
    for line in open(path):
        if line.startswith('#') or not line.strip():
            continue
        res.append(line.split(',')[-1].strip())
    return res


def ref_frames(name):
    """Reference per-frame md5s: avs2dec board run (PKU) or davs2 (xavs2 streams)."""
    for p in (f'{OUT8}/{name}.txt', f'{ES}/{name}.davs2-8.framemd5',
              f'{OUT8}/../out10/{name}.p010-a.txt'):
        if os.path.exists(p):
            return [l.split()[-1] for l in open(p) if l.startswith('frame ')]
    return None


def main(outdir, log):
    rows = []
    for line in open(log):
        m = re.match(r'(\S+) rc=(\d+) frames=(\d+) (?:MD5=(\w+))?\s*(?:rtime=([0-9.]+)s)?', line)
        if not m:
            continue
        name, rc, n, md5, rtime = m.groups()
        n = int(n)
        total = 'n/a'
        p = f'{PKU}/{name}/md5.txt'
        if os.path.exists(p):
            ref = open(p).read().split()[0].lower()
            total = 'MATCH' if md5 and md5.lower() == ref else f'DIFF (ref {ref})'
        frames = 'n/a'
        ref = ref_frames(name)
        got = framemd5(f'{outdir}/{name}.framemd5') if os.path.exists(f'{outdir}/{name}.framemd5') else []
        if ref is not None:
            if got == ref:
                frames = f'MATCH {len(got)}/{len(ref)}'
            else:
                bad = [i for i in range(min(len(got), len(ref))) if got[i] != ref[i]]
                frames = f'DIFF {len(got)} vs {len(ref)} frames, first mismatch {bad[:3]}'
                if total == 'n/a' and not bad and len(got) == len(ref):
                    frames = f'MATCH {len(got)}/{len(ref)}'
        fps = f'{n / float(rtime):.1f}' if rtime and n else 'n/a'
        rows.append((name, rc, n, total, frames, fps))
    for r in rows:
        print('| %s | rc %s | %d | %s | %s | %s |' % r)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
