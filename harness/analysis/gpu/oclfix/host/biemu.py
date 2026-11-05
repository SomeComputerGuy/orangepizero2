#!/usr/bin/env python3
"""Tiny interpreter for Bifrost MIR text dumps (BIFROST_MESA_DEBUG=shaders), enough for the
integer-only 64-bit division kernels. Runs the pre-RA (SSA) and post-RA (register) dumps on the
same inputs and compares both with the expected C semantics.

usage: biemu.py <dump.txt> [-n N] [--seed S]   (dump = one block0..blockN program, pre- or post-RA)
"""
import re, sys, random, argparse

M = 0xffffffff

def parse(path):
    blocks = {}; order = []; cur = None
    for line in open(path):
        line = line.rstrip("\n")
        m = re.match(r"^(block\d+) \{", line)
        if m:
            cur = m.group(1); blocks[cur] = {"ins": [], "succ": [], "pred": []}; order.append(cur); continue
        m = re.match(r"^\}(.*)", line)
        if m:
            rest = m.group(1)
            ms = re.search(r"-> ([^\n]*?)(?:  from (.*))?$", rest)
            if ms:
                blocks[cur]["succ"] = ms.group(1).split()
                blocks[cur]["pred"] = (ms.group(2) or "").split()
            else:
                mf = re.search(r"from (.*)$", rest)
                if mf: blocks[cur]["pred"] = mf.group(1).split()
            cur = None; continue
        if cur is None: continue
        s = line.strip()
        if not s: continue
        s = re.sub(r"^\d+(x\d+)?\s+", "", s)
        if " = " in s: dests, rhs = s.split(" = ", 1)
        else: dests, rhs = "", s
        target = None
        if " -> " in rhs: rhs, target = rhs.split(" -> "); target = target.strip()
        parts = rhs.split(None, 1)
        op = parts[0]; opstr = parts[1] if len(parts) > 1 else ""
        operands = [o.strip() for o in opstr.split(",")] if opstr else []
        attrs = {}
        ops2 = []
        for o in operands:
            ma = re.match(r"(\w+):(-?\w+)$", o)
            if ma and not o.startswith("r"): attrs[ma.group(1)] = int(ma.group(2), 0)
            else: ops2.append(o)
        dl = [d.strip() for d in dests.split(",")] if dests else []
        blocks[cur]["ins"].append((op, dl, ops2, attrs, target))
    return blocks, order

class Machine:
    def __init__(self, mem):
        self.mem = mem  # dict byte addr -> byte
        self.vals = {}  # ssa name or reg -> int or list
        self.tls = {}
        self.unif = {}

    # ---- operands
    def read_word(self, tok):
        """tok: single word operand with optional modifiers; returns 32-bit int"""
        mods = tok.replace("^", "").split(".")
        base, mods = mods[0], mods[1:]
        if base == "_": v = 0
        elif base.startswith("#"): v = int(base[1:], 16) & M
        elif base.startswith("u"):
            mu = re.match(r"u(\d+)(?:\[(\d+)\])?$", base)
            v = self.unif.get((int(mu.group(1)), int(mu.group(2) or 0)))
            if v is None:
                v = 0; self.unif[(int(mu.group(1)), int(mu.group(2) or 0))] = 0; print("warning: uniform %s read as 0" % base, file=sys.stderr)
        elif base.startswith("%") or base.startswith("r"):
            v = self.vals.get(base)
            if v is None: raise KeyError("read of undefined %s" % base)
            if isinstance(v, list): v = v[0]
        else: raise ValueError(tok)
        for md in mods:
            if md == "neg": v = (~v) & M
            elif md == "h00" or md == "h0": v &= 0xffff
            elif md == "h11" or md == "h1": v = (v >> 16) & 0xffff
            elif md == "h01": pass
            elif re.match(r"b[0-3]$", md): v = (v >> (8 * int(md[1]))) & 0xff
            elif md == "abs": pass
            else: raise ValueError("mod %s in %s" % (md, tok))
        return v

    def read_vec(self, tok):
        """vector operand: rA:rB:... or %N (list) -> list of words"""
        if ":" in tok: return [self.read_word(t) for t in tok.split(":")]
        v = self.vals.get(tok.replace("^", "").split(".")[0])
        if isinstance(v, list): return list(v)
        return [self.read_word(tok)]

    def write(self, dest, words):
        if ":" in dest:
            regs = dest.split(":")
            assert len(regs) == len(words), (dest, words)
            for r, w in zip(regs, words): self.vals[r] = w & M
        else:
            d = dest.replace("^", "").split(".")[0]
            self.vals[d] = [w & M for w in words] if len(words) > 1 else (words[0] & M)

    # ---- memory
    def ld(self, addr, nbytes):
        return [int.from_bytes(bytes(self.mem.get(addr + i, 0) for i in range(k, k + 4)), "little")
                for k in range(0, nbytes, 4)]
    def st(self, addr, words):
        b = b"".join((w & M).to_bytes(4, "little") for w in words)
        for i, x in enumerate(b): self.mem[addr + i] = x
    def tld(self, off, nbytes):
        return [self.tls.get(off + k, 0) for k in range(0, nbytes, 4)]
    def tst(self, off, words):
        for k, w in enumerate(words): self.tls[off + 4 * k] = w & M

