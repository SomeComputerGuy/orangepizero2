#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""HTTP server for the netboot flasher (harness/flasher/init).

Serves exactly two things from the newest Armbian image (or --image):
  GET /manifest        IMAGE=<name>.img.xz, SHA256=<uncompressed sha256>, SIZE=<uncompressed bytes>
  GET /<name>.img.xz   the compressed image
  GET /report?status=ok|fail&detail=...   the flasher's result; logged, and written to --status-file
Anything else is 404. The uncompressed checksum is computed once per image (xz -dc | sha256)
and cached next to --cache-dir keyed by name, size and mtime.

  serve-image.py [--bind 10.56.0.1] [--port 8080] [--image X.img.xz] [--manifest-only]
"""
import argparse, glob, hashlib, http.server, json, os, subprocess, sys, time, urllib.parse

TOP = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
IMAGES = os.path.join(TOP, 'armbian-build', 'output', 'images')


def newest_image():
    imgs = sorted(glob.glob(os.path.join(IMAGES, '*Orangepizero2*.img.xz')), key=os.path.getmtime)
    if not imgs:
        sys.exit(f'no *Orangepizero2*.img.xz in {IMAGES}')
    return imgs[-1]


def manifest(image, cache_dir):
    st = os.stat(image)
    os.makedirs(cache_dir, exist_ok=True)
    key = os.path.join(cache_dir, f'{os.path.basename(image)}.{st.st_size}.{int(st.st_mtime)}.json')
    if os.path.exists(key):
        with open(key) as f:
            return json.load(f)
    print(f'computing the uncompressed sha256 of {image} ...', file=sys.stderr, flush=True)
    h, n = hashlib.sha256(), 0
    p = subprocess.Popen(['xz', '-dc', '-T0', image], stdout=subprocess.PIPE)
    while True:
        b = p.stdout.read(1 << 20)
        if not b:
            break
        h.update(b)
        n += len(b)
    if p.wait() != 0:
        sys.exit('xz -dc failed')
    m = {'IMAGE': os.path.basename(image), 'SHA256': h.hexdigest(), 'SIZE': n}
    with open(key, 'w') as f:
        json.dump(m, f)
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bind', default='10.56.0.1')
    ap.add_argument('--port', type=int, default=8080)
    ap.add_argument('--image')
    ap.add_argument('--cache-dir', default=os.path.join(TOP, 'kernel-check', 'work-flasher', 'manifests'))
    ap.add_argument('--status-file', default=os.path.join(TOP, 'kernel-check', 'work-flasher', 'flasher-status'))
    ap.add_argument('--manifest-only', action='store_true', help='print the manifest and exit')
    a = ap.parse_args()
    image = os.path.abspath(a.image or newest_image())
    m = manifest(image, a.cache_dir)
    body = ''.join(f'{k}={v}\n' for k, v in m.items()).encode()
    if a.manifest_only:
        sys.stdout.write(body.decode())
        return

    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            print(time.strftime('%H:%M:%S'), self.client_address[0], fmt % args, file=sys.stderr, flush=True)

        def do_GET(self):
            u = urllib.parse.urlparse(self.path)
            if u.path == '/manifest':
                return self.send(200, body, 'text/plain')
            if u.path == '/' + m['IMAGE']:
                size = os.path.getsize(image)
                self.send_response(200)
                self.send_header('Content-Type', 'application/x-xz')
                self.send_header('Content-Length', str(size))
                self.end_headers()
                with open(image, 'rb') as f:
                    while True:
                        b = f.read(1 << 20)
                        if not b:
                            break
                        try:
                            self.wfile.write(b)
                        except (BrokenPipeError, ConnectionResetError):
                            return
                return
            if u.path == '/report':
                q = urllib.parse.parse_qs(u.query)
                line = f"{time.strftime('%FT%TZ', time.gmtime())} {self.client_address[0]} status={q.get('status', ['?'])[0]} detail={q.get('detail', [''])[0]}\n"
                with open(a.status_file, 'a') as f:
                    f.write(line)
                print('REPORT', line.strip(), file=sys.stderr, flush=True)
                return self.send(200, b'ok\n', 'text/plain')
            self.send(404, b'not found\n', 'text/plain')

        def send(self, code, data, ctype):
            self.send_response(code)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    print(f'serving {image} on http://{a.bind}:{a.port}/ ({m["SIZE"]} bytes, sha256 {m["SHA256"]})', file=sys.stderr, flush=True)
    http.server.ThreadingHTTPServer((a.bind, a.port), H).serve_forever()


if __name__ == '__main__':
    main()
