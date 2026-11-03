#!/usr/bin/env python3
import sys, numpy as np
W, H = 1920, 1080; fs = W * H * 3 // 2
hw = np.memmap(sys.argv[1], np.uint8, 'r'); sw = np.memmap(sys.argv[2], np.uint8, 'r')
Y = lambda a, i: a[i*fs:i*fs+W*H].reshape(H, W).astype(int)
print('frames hw', hw.size // fs, 'sw', sw.size // fs)
h24, s24, s22 = Y(hw, 24), Y(sw, 24), Y(sw, 22)
pred = np.vstack([s22[2:], s22[-1:].repeat(2, 0)])  # ref shifted down 2 px: pred(y) = ref(y + 2)
print('mb  |HW-SW| max/mean   |HW-pred| max/mean   |SW-pred| max/mean')
for c in range(11):
    sl = (slice(0, 16), slice(c*16, c*16+16))
    f = lambda a, b: f'{np.abs(a[sl]-b[sl]).max():4d}/{np.abs(a[sl]-b[sl]).mean():6.2f}'
    print(f'{c:2d}  {f(h24, s24)}          {f(h24, pred)}            {f(s24, pred)}')
for i in (22, 23, 24, 25):
    d = np.abs(Y(hw, i) - Y(sw, i)); big = np.argwhere(d > 4)
    print('frame', i, 'max', d.max(), 'MBs>4', sorted({(r // 16, c // 16) for r, c in big})[:20])
