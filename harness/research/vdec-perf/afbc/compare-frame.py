#!/usr/bin/env python3
# Localize an AFBC-check mismatch on the host: compare a linear frame written by afbc-gpu-check (-D dir, frame-N.<layout>)
# with the software decode of the same frame, per 16x16 superblock.
# Usage: compare-frame.py <stream> <N> <frame-N.layout> [p010le|nv12|yuv420p10le] [width height]
# For yuv420p10le the stream is an AVS2 ES: pass a reference .yuv (davs2/avs2dec output, same layout) as <stream> instead.
import sys, subprocess, numpy as np
stream, n, dump = sys.argv[1], int(sys.argv[2]), sys.argv[3]
layout = sys.argv[4] if len(sys.argv) > 4 else dump.rsplit('.', 1)[1]
w, h = (int(sys.argv[5]), int(sys.argv[6])) if len(sys.argv) > 6 else (3840, 2160)
bps = 2 if layout in ('p010le', 'yuv420p10le') else 1
fsz = w * h * 3 // 2 * bps
if layout == 'yuv420p10le':
    with open(stream, 'rb') as f:
        f.seek(n * fsz); ref = f.read(fsz)
else:
    ref = subprocess.run(['ffmpeg', '-v', 'error', '-i', stream, '-vf', 'select=eq(n\\,%d)' % n, '-frames:v', '1',
                          '-pix_fmt', layout, '-f', 'rawvideo', '-'], capture_output=True).stdout
got = open(dump, 'rb').read()
assert len(ref) == fsz and len(got) == fsz, (len(ref), len(got), fsz)
dt = np.uint16 if bps == 2 else np.uint8
R = np.frombuffer(ref, dt); G = np.frombuffer(got, dt)
shift = 6 if layout == 'p010le' else 0
Ry, Gy = (R[:w*h] >> shift).reshape(h, w), (G[:w*h] >> shift).reshape(h, w)
Rc, Gc = (R[w*h:] >> shift).reshape(h // 2, w), (G[w*h:] >> shift).reshape(h // 2, w)
dy = Ry != Gy; dc = Rc != Gc
print('frame %d %s: luma diffs %d (max |d| %d), chroma diffs %d' % (n, layout, dy.sum(), int(np.abs(Ry.astype(int) - Gy.astype(int)).max()), dc.sum()))
blk = np.zeros((h // 16, w // 16), bool)
for by in range(h // 16):
    for bx in range(w // 16):
        if dy[16*by:16*by+16, 16*bx:16*bx+16].any() or dc[8*by:8*by+8, 16*bx:16*bx+16].any():
            blk[by, bx] = True
ys, xs = np.nonzero(blk)
print('%d of %d superblocks differ' % (blk.sum(), blk.size))
for by, bx in list(zip(ys, xs))[:20]:
    sub = np.abs(Ry[16*by:16*by+16, 16*bx:16*bx+16].astype(int) - Gy[16*by:16*by+16, 16*bx:16*bx+16].astype(int))
    print('  block (%d,%d) px (%d,%d): %d luma px differ, max %d, ref[0,0]=%d got[0,0]=%d' % (bx, by, 16*bx, 16*by, (sub > 0).sum(), sub.max(), Ry[16*by, 16*bx], Gy[16*by, 16*bx]))
