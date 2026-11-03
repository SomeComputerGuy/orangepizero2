import sys, os, re, email
from email import policy
src, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)
data = open(src, 'rb').read()
parts = re.split(rb'(?m)^From (?:mboxrd@z|[0-9a-f]{40}) ', data)
n = 0
for p in parts:
    if not p.strip():
        continue
    msg = email.message_from_bytes(b'From ' + p, policy=policy.compat32)
    subj = (msg['Subject'] or '').replace('\n', ' ')
    subj = re.sub(r'\s+', ' ', subj)
    m = re.match(r'\s*\[PATCH[^\]]*?(\d+)/(\d+)\]', subj)
    if not m or subj.startswith('Re:') or m.group(1) == '0':
        continue
    idx = int(m.group(1))
    body = msg.get_payload(decode=True) or b''
    if b'\ndiff --git' not in body and not body.startswith(b'diff --git'):
        continue
    name = re.sub(r'[^A-Za-z0-9._-]+', '-', subj.split(']', 1)[1].strip())[:70]
    fn = os.path.join(outdir, f'{idx:04d}-{name}.patch')
    with open(fn, 'wb') as f:
        f.write(b'From: ' + (msg['From'] or '').encode() + b'\nDate: ' + (msg['Date'] or '').encode() + b'\nSubject: ' + subj.encode() + b'\n\n' + body)
    n += 1
print(n, 'patches written to', outdir)
