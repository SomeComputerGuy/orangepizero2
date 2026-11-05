#!/usr/bin/env python3
"""Interpreter for Bifrost *disassembly* dumps (the clause_N / {*FMA +ADD} form printed with
BIFROST_MESA_DEBUG=shaders), i.e. the packed binary as the hardware sees it: tuples, FMA/ADD slots,
passthrough (t = this tuple's FMA, t0/t1 = previous tuple's FMA/ADD), staging registers, clause-end
delivery of LOAD results. Integer ops only (enough for the 64-bit division kernels).

usage: biemu3.py <disasm.txt> [-n N] [--seed S] [--ubase U] [--pairs f] [--cts 1] [--rem 1] [--signed 0/1]
"""
import re, sys, random, argparse
M = 0xffffffff

def parse(path):
    clauses = []; cur = None
    for line in open(path):
        line = line.rstrip("\n")
        m = re.match(r"^(clause_\d+):", line)
        if m:
            cur = {"name": m.group(1), "hdr": "", "tuples": []}; clauses.append(cur); continue
        if cur is None: continue
        if re.match(r"^(ds|id)\(", line): cur["hdr"] = line; continue
        s = line.strip()
        if not s or s in ("{", "}"): continue
        if s[0] not in "*+": continue
        slot = s[0]; s = re.sub(r"/\*.*?\*/", "", s[1:]).strip()
        op, _, rest = s.partition(" ")
        toks = [t.strip() for t in rest.split(",")] if rest else []
        ins = {"slot": slot, "op": op, "dest": toks[0] if toks else None, "src": toks[1:], "txt": s}
        if slot == "*": cur["tuples"].append([ins, None])
        else:
            if cur["tuples"] and cur["tuples"][-1][1] is None: cur["tuples"][-1][1] = ins
            else: cur["tuples"].append([None, ins])
    return clauses

def s32(x):
    x &= M
    return x - (1 << 32) if x & 0x80000000 else x

class HW:
    def __init__(self, mem):
        self.mem = mem; self.r = [0] * 64; self.tls = {}; self.unif = {}
        self.t = 0; self.t0 = 0; self.t1 = 0
        self.pending_loads = []   # (base reg, words) delivered at clause end
        self.warn = {}
    def W(self, k):
        self.warn[k] = self.warn.get(k, 0) + 1
    def rd(self, tok):
        mods = tok.split("."); base, mods = mods[0], mods[1:]
        if base == "t": v = self.t
        elif base == "t0": v = self.t0
        elif base == "t1": v = self.t1
        elif base == "#0": v = 0
        elif base.startswith("0x"): v = int(base, 16) & M
        elif base.startswith("u"):
            mu = re.match(r"u(\d+)$", base); w = 0
            for md in mods:
                if md in ("w0", "w1"): w = int(md[1])
            v = self.unif.get((int(mu.group(1)), w))
            if v is None: v = 0; self.W("uniform %s read as 0" % tok)
            mods = [md for md in mods if md not in ("w0", "w1")]
        elif base.startswith("r"): v = self.r[int(base[1:])]
        else: raise ValueError(tok)
        for md in mods:
            if md == "not": v = (~v) & M
            elif md in ("h0", "h00", "x"): v &= 0xffff if md != "x" else M
            elif md in ("h1", "h11"): v = (v >> 16) & 0xffff
            elif re.match(r"b[0-3]$", md): v = (v >> (8 * int(md[1]))) & 0xff
            elif md == "neg": v = (-v) & M
            else: raise ValueError("mod %s in %s" % (md, tok))
        return v & M
    def ld(self, addr, nbytes):
        return [int.from_bytes(bytes(self.mem.get(addr + i, 0) for i in range(k, k + 4)), "little") for k in range(0, nbytes, 4)]
    def st(self, addr, words):
        b = b"".join((w & M).to_bytes(4, "little") for w in words)
        for i, x in enumerate(b): self.mem[addr + i] = x

