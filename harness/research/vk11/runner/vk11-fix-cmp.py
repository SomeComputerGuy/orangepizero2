#!/usr/bin/env python3
"""Job 70 (vk11-fix) comparison against job 68.

  vk11-fix-cmp.py NEWFILES J68FILES OUT.txt [ISOPART]

NEWFILES/part-NN/results.csv.xz = this run (5 caselists), J68FILES/part-NN/results.csv.xz = job 68 (64 parts of
vk-main, build 9d278fabfc2). Prints COUNTS, the CHECK lines 9a-9d (the cases the fixes target) and 10 (regressions
against job 68), and the remaining non-pass rows by class. OUT.txt gets every row that changed and every non-pass.
Job 71 (vk11-fix2) passes ISOPART = part-06 (synchronization2.internally_synchronized_queues.large2_large2 alone in
a fresh dEQP process): that part is kept out of the merged rows and gives checks 9e (the 6 memory requirement cases
of fix 26cb3c93a58) and 9f; check 10 then reports a large2_large2 ResourceError/OOM row of the batch run as INFO
(memory pressure of the 600 MB memcg after thousands of cases in one process) only when 9f passes.
"""
import csv, glob, lzma, os, re, sys

OK = {"Pass", "QualityWarning", "CompatibilityWarning"}


def load(d, skip=None, only=None):
    res = {}
    for p in sorted(glob.glob(os.path.join(d, "part-*/results.csv.xz"))):
        part = os.path.basename(os.path.dirname(p))
        if part == skip or (only and part != only):
            continue
        with lzma.open(p, "rt", newline="") as f:
            for r in csv.reader(f):
                if r and r[0] != "test":
                    res[r[0]] = r
    return res


TARGETS = [  # check, title, regex, expected count
    ("9a", "image_robustness cube r32i nonvolatile fmt_qual (job 68: Crash, INSTR_INVALID_ENC; fix cc734ca5372)",
     r"^dEQP-VK\.robustness\.image_robustness\.(bind|push)\.notemplate\.r32i\.dontunroll\.nonvolatile\.storage_image\."
     r"fmt_qual\.img\.samples_1\.cube(_array)?\.(comp|frag)$", 8),
    ("9b", "drm_format_modifiers export_import*_with_suballoc 24/96-bit (job 68: Fail; fix 000362f6ff4)",
     r"^dEQP-VK\.drm_format_modifiers\.export_import(_fmt_features2)?_with_suballoc\.(r8g8b8|b8g8r8|r32g32b32)_", 16),
    ("9c", "texturequerylod sampler2d_*_trilinear* (job 68: Fail; fix 4800173ec22)",
     r"^dEQP-VK\.glsl\.texture_functions\.query\.texturequerylod\.sampler2d_(fixed|float)_trilinear", 4),
    ("9d", "internally_synchronized_queues.device_wait_idle_device_wait_idle, dEQP watchdog off (job 68: Crash = 30 s watchdog)",
     r"^dEQP-VK\.synchronization2\.internally_synchronized_queues\.device_wait_idle_device_wait_idle$", 1),
]
KNOWN = [  # class, regex: non-pass rows that are expected to stay (see harness/research/vk11/RESULTS.md)
    ("hardware limit, Khronos waiver 4936 (offset >= extent with MIRRORED_REPEAT on Mali)",
     r"^dEQP-VK\.glsl\.texture_functions\.texture\w*offset\w*\.mirrored_repeat\."),
    ("upstream known (panfrost-g52-fails): line rasterization", r"^dEQP-VK\.rasterization\.primitives\.no_stipple\.lines"),
    ("upstream known (panfrost-g52-fails): global priority", r"^dEQP-VK\.api\.device_init\.create_device_global_priority"),
    ("non-conformant driver (conformanceVersion 0.0.0.0, upstream g52-fails)", r"^dEQP-VK\.api\.driver_properties\.conformance_version$"),
    ("resource limit: 1 GB board, 600 MB memcg (upstream g52-fails)", r"^dEQP-VK\.api\.object_management\.max_concurrent\.device"),
]


LARGE2 = "dEQP-VK.synchronization2.internally_synchronized_queues.large2_large2"
MEMREQ = (r"^dEQP-VK\.(memory\.requirements\.create_info\.image\.(regular|transient)_tiling_(linear|optimal)"
          r"|api\.invariance\.memory(_dedicated)?_requirements_matching)$")


