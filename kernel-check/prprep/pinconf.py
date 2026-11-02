#!/usr/bin/env python3
"""List pin claims of enabled nodes in a decompiled DTS (dtc -I dtb -O dts) and report pins
claimed by more than one enabled device. Usage: pinconf.py file.dts"""
import re, sys
txt = open(sys.argv[1]).read()
# parse nodes into (path, props) with a tiny brace parser
nodes = {}; stack = []; ph = {}
for line in txt.splitlines():
    l = line.strip()
    m = re.match(r'(?:[\w,-]+:\s*)?([\w,@.+-]+|/)\s*\{$', l)
    if m:
        stack.append(m.group(1)); path = '/' + '/'.join(stack[1:]); nodes[path] = {}; continue
    if l == '};':
        stack.pop(); continue
    m = re.match(r'([\w,#.+-]+)\s*=\s*(.*);$', l)
    if m and stack:
        path = '/' + '/'.join(stack[1:]); nodes[path][m.group(1)] = m.group(2)
for p, pr in nodes.items():
    if 'phandle' in pr: ph[int(pr['phandle'].strip('<>'), 16)] = p
def enabled(p):
    parts = p.split('/')
    for i in range(2, len(parts) + 1):
        q = '/'.join(parts[:i]) or '/'
        if nodes.get(q, {}).get('status', '"okay"').strip('"') not in ('okay', 'ok'): return False
    return True
claims = {}
for p, pr in nodes.items():
    if not enabled(p) or 'pinctrl@' in p: continue
    for k, v in pr.items():
        if not re.match(r'pinctrl-\d+$', k): continue
        for h in re.findall(r'0x[0-9a-f]+', v):
            grp = ph.get(int(h, 16))
            if not grp: continue
            for pin in re.findall(r'"(P[A-L]\d+)"', nodes[grp].get('pins', '')):
                claims.setdefault(pin, set()).add('%s(%s)' % (p.split('/')[-1], grp.split('/')[-1]))
bad = {k: v for k, v in claims.items() if len(v) > 1}
want = sys.argv[2:] 
for pin in sorted(claims):
    if not want or pin in want: print('claim', pin, ' '.join(sorted(claims[pin])))
for k in sorted(bad): print('CONFLICT', k, ' '.join(sorted(bad[k])))
print('conflicts:', len(bad))
