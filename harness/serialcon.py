#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Drive the Orange Pi Zero2 serial console for harness/reflash.sh.

Reads what the board prints from harness/serial.log (written by scripts/serial-log.py, which must be
running) and writes to /dev/ttyOPIZ2 only (the udev symlink for OUR CP2102 on USB port 3-4; never
ttyUSB0, which belongs to the orangepi5 project).

  serialcon.py uboot-pxe   [--timeout S] [--dry-run]  interrupt autoboot, run dhcp + pxe boot, wait for "Starting kernel"
  serialcon.py wait-flasher [--timeout S]             wait for "FLASHER: RESULT OK" (exit 0) or "FLASHER: FAIL" (exit 1)
  serialcon.py firstlogin  [--timeout S] [--dry-run]  answer Armbian's first-login wizard with local.env credentials
  serialcon.py shell CMD   [--timeout S] [--expect RE] run CMD at the logged-in root shell, print its output

Credentials come from local.env (OPIZ2_USER, OPIZ2_PASSWORD) and are never printed: every line this
tool prints has the password masked.
"""
import argparse, os, re, sys, time

HARNESS = os.path.dirname(os.path.abspath(__file__))
TOP = os.path.dirname(HARNESS)
LOG = os.environ.get('SERIALCON_LOG', os.path.join(HARNESS, 'serial.log'))  # override only for tests
PORT = '/dev/ttyOPIZ2'
ANSI = re.compile(r'\x1b\[[0-9;?]*[a-zA-Z]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|\r')
SECRETS = []


def mask(s):
    for p in SECRETS:
        if p:
            s = s.replace(p, '***')
    return s


def say(*a):
    print(mask(' '.join(str(x) for x in a)), flush=True)


def load_env():
    env = {}
    with open(os.path.join(TOP, 'local.env')) as f:
        for l in f:
            l = l.strip()
            if '=' in l and not l.startswith('#'):
                k, v = l.split('=', 1)
                env[k.strip()] = v.strip().strip('"').strip("'")
    for k in ('OPIZ2_USER', 'OPIZ2_PASSWORD'):
        if not env.get(k):
            sys.exit(f'{k} missing in local.env')
    SECRETS.append(env['OPIZ2_PASSWORD'])
    SECRETS.append(env['OPIZ2_USER'])
    return env


class Console:
    def __init__(self, dry=False):
        self.dry = dry
        if os.path.realpath(PORT) == '/dev/ttyUSB0':
            sys.exit(f'{PORT} resolves to /dev/ttyUSB0 (orangepi5 project): refusing')
        if not os.path.exists(PORT):
            sys.exit(f'{PORT} missing (install harness/99-opiz2-serial.rules)')
        if not os.path.exists(LOG) or time.time() - os.path.getmtime(LOG) > 24 * 3600:
            say(f'WARNING: {LOG} looks stale; is scripts/serial-log.py running?')
        self.pos = os.path.getsize(LOG)
        self.buf = ''
        self.ser = None
        if not dry:
            import serial
            self.ser = serial.Serial(PORT, 115200)

    def write(self, data, show=True):
        if show:
            say('  >>', repr(data))
        if not self.dry:
            self.ser.write(data.encode() if isinstance(data, str) else data)

    def read_new(self):
        with open(LOG, 'rb') as f:
            f.seek(self.pos)
            raw = f.read()
        self.pos += len(raw)
        text = raw.decode('utf8', 'replace')
        # strip the logger's "[HH:MM:SS.mmm] " prefixes
        text = re.sub(r'(?m)^\[\d\d:\d\d:\d\d\.\d{3}\] ', '', text)
        text = ANSI.sub('', text)
        self.buf = (self.buf + text)[-8000:]
        return text

    def wait(self, pattern, timeout, poll=0.2, echo=False, on_tick=None):
        """Wait until pattern matches new console text; return the match (or None on timeout)."""
        rx = re.compile(pattern)
        t0 = time.time()
        while time.time() - t0 < timeout:
            new = self.read_new()
            if echo and new:
                for l in new.splitlines():
                    if l.strip() and '3008;' not in l:
                        say('  |', l[:200])
            m = rx.search(self.buf)
            if m:
                self.seen = self.buf[:m.end()]  # console text up to and including the match
                self.buf = self.buf[m.end():]
                return m
            if on_tick:
                on_tick()
            time.sleep(poll)
        return None


def cmd_uboot_pxe(a):
    c = Console(a.dry_run)
    # dhcp with autoload off: only lease + serverip. Then clear bootfile: U-Boot's pxe derives its
    # path prefix from it (pxe_setup_ctx()), and the networkd hint BootFilename=pxelinux.cfg/default-arm-sunxi
    # would turn every relative fetch into pxelinux.cfg/<file>.
    cmds = ['setenv autoload no', 'dhcp', 'setenv serverip ' + a.server, 'setenv bootfile', 'pxe get', 'pxe boot']
    if a.dry_run:
        say('dry-run: would wait for "U-Boot SPL"/"Hit any key to stop autoboot", send Ctrl-C/space until "=> ",')
        say('         then send:', ' ; '.join(cmds), '; and wait for "Starting kernel"')
        return 0
    say(f'waiting up to {a.timeout}s for U-Boot on the console ...')
    if not c.wait(r'U-Boot SPL|U-Boot 20\d\d|Hit any key to stop autoboot', a.timeout, poll=0.05):
        say('no U-Boot banner seen'); return 2
    # bootdelay is 1 s: hammer the console until the prompt shows
    t0 = time.time()
    while time.time() - t0 < 20:
        c.write(b'\x03 ', show=False)
        if c.wait(r'(?m)^=> ?$|\n=> ', 0.1, poll=0.05):
            break
    else:
        say('autoboot was not interrupted (no "=>" prompt)'); return 3
    say('U-Boot prompt reached')
    time.sleep(0.3)
    c.write(b'\x03'); c.wait(r'=> ', 2)
    bad = {'dhcp': r'Retry count exceeded|TIMEOUT|Abort|No ethernet found',
           'pxe get': r'Config file not found|not set|Error|TIMEOUT'}
    for cmd in cmds[:-1]:
        c.write(cmd + '\n')
        if not c.wait(r'=> ', 90, echo=True):
            say(f'no prompt after {cmd!r}'); return 4
        if cmd in bad and re.search(bad[cmd], c.seen):
            say(f'{cmd!r} failed'); return 5
    c.write(cmds[-1] + '\n')
    if c.wait(r'Starting kernel', 180, echo=True):
        say('kernel started'); return 0
    say('kernel did not start'); return 6


def cmd_wait_flasher(a):
    c = Console(dry=True)  # read-only
    m = c.wait(r'FLASHER: (RESULT OK[^\n]*|FAIL[^\n]*)', a.timeout, poll=1, echo=True)
    if not m:
        say('flasher: no result within timeout'); return 2
    say('flasher:', m.group(1))
    return 0 if m.group(1).startswith('RESULT OK') else 1


def cmd_firstlogin(a):
    env = load_env()
    pw, user = env['OPIZ2_PASSWORD'], env['OPIZ2_USER']
    rules = [  # (prompt regex, answer); None answer = done
        (r'Press Enter to start', ''),
        (r'[Cc]reate root password', pw), (r'[Rr]epeat root password', pw),
        (r'[Cc]hoose default system command shell', ''), (r'shell:\s*$', '1'),
        (r'[Pp]rovide a username', user),
        (r'[Cc]reate user \(.*\) password', pw), (r'[Rr]epeat user \(.*\) password', pw),
        (r'[Pp]rovide your real name', 'Arun Iyengar'),
        (r'language based on your location', 'n'),
        (r'\[Y/n\]|\[y/N\]', 'n'),
        (r'root@orangepizero2:~#\s*$', None),
    ]
    if a.dry_run:
        say('dry-run: first-login wizard answers (secrets masked):')
        for p, ans in rules:
            shown = '<done>' if ans is None else '<password>' if ans == pw else '<username>' if ans == user else repr(ans)
            say(f'  {p!r:48} -> {shown}')
        return 0
    c = Console()
    c.write('\n', show=False)
    t0 = time.time()
    while time.time() - t0 < a.timeout:
        c.read_new()
        tail = c.buf[-400:]
        last = tail.splitlines()[-1] if tail.splitlines() else ''
        for p, ans in rules:
            if re.search(p, last) or (ans is not None and re.search(p + r'[^\n]*$', tail)):
                if ans is None:
                    say('first login done: root shell ready'); return 0
                say('prompt:', p)
                c.write(ans + '\n', show=False)
                c.buf = ''
                time.sleep(1.5)
                break
        else:
            time.sleep(1)
    say('first login: timeout; last console text:', repr(c.buf[-300:]))
    return 2


def cmd_shell(a):
    c = Console()
    tag = f'__done_{int(time.time())}__'
    c.write(a.cmd + f'; echo {tag} rc=$?\n')
    m = c.wait(re.escape(tag) + r' rc=(\d+)', a.timeout, echo=True)
    if not m:
        say('no completion marker'); return 2
    if a.expect and not re.search(a.expect, c.buf + m.string):
        say('expected output not seen'); return 3
    return int(m.group(1))


def main():
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest='sub', required=True)
    p = sp.add_parser('uboot-pxe'); p.add_argument('--timeout', type=int, default=180); p.add_argument('--dry-run', action='store_true'); p.add_argument('--server', default='10.56.0.1')
    p = sp.add_parser('wait-flasher'); p.add_argument('--timeout', type=int, default=1800)
    p = sp.add_parser('firstlogin'); p.add_argument('--timeout', type=int, default=600); p.add_argument('--dry-run', action='store_true')
    p = sp.add_parser('shell'); p.add_argument('cmd'); p.add_argument('--timeout', type=int, default=60); p.add_argument('--expect')
    a = ap.parse_args()
    return {'uboot-pxe': cmd_uboot_pxe, 'wait-flasher': cmd_wait_flasher, 'firstlogin': cmd_firstlogin, 'shell': cmd_shell}[a.sub](a)


if __name__ == '__main__':
    sys.exit(main())