def main():
    iso_part = sys.argv[4] if len(sys.argv) > 4 else None
    new, old = load(sys.argv[1], skip=iso_part), load(sys.argv[2])
    iso = load(sys.argv[1], only=iso_part) if iso_part else {}
    out = open(sys.argv[3], "w")
    counts = {}
    for r in new.values():
        counts[r[1]] = counts.get(r[1], 0) + 1
    print("COUNTS cases=%d %s" % (len(new), " ".join("%s=%d" % kv for kv in sorted(counts.items()))))
    for chk, title, rx, want in TARGETS:
        # the target cases = the rows of the group that were non-pass (not NotSupported) in job 68
        rows = [r for c, r in sorted(new.items()) if re.search(rx, c) and c in old
                and old[c][1] not in OK and old[c][1] != "NotSupported"]
        npass = sum(1 for r in rows if r[1] in OK)
        v = "PASS" if len(rows) == want and npass == want else "FAIL"
        print("CHECK %s %s: Pass %d of %d (%d in this run): %s" % (chk, title, npass, want, len(rows), v))
        for r in rows:
            if r[1] not in OK:
                print("  %s %s %s" % (r[0], r[1], r[3][:160] if len(r) > 3 else ""))
    iso_ok = False
    if iso_part:
        rows = [r for c, r in sorted(new.items()) if re.search(MEMREQ, c)]
        npass = sum(1 for r in rows if r[1] in OK)
        print("CHECK 9e memory requirements create_info.image regular/transient + api.invariance memory*_requirements_matching "
              "(job 70: Fail, stack garbage in vkGetDeviceImageMemoryRequirements; fix 26cb3c93a58): Pass %d of 6 (%d in this run): %s"
              % (npass, len(rows), "PASS" if len(rows) == 6 and npass == 6 else "FAIL"))
        for r in rows:
            if r[1] not in OK:
                print("  %s %s %s" % (r[0], r[1], r[3][:160] if len(r) > 3 else ""))
        r = iso.get(LARGE2)
        iso_ok = r is not None and r[1] in OK
        print("CHECK 9f %s alone in a fresh dEQP process (%s): %s: %s"
              % (LARGE2, iso_part, r[1] if r else "no row", "PASS" if iso_ok else "FAIL"))
    reg, fixed = [], []
    for c, r in sorted(new.items()):
        o = old.get(c)
        if o is None:
            continue
        if o[1] in OK and r[1] not in OK:
            if c == LARGE2 and iso_ok and r[1] in ("ResourceError", "OOM", "ResourceLimit"):
                print("INFO not counted in check 10: %s %s in the batch run, Pass alone (9f): memcg memory pressure" % (c, r[1]))
                continue
            reg.append((c, o[1], r))
        elif o[1] not in OK and o[1] != "NotSupported" and r[1] in OK:
            fixed.append((c, o[1], r))
    print("CHECK 10 regressions against job 68 (Pass/QualityWarning there, not now): %d: %s" % (len(reg), "PASS" if not reg else "FAIL"))
    for c, o, r in reg[:40]:
        print("  REG %s %s (job 68 %s) %s" % (c, r[1], o, r[3][:120] if len(r) > 3 else ""))
    print("INFO fixed against job 68 (non-pass there, Pass now): %d" % len(fixed))
    out.write("REGRESSIONS vs job 68: %d\n" % len(reg))
    for c, o, r in reg:
        out.write("  REG %s %s (job 68 %s) %s\n" % (c, r[1], o, r[3] if len(r) > 3 else ""))
    out.write("FIXED vs job 68: %d\n" % len(fixed))
    for c, o, r in fixed:
        out.write("  FIX %s (job 68 %s)\n" % (c, o))
    nonpass = [r for c, r in sorted(new.items()) if r[1] not in OK and r[1] != "NotSupported"]
    classes, other = {}, []
    target_rx = [t[2] for t in TARGETS]
    for r in nonpass:
        for name, rx in KNOWN:
            if re.search(rx, r[0]):
                classes[name] = classes.get(name, 0) + 1
                break
        else:
            if not any(re.search(rx, r[0]) for rx in target_rx):
                other.append(r)
    for name, rx in KNOWN:
        print("INFO remaining, %s: %d" % (name, classes.get(name, 0)))
    print("INFO remaining, not in the known classes and not a check-9 target: %d" % len(other))
    for r in other[:40]:
        print("  OTHER %s %s %s" % (r[0], r[1], r[3][:120] if len(r) > 3 else ""))
    out.write("NON-PASS: %d\n" % len(nonpass))
    for r in nonpass:
        out.write("  %s %s %s\n" % (r[0], r[1], r[3] if len(r) > 3 else ""))


if __name__ == "__main__":
    main()
