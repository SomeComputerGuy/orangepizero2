#!/usr/bin/env python3
# Read raw frames (NV12 or P010) from stdin; print total md5 and write per-frame md5 list to argv[3].
# argv: W H OUTLIST BYTES_PER_SAMPLE [CHUNK]
# env DUMP=1,2,3 : save these frames to /root/vdec-out/frameN.raw
# env REF=<ffmpeg framemd5 file> : save every frame whose md5 differs from REF (at most 4) to /root/vdec-out/bad-N.raw
import sys, hashlib, os
w, h, bpp = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[4])
size = w * h * 3 // 2 * bpp
chunk = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] else size
dump = set(int(x) for x in os.environ.get("DUMP", "").split(",") if x)
ref = []
if os.environ.get("REF"):
    ref = [l.split(",")[-1].strip() for l in open(os.environ["REF"]) if not l.startswith("#")]
tot = hashlib.md5(); n = 0; saved = 0
with open(sys.argv[3], "w") as out:
    buf = sys.stdin.buffer
    while True:
        d = buf.read(chunk)
        if len(d) == chunk: d = d[:size]
        if not d: break
        m = hashlib.md5(d).hexdigest()
        if n in dump: open(f"/root/vdec-out/frame{n}.raw", "wb").write(d)
        if ref and n < len(ref) and m != ref[n] and saved < 4:
            open(f"/root/vdec-out/bad-{n}.raw", "wb").write(d); saved += 1
        tot.update(d); out.write(f"{n} {m} {len(d)}\n"); n += 1
print(f"frames={n} md5={tot.hexdigest()}")
