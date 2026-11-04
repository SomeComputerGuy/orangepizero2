#!/usr/bin/env python3
# Usage: python3 -I m4v-types.py <stream (.avi via ffmpeg -c copy -f m4v first, or raw .m4v)> -> coded VOP types, decode order
import sys, re
b = open(sys.argv[1], 'rb').read()
print(''.join('IPBS'[b[m.end()] >> 6] for m in re.finditer(b'\x00\x00\x01\xb6', b)))
