#!/usr/bin/env python3
"""vk-cmp.py BASELINE.csv[.xz] NEW.csv: compare two deqp-run.py results.csv files (test,status,...).
Prints the status counts of NEW, then REGRESSIONS (Pass in baseline, not Pass now), FIXED (not Pass -> Pass) and
STILL-NONPASS (not Pass in both) with the case names. Mechanical: the runner copies the REGRESSIONS line and list."""
import csv, lzma, sys
def load(p):
    f = lzma.open(p, "rt") if p.endswith(".xz") else open(p)
    d = {}
    for row in csv.reader(f):
        if len(row) >= 2 and row[0].startswith("dEQP"): d[row[0]] = row[1]
    return d
b, n = load(sys.argv[1]), load(sys.argv[2])
cnt = {}
for s in n.values(): cnt[s] = cnt.get(s, 0) + 1
print("NEW cases %d: %s" % (len(n), " ".join("%s=%d" % kv for kv in sorted(cnt.items()))))
reg = sorted(t for t, s in n.items() if s != "Pass" and b.get(t) == "Pass")
fix = sorted(t for t, s in n.items() if s == "Pass" and t in b and b[t] != "Pass")
still = sorted(t for t, s in n.items() if s != "Pass" and s != "NotSupported" and t in b and b[t] != "Pass")
missing = sorted(t for t in b if t not in n)
print("REGRESSIONS: %d" % len(reg)); [print("  REG %s %s (was Pass)" % (t, n[t])) for t in reg]
print("FIXED: %d" % len(fix)); [print("  FIX %s (was %s)" % (t, b[t])) for t in fix]
print("STILL-NONPASS: %d" % len(still)); [print("  STILL %s %s (was %s)" % (t, n[t], b[t])) for t in still]
print("MISSING (in baseline, not run): %d" % len(missing))
