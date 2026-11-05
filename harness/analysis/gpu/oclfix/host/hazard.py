import re, sys
# scan a Bifrost disassembly: for each clause, flag tuple sources that read a register written by the
# previous K tuples (K=1,2) of the same clause without passthrough, and ADD reading FMA dest of same tuple
lines = open(sys.argv[1]).read().split("\n")
clause = None; tuples = []; hits = {1: 0, 2: 0, 3: 0}; same = 0; ex = []
def flush():
    global tuples, same
    for i, (f, a) in enumerate(tuples):
        for k in (1, 2, 3):
            if i - k < 0: continue
            wr = set()
            for ins in tuples[i - k]:
                if ins: wr |= ins["w"]
            for ins in (f, a):
                if not ins: continue
                hit = ins["r"] & wr
                if hit:
                    hits[k] += 1
                    if k == 1: ex.append((clause, i, k, sorted(hit), ins["txt"]))
        if f and a and (a["r"] & f["w"]): same += 1
    tuples = []
def parse_ins(s):
    s = s.strip()
    slot = s[0]; s = s[1:]
    op, _, rest = s.partition(" ")
    toks = [t.strip() for t in rest.split(",")] if rest else []
    w = set(); r = set()
    if toks:
        d = toks[0]
        m = re.match(r"r(\d+)", d)
        if m: w.add(int(m.group(1)))
        for t in toks[1:]:
            if t.startswith("@"):
                m = re.match(r"@r(\d+)", t)
                if m and op.startswith("STORE"):
                    n = {"i32": 1, "i64": 2, "i96": 3, "i128": 4}[op.split(".")[1]]
                    r |= set(range(int(m.group(1)), int(m.group(1)) + n))
                continue
            m = re.match(r"r(\d+)", t)
            if m: r.add(int(m.group(1)))
    return {"op": op, "w": w, "r": r, "txt": s}
cur = [None, None]
for l in lines:
    if l.startswith("clause_"):
        flush(); clause = l.strip(":")
    elif l.startswith("    *"):
        cur = [parse_ins(l), None]
    elif l.startswith("    +"):
        cur[1] = parse_ins(l); tuples.append(tuple(cur)); cur = [None, None]
flush()
print("reads of a register written by tuple i-1 (no passthrough):", hits[1], " i-2:", hits[2], " i-3:", hits[3], " ADD reads FMA dest reg same tuple:", same)
for e in ex: print(e)
