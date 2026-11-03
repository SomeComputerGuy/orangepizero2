#!/usr/bin/env python3
"""Run an OpenCL-CTS profile CSV (Mesa CI format: "Name,relative/binary args") on the board.

Usage: clcts-run.py --cts DIR(test_conformance) --profile FILE.csv --out DIR [--timeout S] [--only REGEX]
Each line runs as its own process from its binary's directory, with a timeout. The full log goes to
OUT/logs/<name>.log. Sub-test results are parsed from the harness lines "<test> passed|failed|skipped"
and written to OUT/results.csv as "suite,subtest,status,detail". The per-binary verdict (exit code,
"PASSED/FAILED n of m") goes to OUT/binaries.csv. Lines tagged CL_DEVICE_TYPE_CPU are skipped,
as in Mesa CI. Binaries already in binaries.csv are not rerun (resume).
"""
import argparse, csv, os, re, shlex, subprocess, time

RE_SUB = re.compile(r"^(\S+)\s+(passed|failed|skipped)\.?\s*$", re.I)
RE_SUM = re.compile(r"^(PASSED|FAILED)\s+(\d+)\s+of\s+(\d+)\s+tests?", re.I)


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cts", required=True); ap.add_argument("--profile", required=True)
    ap.add_argument("--out", required=True); ap.add_argument("--timeout", type=int, default=5000)
    ap.add_argument("--only", default=None)
    a = ap.parse_args()
    os.makedirs(os.path.join(a.out, "logs"), exist_ok=True)
    bpath = os.path.join(a.out, "binaries.csv"); rpath = os.path.join(a.out, "results.csv")
    done = set()
    if os.path.exists(bpath):
        done = {r[0] for r in csv.reader(open(bpath)) if r and r[0] != "suite"}
    newb = not os.path.exists(bpath)
    with open(bpath, "a", newline="") as fb, open(rpath, "a", newline="") as fr:
        wb, wr = csv.writer(fb), csv.writer(fr)
        if newb:
            wb.writerow(["suite", "verdict", "exit", "summary", "seconds", "command"])
            wr.writerow(["suite", "subtest", "status", "detail"])
        for line in open(a.profile):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = [p.strip() for p in line.split(",")]
            if parts[0].startswith("CL_DEVICE_TYPE_"):
                continue  # device-type-specific lines (CPU linear filtering), skipped like Mesa CI
            name, cmd = parts[0], parts[1]
            if name in done or (a.only and not re.search(a.only, name)):
                continue
            argv = shlex.split(cmd); exe = os.path.join(a.cts, argv[0])
            log = os.path.join(a.out, "logs", re.sub(r"[^A-Za-z0-9_.-]+", "_", name) + ".log")
            t0 = time.time()
            if not os.path.exists(exe):
                wb.writerow([name, "Missing", "", "binary not built", 0, cmd]); fb.flush(); continue
            for attempt in range(3):
              wait_for_memory()
              try:
                with open(log, "w") as lf:
                    p = subprocess.run([exe] + argv[1:], cwd=os.path.dirname(exe), stdout=lf,
                                       stderr=subprocess.STDOUT, timeout=a.timeout)
                rc = p.returncode
              except subprocess.TimeoutExpired:
                rc = "timeout"
              if rc != -9:
                break  # -9 = killed (OOM on the shared board): retry
            summ, subs = "", []
            for l in open(log, errors="replace"):
                m = RE_SUB.match(l.strip())
                if m: subs.append((m.group(1), m.group(2).capitalize()))
                m = RE_SUM.match(l.strip())
                if m: summ = l.strip()
            for s, st in subs:
                wr.writerow([name, s, st, ""])
            nfail = sum(1 for _, st in subs if st == "Failed")
            if rc == "timeout": verdict = "Timeout"
            elif rc not in (0,) and rc < 0: verdict = "Crash"
            elif rc == 0 and nfail == 0: verdict = "Pass" if any(st == "Passed" for _, st in subs) or not subs else "Skip"
            else: verdict = "Fail"
            wb.writerow([name, verdict, rc, summ, "%.0f" % (time.time() - t0), cmd]); fb.flush(); fr.flush()
            print("%-40s %-8s rc=%s %s" % (name, verdict, rc, summ), flush=True)


if __name__ == "__main__":
    main()
