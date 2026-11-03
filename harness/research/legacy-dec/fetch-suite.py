#!/usr/bin/env python3
# Usage: python3 -I fetch-suite.py <fluster-suite.json> <outdir> [skip-substring...]
# Downloads each vector's source (deduped), checks md5 vs source_checksum, extracts only input_file
# to <outdir>/bits/<vector-name>.<ext>, writes <outdir>/SHA256SUMS (archives + bitstreams) and vectors.tsv
# (name, bitstream, fluster result md5, output_format). Data only: nothing downloaded is executed.
import json, sys, os, hashlib, gzip, zipfile, tarfile, urllib.request, shutil, concurrent.futures as cf
suite, out = sys.argv[1], sys.argv[2]; skip = sys.argv[3:]
d = json.load(open(suite)); os.makedirs(out + '/src', exist_ok=True); os.makedirs(out + '/bits', exist_ok=True)
vecs = [v for v in d['test_vectors'] if not any(s in v['source'] for s in skip)]
def md5(p):
    h = hashlib.md5(); f = open(p, 'rb')
    for b in iter(lambda: f.read(1 << 20), b''): h.update(b)
    return h.hexdigest()
def fetch(url):
    p = out + '/src/' + hashlib.sha1(url.encode()).hexdigest()[:8] + '_' + url.split('/')[-1]
    if not os.path.exists(p):
        req = urllib.request.Request(url, headers={'User-Agent': 'curl/8'})
        with urllib.request.urlopen(req, timeout=600) as r, open(p + '.part', 'wb') as f: shutil.copyfileobj(r, f)
        os.rename(p + '.part', p)
    return url, p
srcs = {}
with cf.ThreadPoolExecutor(8) as ex:
    for url, p in ex.map(fetch, sorted({v['source'] for v in vecs})): srcs[url] = p
rows = []
for v in vecs:
    p = srcs[v['source']]; ok = (md5(p) == v.get('source_checksum') or not v.get('source_checksum'))
    inp = v['input_file']; dst = out + '/bits/' + v['name'] + os.path.splitext(inp)[1]
    try:
        if p.endswith('.zip'):
            z = zipfile.ZipFile(p); m = [n for n in z.namelist() if n == inp or n.endswith('/' + inp)][0]
            with z.open(m) as s, open(dst, 'wb') as f: shutil.copyfileobj(s, f)
        elif p.endswith(('.tgz', '.tar.gz')):
            t = tarfile.open(p); m = [n for n in t.getmembers() if n.isfile() and (n.name == inp or n.name.endswith('/' + inp))][0]
            with t.extractfile(m) as s, open(dst, 'wb') as f: shutil.copyfileobj(s, f)
        elif p.endswith('.gz'):
            with gzip.open(p) as s, open(dst, 'wb') as f: shutil.copyfileobj(s, f)
        else:
            shutil.copyfile(p, dst)
    except Exception as e:
        print('EXTRACT-FAIL', v['name'], e); dst = ''
    rows.append((v['name'], os.path.basename(dst), v.get('result', ''), v.get('output_format', ''), 'srcmd5-ok' if ok else 'SRCMD5-BAD'))
with open(out + '/vectors.tsv', 'w') as f:
    for r in rows: f.write('\t'.join(r) + '\n')
with open(out + '/SHA256SUMS', 'w') as f:
    for q in sorted(set(srcs.values())) + sorted(out + '/bits/' + r[1] for r in rows if r[1]):
        h = hashlib.sha256(open(q, 'rb').read()).hexdigest(); f.write(h + '  ' + os.path.relpath(q, out) + '\n')
print(suite, len(rows), 'vectors;', sum(r[4] != 'srcmd5-ok' for r in rows), 'bad source md5')
