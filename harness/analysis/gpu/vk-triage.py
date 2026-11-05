#!/usr/bin/env python3
"""Triage a deqp-run.py results.csv for dEQP-VK against Mesa CI's panfrost G52 (Bifrost v7) expectations.

Usage: vk-triage.py RESULTS_CSV MESA_CI_DIR [OUT_DIR]
MESA_CI_DIR = mesa src/panfrost/ci. Reads panfrost-g52-{fails,flakes,skips}.txt and panvk-{skips,flakes}.txt.
Prints status counts, then every non-Pass/NotSupported case with its Mesa expectation (fails list status, or
skip/flake regex hit, or "new"), grouped by top-level dEQP-VK group. Writes nonpass.csv + summary.txt to OUT_DIR.
"""
import csv, os, re, sys, collections

def load_list(p, with_status=False):
    out = []
    if not os.path.exists(p): return out
    for l in open(p):
        l = l.strip()
        if not l or l.startswith("#"): continue
        if with_status and "," in l:
            n, s = l.rsplit(",", 1); out.append((n, s))
        else:
            out.append((l, None))
    return out

res, ci = sys.argv[1], sys.argv[2]
out = sys.argv[3] if len(sys.argv) > 3 else None
fails = dict(load_list(os.path.join(ci, "panfrost-g52-fails.txt"), True))
rx = []
for f in ("panfrost-g52-skips.txt", "panfrost-g52-flakes.txt", "panvk-skips.txt", "panvk-flakes.txt", "panfrost-flakes.txt"):
    for n, _ in load_list(os.path.join(ci, f)):
        if n.startswith("dEQP-VK") or n.startswith(".*") or n.startswith("dEQP-VK"):
            try: rx.append((f, re.compile(n)))
            except re.error: pass

rows = [r for r in csv.DictReader(open(res))]
cnt = collections.Counter(r["status"] for r in rows)
lines = ["%d cases" % len(rows)] + ["%-16s %d" % kv for kv in sorted(cnt.items())]
np = []
for r in rows:
    if r["status"] in ("Pass", "NotSupported"): continue
    t = r["test"]
    exp = ("g52-fails:" + fails[t]) if t in fails else next((f for f, c in rx if c.fullmatch(t)), "new")
    np.append((t, r["status"], exp, r["detail"]))
grp = collections.Counter((t.split(".")[1], s, "known" if e != "new" else "new") for t, s, e, _ in np)
lines.append("\nnon-pass by group (group, status, vs Mesa G52 lists): count")
lines += ["  %s %s %s: %d" % (g, s, k, n) for (g, s, k), n in sorted(grp.items())]
print("\n".join(lines))
if out:
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, "summary.txt"), "w").write("\n".join(lines) + "\n")
    with open(os.path.join(out, "nonpass.csv"), "w", newline="") as f:
        w = csv.writer(f); w.writerow(["test", "status", "mesa_g52_expectation", "detail"]); w.writerows(np)