def s32(x):
    x &= M
    return x - (1 << 32) if x & 0x80000000 else x

def run(blocks, order, mach, trace=None):
    cur = order[0]; prev = None; steps = 0
    while cur is not None:
        blk = blocks[cur]
        ins = blk["ins"]
        # phis first, in parallel
        phis = [i for i in ins if i[0] == "PHI"]
        if phis:
            pidx = blk["pred"].index(prev)
            newv = [(dl[0], mach.read_vec(ops[pidx])) for (_, dl, ops, _, _) in phis]
            for d, v in newv: mach.write(d, v)
        nxt = None
        for (op, dl, ops, attrs, target) in ins:
            steps += 1
            base = op.split(".")[0]
            mods = op.split(".")[1:]
            if op == "PHI": continue
            if base in ("IADD", "ISUB"):
                a, b = mach.read_word(ops[0]), mach.read_word(ops[1])
                r = (a + b) if base == "IADD" else (a - b)
                mach.write(dl[0], [r])
            elif base in ("LSHIFT_OR", "RSHIFT_OR"):
                a, b, s = mach.read_word(ops[0]), mach.read_word(ops[1]), mach.read_word(ops[2]) & 31
                r = ((a << s) if base == "LSHIFT_OR" else (a >> s)) | b
                if "not" in mods: r = ~r
                mach.write(dl[0], [r])
            elif base == "ARSHIFT":
                a, b, s = mach.read_word(ops[0]), mach.read_word(ops[1]), mach.read_word(ops[2]) & 31
                mach.write(dl[0], [(s32(a) >> s) | b])
            elif base == "MUX":
                a, b, c = mach.read_word(ops[0]), mach.read_word(ops[1]), mach.read_word(ops[2])
                assert mods[1] == "int_zero", op
                mach.write(dl[0], [b if c != 0 else a])
            elif base == "ICMP":
                ty, rt, cf = mods[0], mods[1], mods[2]
                a, b = mach.read_word(ops[0]), mach.read_word(ops[1])
                if ty == "s32": a, b = s32(a), s32(b)
                c = {"eq": a == b, "ne": a != b, "lt": a < b, "le": a <= b, "gt": a > b, "ge": a >= b}[cf]
                mach.write(dl[0], [(1 if rt == "i1" else M) if c else 0])
            elif base == "CLZ":
                a = mach.read_word(ops[0])
                mach.write(dl[0], [32 - a.bit_length()])
            elif base == "MKVEC":
                a, b = mach.read_word(ops[0]) & 0xffff, mach.read_word(ops[1]) & 0xffff
                mach.write(dl[0], [a | (b << 16)])
            elif base in ("U8_TO_U32", "U16_TO_U32"):
                mach.write(dl[0], [mach.read_word(ops[0])])
            elif base == "IMUL":
                mach.write(dl[0], [mach.read_word(ops[0]) * mach.read_word(ops[1])])
            elif base == "MOV":
                mach.write(dl[0], [mach.read_word(ops[0])])
            elif base == "SPLIT":
                v = mach.read_vec(ops[0])
                assert len(v) == len(dl), (v, dl)
                for d, w in zip(dl, v): mach.write(d, [w])
            elif base == "COLLECT":
                mach.write(dl[0], [mach.read_word(o) for o in ops])
            elif base == "LOAD":
                nbits = int(mods[0][1:]); nbytes = nbits // 8
                lo, hi = mach.read_word(ops[0]), mach.read_word(ops[1])
                off = attrs.get("byte_offset", 0)
                if "tl" in mods: words = mach.tld(lo + off, nbytes)
                else: words = mach.ld(((hi << 32) | lo) + off, nbytes)
                mach.write(dl[0], words)
            elif base == "STORE":
                nbits = int(mods[0][1:]); nbytes = nbits // 8
                words = mach.read_vec(ops[0])[: nbytes // 4]
                lo, hi = mach.read_word(ops[1]), mach.read_word(ops[2])
                off = attrs.get("byte_offset", 0)
                if "tl" in mods: mach.tst(lo + off, words)
                else: mach.st(((hi << 32) | lo) + off, words)
            elif base == "BRANCHZ":
                a = mach.read_word(ops[0]); b = mach.read_word(ops[1])
                taken = (a == b) if mods[-1] == "eq" else (a != b)
                if taken: nxt = target
            elif base == "JUMP":
                nxt = target
            else:
                raise NotImplementedError(op)
            if trace is not None: trace.append((cur, op, dl, [mach.vals.get(d.split(":")[0].split(".")[0]) for d in dl]))
        prev = cur
        if nxt is None:
            i = order.index(cur) + 1
            nxt = order[i] if i < len(order) else None
        cur = nxt
    return steps

def c_div(a, b, signed, rem):
    """C semantics of 64-bit / and % (truncation); returns None for UB cases"""
    if b == 0: return None
    if signed:
        if a == -(1 << 63) and b == -1: return None
        q = abs(a) // abs(b); q = -q if (a < 0) != (b < 0) else q
        r = a - q * b
        return r if rem else q
    return (a % b) if rem else (a // b)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump"); ap.add_argument("-n", type=int, default=64); ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--vec", type=int, default=16); ap.add_argument("--signed", type=int, default=1); ap.add_argument("--rem", type=int, default=0)
    ap.add_argument("--trace-tid", type=int, default=-1)
    ap.add_argument("--ubase", type=int, default=3, help="uniform index of srcA (srcB = +1, dst = +2)")
    ap.add_argument("--pairs", help="file with 'a b' hex pairs; fills all elements cyclically")
    ap.add_argument("--cts", type=int, default=0, help="use the CTS random distribution")
    a = ap.parse_args()
    blocks, order = parse(a.dump)
    rnd = random.Random(a.seed)
    V = a.vec; stride = 8 * V
    A_BASE, B_BASE, D_BASE = 0x100000, 0x200000, 0x300000
    mem = {}
    def gen():
        k = rnd.randrange(4)
        if k == 0: return rnd.getrandbits(64)
        if k == 1: return rnd.getrandbits(rnd.randrange(1, 64))
        if k == 2: return (-rnd.getrandbits(rnd.randrange(1, 63))) & ((1 << 64) - 1)
        return rnd.getrandbits(32) | (rnd.choice([0, 0, 1, rnd.getrandbits(16)]) << 32)
    def gen_cts():
        x = rnd.getrandbits(32); y = rnd.getrandbits(32)
        xs = x - (1 << 32) if x >> 31 else x; ys = y - (1 << 32) if y >> 31 else y
        return (((xs << 33) | (ys & ((1 << 64) - 1))) ^ ((ys << 16))) & ((1 << 64) - 1)
    if a.pairs:
        P = [tuple(int(t, 16) for t in l.split()[:2]) for l in open(a.pairs) if l.strip()]
        A = [P[i % len(P)][0] for i in range(a.n * V)]; B = [P[i % len(P)][1] for i in range(a.n * V)]
    elif a.cts:
        A = [gen_cts() for _ in range(a.n * V)]; B = [gen_cts() for _ in range(a.n * V)]
    else:
        A = [gen() for _ in range(a.n * V)]; B = [gen() for _ in range(a.n * V)]
    for i, (x, y) in enumerate(zip(A, B)):
        for j, bt in enumerate(x.to_bytes(8, "little")): mem[A_BASE + 8 * i + j] = bt
        for j, bt in enumerate(y.to_bytes(8, "little")): mem[B_BASE + 8 * i + j] = bt
    bad = 0; checked = 0
    for tid in range(a.n):
        m = Machine(mem)
        ub = a.ubase
        m.unif = {(ub, 0): A_BASE & M, (ub, 1): A_BASE >> 32, (ub + 1, 0): B_BASE & M, (ub + 1, 1): B_BASE >> 32,
                  (ub + 2, 0): D_BASE & M, (ub + 2, 1): D_BASE >> 32}
        m.vals["r60"] = tid; m.vals["r61"] = 0; m.vals["r62"] = 0
        for r in range(55, 60): m.vals["r%d" % r] = 0
        tr = [] if tid == a.trace_tid else None
        run(blocks, order, m, tr)
        if tr is not None:
            for t in tr: print(t)
        for c in range(V):
            i = tid * V + c
            x, y = A[i], B[i]
            got = int.from_bytes(bytes(mem.get(D_BASE + 8 * i + j, 0) for j in range(8)), "little")
            if a.signed:
                xs = x - (1 << 64) if x >> 63 else x; ys = y - (1 << 64) if y >> 63 else y
                exp = c_div(xs, ys, True, a.rem)
            else:
                exp = c_div(x, y, False, a.rem)
            if exp is None: continue
            exp &= (1 << 64) - 1
            checked += 1
            if got != exp:
                bad += 1
                if bad <= 12: print("tid %d comp %d: %#x %s %#x = %#x, got %#x" % (tid, c, x, "%" if a.rem else "/", y, exp, got))
    print("%s: %d checked, %d bad" % (a.dump, checked, bad))

if __name__ == "__main__":
    main()