def run(clauses, hw, max_steps=10_000_000):
    index = {c["name"]: i for i, c in enumerate(clauses)}
    ci = 0; steps = 0
    while ci is not None and ci < len(clauses):
        c = clauses[ci]; nxt = None
        for fma, add in c["tuples"]:
            steps += 1
            if steps > max_steps: raise RuntimeError("runaway")
            new_t0 = hw.t0; new_t1 = hw.t1
            # FMA first
            if fma is not None:
                v = exec_ins(hw, fma, c, ci, index)
                if v is not None: hw.t = v; new_t0 = v
            if add is not None:
                r = exec_ins(hw, add, c, ci, index)
                if isinstance(r, tuple) and r[0] == "branch": nxt = r[1]; r = None
                if r is not None: new_t1 = r
            hw.t0, hw.t1 = new_t0, new_t1
        # deliver loads at clause end
        for base, words in hw.pending_loads:
            for k, w in enumerate(words): hw.r[base + k] = w & M
        hw.pending_loads = []
        if "eos" in c["hdr"].split(): return steps
        ci = nxt if nxt is not None else ci + 1
    return steps

def wdest(hw, ins, val):
    d = ins["dest"]
    val &= M
    if d is None: return val
    m = re.match(r"r(\d+)", d)
    if m: hw.r[int(m.group(1))] = val
    return val

