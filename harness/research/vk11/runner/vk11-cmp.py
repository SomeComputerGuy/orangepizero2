#!/usr/bin/env python3
"""vk11-cmp.py: results of the full dEQP-VK vk-main run at Vulkan 1.1 (job 68), host side, no board.

  vk11-cmp.py part RESULTS.csv[.xz] OUTDIR   counts of one part + OUTDIR/nonpass.csv (every row not Pass/NotSupported)
  vk11-cmp.py final FILESDIR OUT.txt         all parts (FILESDIR/part-NN/results.csv.xz): totals, regressions against
                                             every baseline below, non-pass rows grouped; prints the CHECK lines
Regression = Pass in a baseline and now not Pass/QualityWarning/CompatibilityWarning (NotSupported counts as a
regression too: a case that used to run must still run). Baselines (deqp-run.py results.csv of the same 1.4.6.2 tree):"""
import csv, glob, lzma, os, sys
H = "/home/aruni/orangepizero2"
BASELINES = [  # name, path, what it is
    ("main1in100-sys-1.0", H + "/harness/analysis/gpu/cts-vk-1.4.6.2/vk-main-1in100/results.csv.xz", "system Mesa 26.2.4, API 1.0"),
    ("main1in100-sys-ovr1.1", H + "/harness/analysis/gpu/cts-vk-1.4.6.2/vk-main-1in100-override1.1/results.csv.xz", "system Mesa 26.2.4, MESA_VK_VERSION_OVERRIDE=1.1"),
    ("subset-sys-1.0", H + "/harness/analysis/gpu/cts-vk-1.4.6.2/vk-subset/results.csv.xz", "system Mesa 26.2.4, API 1.0"),
    ("subset-sys-ovr1.1", H + "/harness/analysis/gpu/cts-vk-1.4.6.2/vk-subset-override1.1/results.csv.xz", "system Mesa 26.2.4, override 1.1"),
    ("subset-fork-job52", H + "/harness/research/gpu-invalid-enc/logs/runner/files/subset4/results.csv", "fork 0e274280595 on c38, override 1.1 (job 52)"),
]
PASSLIKE = {"Pass", "QualityWarning", "CompatibilityWarning"}
KEEPNODETAIL = {"Pass", "NotSupported"}


def load(p):
    f = lzma.open(p, "rt") if p.endswith(".xz") else open(p)
    d = {}
    for row in csv.reader(f):
        if len(row) >= 2 and row[0].startswith("dEQP"):  # detail kept only for non-pass rows (3.25 M rows)
            d[row[0]] = (row[1], row[3] if len(row) > 3 and row[1] not in KEEPNODETAIL else "")
    return d


def counts(d):
    c = {}
    for s, _ in d.values(): c[s] = c.get(s, 0) + 1
    return " ".join("%s=%d" % kv for kv in sorted(c.items()))


def group(t, n=3):
    return ".".join(t.split(".")[:n])


def part(res, outdir):
    d = load(res)
    with open(os.path.join(outdir, "nonpass.csv"), "w", newline="") as f:
        w = csv.writer(f)
        for t, (s, m) in d.items():
            if s not in PASSLIKE and s != "NotSupported": w.writerow([t, s, m])
    print("COUNTS %s cases=%d %s" % (os.path.basename(outdir), len(d), counts(d)))


def final(filesdir, out):
    new, nparts = {}, 0
    for p in sorted(glob.glob(os.path.join(filesdir, "part-*/results.csv.xz"))):
        new.update(load(p)); nparts += 1
    o = open(out, "w")
    def pr(s=""): o.write(s + "\n")
    pr("PARTS with results: %d" % nparts)
    pr("TOTAL cases %d: %s" % (len(new), counts(new)))
    allreg = {}
    for name, path, what in BASELINES:
        if not os.path.exists(path):
            pr("BASELINE %s: MISSING %s" % (name, path)); continue
        b = load(path)
        common = [t for t in b if t in new]
        reg = sorted(t for t in common if b[t][0] == "Pass" and new[t][0] not in PASSLIKE)
        fix = sorted(t for t in common if b[t][0] != "Pass" and new[t][0] == "Pass")
        pr("BASELINE %s (%s): %d cases, %d in this run; REGRESSIONS %d, FIXED %d" % (name, what, len(b), len(common), len(reg), len(fix)))
        for t in reg:
            allreg.setdefault(t, []).append(name)
            pr("  REG[%s] %s %s (was Pass) %s" % (name, t, new[t][0], new[t][1][:120]))
        for t in fix: pr("  FIX[%s] %s (was %s)" % (name, t, b[t][0]))
    pr("REGRESSIONS (union over baselines): %d" % len(allreg))
    for t in sorted(allreg): pr("  REG %s %s [%s]" % (t, new[t][0], ",".join(allreg[t])))
    bad = {t: v for t, v in new.items() if v[0] not in PASSLIKE and v[0] != "NotSupported"}
    g = {}
    for t, (s, _) in bad.items(): g[(group(t), s)] = g.get((group(t), s), 0) + 1
    pr("NON-PASS (not Pass/NotSupported): %d, by group:" % len(bad))
    for (gr, s), n in sorted(g.items(), key=lambda kv: -kv[1]): pr("  %6d %s %s" % (n, s, gr))
    pr("NON-PASS list:")
    for t in sorted(bad): pr("  %s %s %s" % (t, bad[t][0], bad[t][1][:160]))
    o.close()
    c = {}
    for s, _ in new.values(): c[s] = c.get(s, 0) + 1
    print("COUNTS cases=%d %s" % (len(new), " ".join("%s=%d" % kv for kv in sorted(c.items()))))
    print("REGRESSIONS %d" % len(allreg))


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "part": part(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 4 and sys.argv[1] == "final": final(sys.argv[2], sys.argv[3])
    else: print(__doc__); sys.exit(2)
