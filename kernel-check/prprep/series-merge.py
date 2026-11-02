#!/usr/bin/env python3
"""Replay the series.conf change of commit C onto the working-tree series.conf (context-free).
Usage: series-merge.py <armbian repo> <commit> <worktree series.conf path (relative)> [order-ref]
Removed lines are deleted where present. Each run of added lines is inserted after an anchor:
 - with order-ref: the nearest entry that precedes the run's first entry in order-ref's series.conf
   and exists in the target (so the result follows order-ref's ordering);
 - else: the nearest preceding post-image entry that exists in the target; a run appended at the
   end of the file stays at the end."""
import difflib, subprocess, sys
repo, c, rel = sys.argv[1:4]
oref = sys.argv[4] if len(sys.argv) > 4 else None
show = lambda r: subprocess.run(['git', '-C', repo, 'show', f'{r}:{rel}'], capture_output=True, text=True).stdout.splitlines()
entry = lambda l: bool(l.strip()) and not l.lstrip().startswith('#')
pre, post = show(c + '^'), show(c)
order = show(oref) if oref else None
tgt = open(rel).read().splitlines()
sm = difflib.SequenceMatcher(a=pre, b=post, autojunk=False)
for tag, i1, i2, j1, j2 in sm.get_opcodes():
    if tag in ('delete', 'replace'):
        for l in pre[i1:i2]:
            if entry(l) and l in tgt: tgt.remove(l)
    if tag not in ('insert', 'replace'): continue
    run = [l for l in post[j1:j2] if not (entry(l) and l in tgt)]
    if not run: continue
    pos = None
    first = next((l for l in run if entry(l)), None)
    if order is not None and first in order:
        for a in reversed(order[:order.index(first)]):
            if entry(a) and a in tgt:
                pos = tgt.index(a); break
    if pos is None:
        if j2 == len(post) and i2 == len(pre): pos = len(tgt) - 1
        else:
            for a in reversed(post[:j1]):
                if entry(a) and a in tgt:
                    pos = len(tgt) - 1 - tgt[::-1].index(a); break
    if pos is None: pos = -1
    tgt[pos + 1:pos + 1] = run
open(rel, 'w').write('\n'.join(tgt) + '\n')
