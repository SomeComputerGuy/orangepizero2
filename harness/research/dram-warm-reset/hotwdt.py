#!/usr/bin/env python3
# Host driver: hot-OOM hardware-watchdog reset loop. usage: hotwdt.py LABEL N MODE TIMEOUT HEAT OUTFILE
#  MODE=holder : our /dev/watchdog0 holder (TIMEOUT s) stops petting after HEAT s of stress+OOM
#  MODE=livelock: systemd keeps the watchdog (15 s); stress+bigheap until real OOM livelock; systemd's pet stalls
import subprocess, sys, time, re, os, datetime
label, N, mode, tmo, heat, out = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
H = '/home/aruni/orangepizero2/harness'; LOG = H + '/serial.log'
SSH = [H + '/ssh.sh']
def ssh(cmd, inp=None, t=30):
    try: return subprocess.run(SSH + [cmd], input=inp, capture_output=True, text=True, timeout=t)
    except subprocess.TimeoutExpired: return None
def ts2sec(s):  # serial ts HH:MM:SS.mmm -> seconds of day
    h, m, x = s.split(':'); return int(h) * 3600 + int(m) * 60 + float(x)
def now_sod():
    d = datetime.datetime.now(); return d.hour * 3600 + d.minute * 60 + d.second + d.microsecond / 1e6
def wait_ssh(limit=600):
    t0 = time.time()
    while time.time() - t0 < limit:
        r = ssh('cat /proc/sys/kernel/random/boot_id', t=10)
        if r and r.returncode == 0: return r.stdout.strip()
        time.sleep(2)
    return None
holder = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'wdhold.py')).read()
STRESS = 'stress-ng --cpu 4 --cpu-method matrixprod --vm 2 --vm-bytes 100% --vm-keep --bigheap 1 -t 900s'
for i in range(1, N + 1):
    bid0 = wait_ssh()
    if not bid0: print('board not answering ssh, abort'); sys.exit(1)
    off = os.path.getsize(LOG)
    r = ssh('cat > /tmp/wdhold.py', inp=holder)
    if mode == 'holder':
        setup = ('busctl set-property org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager RuntimeWatchdogUSec t 0; '
                 'sleep 0.5; fuser /dev/watchdog0 2>&1; '
                 f'setsid nohup python3 /tmp/wdhold.py {tmo} {heat} timed >/tmp/wdhold.out 2>&1 < /dev/null & sleep 1; '
                 'H=$(pgrep -f -n "python3 /tmp/wdhold.py"); echo holder=$H; fuser /dev/watchdog0 2>&1; '
                 'if ! fuser /dev/watchdog0 2>/dev/null | grep -qw "$H"; then cat /tmp/wdhold.out; '
                 'busctl set-property org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager RuntimeWatchdogUSec t 15000000; echo HOLDER-FAIL; exit 1; fi; '
                 f'setsid nohup {STRESS} >/tmp/sng.log 2>&1 < /dev/null & sleep 1; echo started')
    else:
        pre_cmd = 'sysctl -q -w vm.panic_on_oom=1 kernel.panic=0; cat /proc/sys/vm/panic_on_oom /proc/sys/kernel/panic; fuser /dev/watchdog0 2>&1; ' if mode == 'oompanic' else ''
        setup = (pre_cmd + f'setsid nohup python3 /tmp/wdhold.py 0 {heat} mon >/tmp/wdhold.out 2>&1 < /dev/null & sleep 1; '
                 f'setsid nohup {STRESS} >/tmp/sng.log 2>&1 < /dev/null & sleep 1; echo started')
    r = ssh(setup, t=40)
    info = (r.stdout + r.stderr).replace('\n', ' ') if r else 'setup-ssh-timeout'
    if 'HOLDER-FAIL' in info: print('holder failed:', info); sys.exit(1)
    # wait for an SPL banner after off
    t0 = time.time(); txt = ''; spl = None
    while time.time() - t0 < 1200:
        time.sleep(3)
        with open(LOG, 'rb') as f:
            f.seek(off); txt = f.read().decode('latin-1')
        m = re.search(r'\[(\d\d:\d\d:\d\d\.\d+)\] U-Boot SPL', txt)
        if m:
            spl = m; break
    if not spl: print(f'{label} {i}: no reset within 20 min'); sys.exit(1)
    time.sleep(8)
    bid1 = wait_ssh(); up = now_sod()
    with open(LOG, 'rb') as f:
        f.seek(off); txt = f.read().decode('latin-1')
    pre, post = txt[:spl.start()], txt[spl.start():]
    stop = re.findall(r'\[(\d\d:\d\d:\d\d\.\d+)\][^\n]*wdhold: STOP[^\n]*?(cpu=\d+ ddr=\d+)', pre)
    pets = re.findall(r'\[(\d\d:\d\d:\d\d\.\d+)\][^\n]*?wdhold: (?:pet|no-pet|mon)[^\n]*?(cpu=\d+ ddr=\d+)', pre)
    last = pets[-1] if pets else ('?', '?')
    ooms = len(re.findall(r'Out of memory: Killed', pre))
    reboot = 'reboot:' in pre or 'Restarting system' in pre
    dram = [l.split('] ', 1)[1].strip() for l in post.split('\n') if 'DRAM:' in l or 'not supported' in l or 'resetting' in l or 'retried' in l][:6]
    nspl = len(re.findall(r'U-Boot SPL', post.split('login:')[0]))
    spl_s = ts2sec(spl.group(1))
    if stop:
        gap = '%.1f' % (spl_s - ts2sec(stop[-1][0])); stemp = stop[-1][1]
    else:
        gap = 'n/a'; stemp = 'n/a'
    pm = re.findall(r'\[(\d\d:\d\d:\d\d\.\d+)\][^\n]*Kernel panic - not syncing: ([^\n]{0,60})', pre)
    if pm: gap = '%.1f(panic->SPL; panic=%s)' % (spl_s - ts2sec(pm[0][0]), pm[0][1].strip())
    lastgap = '%.1f' % (spl_s - ts2sec(last[0])) if last[0] != '?' else '?'
    mt = ssh('grep MemTotal /proc/meminfo; systemctl show -p RuntimeWatchdogUSec; fuser /dev/watchdog0 2>&1', t=20)
    mt = mt.stdout.replace('\n', ' ').strip() if mt else '?'
    sshup = '%.1f' % (up - spl_s)
    line = (f'{label} {i}: mode={mode} tmo={tmo} heat={heat} temp-at-stop=[{stemp}] last-temp-before-reset=[{last[1]}] '
            f'(logged {lastgap}s before SPL) stop->SPL={gap}s oom-kills={ooms} reboot-msg={reboot} spl-passes={nspl} '
            f'dram={dram} {mt} ssh-up={sshup}s-after-SPL newboot={bid1 != bid0} setup=[{info.strip()}]')
    print(line, flush=True)
    open(out, 'a').write(line + '\n')
    time.sleep(20)
