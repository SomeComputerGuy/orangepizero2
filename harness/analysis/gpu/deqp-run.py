#!/usr/bin/env python3
"""Minimal crash-tolerant dEQP runner for the board (deqp-runner substitute, no extra deps).

Usage: deqp-run.py --deqp BIN --caselist FILE --out DIR [--jobs N] [--timeout S] [-- extra deqp args]

Splits the caselist into N shards. Each shard runs one dEQP process at a time on the
remaining cases, and parses stdout:
    Test case '<name>'..
      Pass (msg) | Fail (msg) | NotSupported (msg) | QualityWarning (msg) | ...
If a process dies mid-case, that case is recorded as Crash. If no line arrives for
--timeout seconds, the case is killed and recorded as Timeout. The shard then restarts at
the next case. Results go to OUT/results.csv as "test,status,duration_s,detail", in
caselist order, and the run can be resumed: cases already in OUT/shard-*.csv are skipped.
"""
import argparse, csv, json, os, re, selectors, subprocess, sys, threading, time

MESA_CI_ARGS = ["--deqp-surface-width=256", "--deqp-surface-height=256", "--deqp-surface-type=pbuffer",
                "--deqp-visibility=hidden", "--deqp-gl-config-name=rgba8888d24s8ms0",
                "--deqp-log-images=disable", "--deqp-log-shader-sources=disable", "--deqp-shadercache=disable",
                "--deqp-crashhandler=enable", "--deqp-watchdog=enable"]
RE_CASE = re.compile(r"^Test case '(.+)'\.\.$")
RE_RES = re.compile(r"^\s+(Pass|Fail|NotSupported|QualityWarning|CompatibilityWarning|InternalError|"
                    r"ResourceError|Crash|Timeout|Waiver|DeviceLost)\s*\((.*)\)\s*$")


def wait_for_memory(min_kb=350000, poll=60):
    """Board is shared with other agents: never start a test process while avs2dec runs or memory is short."""
    while True:
        busy = subprocess.run(["pgrep", "-x", "avs2dec"], stdout=subprocess.DEVNULL).returncode == 0
        avail = 0
        for l in open("/proc/meminfo"):
            if l.startswith("MemAvailable:"): avail = int(l.split()[1])
        if not busy and avail >= min_kb:
            return
        time.sleep(poll)


def oom_first():
    """deqp children are the OOM killer's first choice; the runner itself is protected (see main)."""
    with open("/proc/self/oom_score_adj", "w") as f:
        f.write("1000")


def run_shard(idx, cases, a, extra):
    path = os.path.join(a.out, "shard-%d.csv" % idx)
    done = set()
    if os.path.exists(path):
        with open(path) as f:
            done = {r[0] for r in csv.reader(f) if r}
    todo = [c for c in cases if c not in done]
    with open(path, "a", newline="") as fo:
        w = csv.writer(fo)
        kpath = os.path.join(a.out, "shard-%d.kills.json" % idx)  # persisted so a runner restart cannot loop
        kills = json.load(open(kpath)) if os.path.exists(kpath) else {}
        while todo:
            cl = os.path.join(a.out, "shard-%d.caselist" % idx)
            with open(cl, "w") as f:
                f.write("\n".join(todo) + "\n")
            cmd = [a.deqp, "--deqp-caselist-file=" + cl, "--deqp-log-filename=" + os.path.join(a.out, "shard-%d.qpa" % idx)] + MESA_CI_ARGS + extra
            wait_for_memory()
            p = subprocess.Popen(cmd, cwd=os.path.dirname(a.deqp), preexec_fn=oom_first, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, errors="replace", bufsize=1)
            sel = selectors.DefaultSelector(); sel.register(p.stdout, selectors.EVENT_READ)
            pos = {c: i for i, c in enumerate(todo)}
            cur, t0, tail, last = None, time.time(), [], -1
            while True:
                if not sel.select(timeout=a.timeout):
                    p.kill(); p.wait()
                    if cur:
                        w.writerow([cur, "Timeout", "%.1f" % (time.time() - t0), "no output for %ds" % a.timeout]); fo.flush()
                        todo = todo[pos[cur] + 1:]
                    break
                line = p.stdout.readline()
                if not line:
                    p.wait()
                    if cur and p.returncode == -9:  # OOM/external kill: retry once, then record OOM and move on
                        kills[cur] = kills.get(cur, 0) + 1
                        with open(kpath, "w") as kf:
                            json.dump(kills, kf)
                        if kills[cur] < 2:
                            todo = todo[pos[cur]:]
                        else:
                            w.writerow([cur, "OOM", "%.1f" % (time.time() - t0),
                                        "SIGKILL x%d (memcg OOM): " % kills[cur] + " | ".join(l.strip() for l in tail[-3:])[:250]]); fo.flush()
                            todo = todo[pos[cur] + 1:]
                    elif cur:  # died inside a case
                        w.writerow([cur, "Crash", "%.1f" % (time.time() - t0),
                                    ("exit %d: " % p.returncode) + " | ".join(l.strip() for l in tail[-3:])[:300]]); fo.flush()
                        todo = todo[pos[cur] + 1:]
                    else:
                        todo = todo[last + 1:] if last >= 0 else []  # clean exit; resume after last reported
                    break
                tail = (tail + [line])[-6:]
                m = RE_CASE.match(line.rstrip("\n"))
                if m:
                    cur, t0 = m.group(1), time.time(); continue
                m = RE_RES.match(line.rstrip("\n"))
                if m and cur:
                    w.writerow([cur, m.group(1), "%.2f" % (time.time() - t0), m.group(2)[:300]]); fo.flush()
                    last = pos.get(cur, -1)
                    cur = None
            # any case never started by a clean-exiting process is left in todo only if it crashed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--deqp", required=True); ap.add_argument("--caselist", required=True)
    ap.add_argument("--out", required=True); ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--timeout", type=int, default=120)
    a, extra = ap.parse_known_args()
    try:  # keep the runner alive under memcg OOM so kill counts and resume state stay coherent
        with open("/proc/self/oom_score_adj", "w") as f:
            f.write("-900")
    except OSError:
        pass
    extra = [x for x in extra if x != "--"]
    os.makedirs(a.out, exist_ok=True)
    cases = [l.strip() for l in open(a.caselist) if l.strip() and not l.startswith("#")]
    shards = [cases[i::a.jobs] for i in range(a.jobs)]
    th = [threading.Thread(target=run_shard, args=(i, s, a, extra)) for i, s in enumerate(shards)]
    t0 = time.time(); [t.start() for t in th]; [t.join() for t in th]
    res = {}
    for i in range(a.jobs):
        with open(os.path.join(a.out, "shard-%d.csv" % i)) as f:
            for r in csv.reader(f):
                if r: res[r[0]] = r
    with open(os.path.join(a.out, "results.csv"), "w", newline="") as f:
        w = csv.writer(f); w.writerow(["test", "status", "duration_s", "detail"])
        for c in cases:
            w.writerow(res.get(c, [c, "Missing", "", "never reported"]))
    counts = {}
    for c in cases:
        s = res.get(c, [c, "Missing"])[1]; counts[s] = counts.get(s, 0) + 1
    with open(os.path.join(a.out, "summary.txt"), "w") as f:
        f.write("caselist %s, %d cases, %.0f s\n" % (a.caselist, len(cases), time.time() - t0))
        for k in sorted(counts): f.write("%-22s %d\n" % (k, counts[k]))
    print(open(os.path.join(a.out, "summary.txt")).read())


if __name__ == "__main__":
    main()