def exec_ins(hw, ins, clause, ci, index):
    op = ins["op"]; base = op.split(".")[0]; mods = op.split(".")[1:]; S = ins["src"]
    if base == "NOP": return None
    if base in ("IADD", "ISUB"):
        a, b = hw.rd(S[0]), hw.rd(S[1]); return wdest(hw, ins, a + b if base == "IADD" else a - b)
    if base == "IMUL": return wdest(hw, ins, hw.rd(S[0]) * hw.rd(S[1]))
    if base in ("LSHIFT_OR", "RSHIFT_OR"):
        a, b, s = hw.rd(S[0]), hw.rd(S[1]), hw.rd(S[2]) & 31
        r = ((a << s) if base == "LSHIFT_OR" else (a >> s)) | b
        if "not" in mods: r = ~r
        return wdest(hw, ins, r)
    if base == "ARSHIFT":
        a, b, s = hw.rd(S[0]), hw.rd(S[1]), hw.rd(S[2]) & 31
        return wdest(hw, ins, (s32(a) >> s) | b)
    if base == "MUX":
        a, b, c = hw.rd(S[0]), hw.rd(S[1]), hw.rd(S[2])
        assert len(mods) == 1 or mods[1] == "int_zero", op
        return wdest(hw, ins, b if c != 0 else a)
    if base == "CSEL":
        ty = mods[0]; cf = mods[1]
        a, b, c, d = (hw.rd(x) for x in S[:4])
        if ty == "s32": a, b = s32(a), s32(b)
        cond = {"eq": a == b, "ne": a != b, "lt": a < b, "le": a <= b, "gt": a > b, "ge": a >= b}[cf]
        return wdest(hw, ins, c if cond else d)
    if base == "ICMP":
        ty = mods[0]; rt = "i1"; cf = mods[-1]
        if len(mods) == 3: rt = mods[1]
        a, b = hw.rd(S[0]), hw.rd(S[1])
        if ty == "s32": a, b = s32(a), s32(b)
        c = {"eq": a == b, "ne": a != b, "lt": a < b, "le": a <= b, "gt": a > b, "ge": a >= b}[cf]
        return wdest(hw, ins, (1 if rt == "i1" else M) if c else 0)
    if base == "CLZ": a = hw.rd(S[0]); return wdest(hw, ins, 32 - a.bit_length())
    if base == "MKVEC":
        a, b = hw.rd(S[0]) & 0xffff, hw.rd(S[1]) & 0xffff; return wdest(hw, ins, a | (b << 16))
    if base in ("U8_TO_U32", "U16_TO_U32", "MOV"): return wdest(hw, ins, hw.rd(S[0]))
    if base == "LOAD":
        nbytes = int(mods[0][1:]) // 8
        lo, hi = hw.rd(S[0]), hw.rd(S[1])
        stg = [t for t in S if t.startswith("@")][0]; breg = int(stg[2:])
        if "tl" in mods: words = [hw.tls.get(lo + k, 0) for k in range(0, nbytes, 4)]
        else: words = hw.ld(((hi << 32) | lo), nbytes)
        hw.pending_loads.append((breg, words)); return None
    if base == "STORE":
        nbytes = int(mods[0][1:]) // 8
        stg = [t for t in S if t.startswith("@")][0]; breg = int(stg[2:])
        words = [hw.r[breg + k] for k in range(nbytes // 4)]
        addr_toks = [t for t in S if not t.startswith("@")]
        lo, hi = hw.rd(addr_toks[0]), hw.rd(addr_toks[1])
        if "tl" in mods:
            for k, w in enumerate(words): hw.tls[lo + 4 * k] = w
        else: hw.st((hi << 32) | lo, words)
        return None
    if base == "BRANCHZ":
        a = hw.rd(S[0]); tgt = S[-1]
        taken = (a == 0) if mods[-1] == "eq" else (a != 0)
        return ("branch", index[tgt]) if taken else None
    if base == "JUMP":
        return ("branch", index[S[-1]])
    raise NotImplementedError(op)

def c_div(a, b, signed, rem):
    if b == 0: return None
    if signed:
        if a == -(1 << 63) and b == -1: return None
        q = abs(a) // abs(b); q = -q if (a < 0) != (b < 0) else q
        return (a - q * b) if rem else q
    return (a % b) if rem else (a // b)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump"); ap.add_argument("-n", type=int, default=32); ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--vec", type=int, default=16); ap.add_argument("--signed", type=int, default=1); ap.add_argument("--rem", type=int, default=0)
    ap.add_argument("--ubase", type=int, default=0); ap.add_argument("--pairs"); ap.add_argument("--cts", type=int, default=0)
    a = ap.parse_args()
    clauses = parse(a.dump)
    rnd = random.Random(a.seed); V = a.vec
    A_BASE, B_BASE, D_BASE = 0x100000, 0x200000, 0x300000
    def gen():
        k = rnd.randrange(4)
        if k == 0: return rnd.getrandbits(64)
        if k == 1: return rnd.getrandbits(rnd.randrange(1, 64))
        if k == 2: return (-rnd.getrandbits(rnd.randrange(1, 63))) & ((1 << 64) - 1)
        return rnd.getrandbits(32) | (rnd.choice([0, 0, 1, rnd.getrandbits(16)]) << 32)
    def gen_cts():
        x = rnd.getrandbits(32); y = rnd.getrandbits(32)
        xs = x - (1 << 32) if x >> 31 else x; ys = y - (1 << 32) if y >> 31 else y
        return (((xs << 33) | (ys & ((1 << 64) - 1))) ^ (ys << 16)) & ((1 << 64) - 1)
    if a.pairs:
        P = [tuple(int(t, 16) for t in l.split()[:2]) for l in open(a.pairs) if l.strip()]
        A = [P[i % len(P)][0] for i in range(a.n * V)]; B = [P[i % len(P)][1] for i in range(a.n * V)]
    else:
        g = gen_cts if a.cts else gen
        A = [g() for _ in range(a.n * V)]; B = [g() for _ in range(a.n * V)]
    mem = {}
    for i, (x, y) in enumerate(zip(A, B)):
        for j, bt in enumerate(x.to_bytes(8, "little")): mem[A_BASE + 8 * i + j] = bt
        for j, bt in enumerate(y.to_bytes(8, "little")): mem[B_BASE + 8 * i + j] = bt
    bad = checked = 0; warn = {}
    for tid in range(a.n):
        hw = HW(mem); ub = a.ubase
        hw.unif = {(ub, 0): A_BASE & M, (ub, 1): A_BASE >> 32, (ub + 1, 0): B_BASE & M, (ub + 1, 1): B_BASE >> 32,
                   (ub + 2, 0): D_BASE & M, (ub + 2, 1): D_BASE >> 32}
        hw.r[60] = tid
        run(clauses, hw)
        for k, v in hw.warn.items(): warn[k] = warn.get(k, 0) + v
        for c in range(V):
            i = tid * V + c; x, y = A[i], B[i]
            got = int.from_bytes(bytes(mem.get(D_BASE + 8 * i + j, 0) for j in range(8)), "little")
            if a.signed:
                xs = x - (1 << 64) if x >> 63 else x; ys = y - (1 << 64) if y >> 63 else y
                exp = c_div(xs, ys, True, a.rem)
            else: exp = c_div(x, y, False, a.rem)
            if exp is None: continue
            exp &= (1 << 64) - 1; checked += 1
            if got != exp:
                bad += 1
                if bad <= 10: print("tid %d comp %d: %#x %s %#x = %#x, got %#x" % (tid, c, x, "%" if a.rem else "/", y, exp, got))
    for k, v in warn.items(): print("warning:", k, "x%d" % v)
    print("%s: %d clauses, %d checked, %d bad" % (a.dump, len(clauses), checked, bad))

if __name__ == "__main__":
    main()
