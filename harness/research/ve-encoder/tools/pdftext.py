# crude PDF text extractor: inflate FlateDecode streams, print Tj/TJ strings
import sys,re,zlib
d=open(sys.argv[1],'rb').read()
out=[]
for m in re.finditer(rb'stream\r?\n(.*?)\r?\nendstream',d,re.S):
    s=m.group(1)
    try: s=zlib.decompress(s)
    except Exception: continue
    if b'Tj' not in s and b'TJ' not in s: continue
    txt=[]
    for tm in re.finditer(rb'\[(.*?)\]\s*TJ|\((.*?)\)\s*Tj',s,re.S):
        if tm.group(1) is not None:
            parts=re.findall(rb'\((.*?)(?<!\\)\)',tm.group(1),re.S)
            txt.append(b''.join(parts))
        else: txt.append(tm.group(2))
    line=b' '.join(txt).replace(b'\\(',b'(').replace(b'\\)',b')')
    out.append(line.decode('latin-1'))
print('\n'.join(out))
