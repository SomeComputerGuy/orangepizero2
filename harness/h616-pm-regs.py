#!/usr/bin/env python3
# H616 PM bring-up helper (run as root on the board; needs /dev/mem, STRICT_DEVMEM is off).
#   h616-pm-regs.py            dump the CPU power / CPUIDLE registers
#   h616-pm-regs.py --trace    dump the BL31 PM trace page (0x4003f000)
#   h616-pm-regs.py --knob N   set the BL31 experiment knob (see below) and re-arm the trace
#   h616-pm-regs.py --arm      re-arm the per-core trace rings (frozen after a warm reset)
# Knob bits: 2:0 cpu-sleep mode (0 WFI-only/safe, 1 regular: CORE_CLOSE + WFI with the GIC
# CPU interface off, 3 = 1 but core 0 never gated; anything else = 0. Since round 5 the
# CPUIDLE_WAKE bit of a core is set while it is online and not touched on the idle path);
# bit3 suspend: clear PWRCTL.powerdown_en before requesting self-refresh; bit4 suspend: skip
# DRAM self-refresh; bit5 suspend: keep CPU clock/PLL; bit6 suspend: run
# standby routine from DRAM (implies bit4). The knob is reset to 0 by BL31 at every boot.
# Trace: SLEEP_* d0 = STAT (ENTER: mode | STAT << 8), d1 = PEND | WAKE << 8;
# CPUIDLE_STAT = (gated cores << 4) | (cores in WFI).
import mmap, os, struct, sys

TRACE_BASE = 0x4003f000
TRACE_LAYOUT = 3
DRAM_COM, DRAM_CTL = 0x047fa000, 0x047fb000   # H616 (0x0481/0x0482xxxx are the A133 blocks)
R_CPUCFG, CPUCFG = 0x07000400, 0x09010000
EVENTS = {1: 'BOOT', 2: 'CPU_ON', 3: 'CPU_OFF', 4: 'SLEEP_ENTER', 5: 'SLEEP_WAKE',
          6: 'SLEEP_WFI_RET', 7: 'STANDBY', 8: 'SYS_SUSPEND', 9: 'SYS_JUMP',
          10: 'SYS_RESUME', 11: 'SYSTEM_RESET', 12: 'SYSTEM_OFF', 13: 'SYS_DRAM',
          14: 'SYS_SR', 15: 'SYS_PWRCTL'}

def page(fd, addr, prot):
    return mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, prot, offset=addr & ~0xfff)

def rd(fd, addr):
    m = page(fd, addr, mmap.PROT_READ)
    v = struct.unpack_from('<I', m, addr & 0xfff)[0]
    m.close()
    return v

def regs(fd):
    for name, addr in [
        ('CPUCFG C0_CPU_STATUS (bit16+n STANDBYWFI n, bit0 STANDBYWFIL2)', CPUCFG + 0x80),
        ('CPUCFG C0_RST_CTRL (bit n: nCORERESET n)', CPUCFG + 0x00),
        ('CPUCFG DBG_REG0 (bit n: DBGPWRDUP n)', CPUCFG + 0xc0),
        ('R_CPUCFG C0_PWRON_RESET', R_CPUCFG + 0x40),
        ('R_CPUCFG C0_PWROFF_GATING (bit n: core n clamps active)', R_CPUCFG + 0x44),
        ('R_CPUCFG C0_CPU0_PWR_SWITCH (0x00 on, 0xff off)', R_CPUCFG + 0x50),
        ('R_CPUCFG C0_CPU1_PWR_SWITCH', R_CPUCFG + 0x54),
        ('R_CPUCFG C0_CPU2_PWR_SWITCH', R_CPUCFG + 0x58),
        ('R_CPUCFG C0_CPU3_PWR_SWITCH', R_CPUCFG + 0x5c),
        ('R_CPUCFG CPUIDLE_EN', R_CPUCFG + 0x100),
        ('R_CPUCFG CORE_CLOSE_FLAG', R_CPUCFG + 0x104),
        ('R_CPUCFG CPUIDLE_PEND', R_CPUCFG + 0x108),
        ('R_CPUCFG CPUIDLE_WAKE', R_CPUCFG + 0x10c),
        ('R_CPUCFG CPUIDLE_STAT', R_CPUCFG + 0x110),
        ('R_CPUCFG PWR_SW_DELAY', R_CPUCFG + 0x140),
        ('R_CPUCFG CONFIG_DELAY', R_CPUCFG + 0x144),
        ('CPUCFG C0_CTRL_REG0 (bits 27:24 AA64nAA32, must be f)', CPUCFG + 0x10),
        ('DRAM CTL MSTR', DRAM_CTL + 0x000),
        ('DRAM CTL STATR (op mode bits 1:0: 1 normal, 2 power-down, 3 self-refresh)', DRAM_CTL + 0x004),
        ('DRAM CTL CLKEN', DRAM_CTL + 0x00c),
        ('DRAM CTL PWRCTL (bit0 selfref_en, bit1 powerdown_en, bit5 selfref_sw)', DRAM_CTL + 0x030),
        ('DRAM CTL PWRTMG', DRAM_CTL + 0x034),
        ('DRAM CTL HWLPCTL', DRAM_CTL + 0x038),
        ('DRAM CTL DFIMISC', DRAM_CTL + 0x1b0),
        ('DRAM CTL SWCTL', DRAM_CTL + 0x320),
        ('DRAM CTL SWSTAT', DRAM_CTL + 0x324),
        ('DRAM COM MAER0', DRAM_COM + 0x020),
        ('DRAM COM MAER1', DRAM_COM + 0x024),
        ('DRAM COM MAER2', DRAM_COM + 0x028),
    ]:
        print('%08x = %08x  %s' % (addr, rd(fd, addr), name))

def ring(m, base, records):
    count = struct.unpack_from('<I', m, base)[0]
    out = []
    for i in range(max(0, count - records), count):
        ts, ev, d0, d1 = struct.unpack_from('<IIII', m, base + 0x10 + (i % records) * 16)
        out.append((ts, ev >> 24, ev & 0xff, d0, d1))
    return count, out

def show(recs, t0):
    for ts, core, ev, d0, d1 in recs:
        print('%12.3f ms  core%u  %-14s d0=%08x d1=%08x' % (((ts - t0) & 0xffffffff) / 24000.0,
              core, EVENTS.get(ev, str(ev)), d0, d1))

def trace(fd):
    m = page(fd, TRACE_BASE, mmap.PROT_READ)
    magic, gen, knob, freeze, layout = struct.unpack_from('<IIIII', m, 0)
    if magic != 0x4d505853:
        print('no trace page (magic %08x)' % magic)
        return
    if layout != TRACE_LAYOUT:
        print('trace page layout %u, this tool decodes layout %u: stale page of an older BL31, '
              'not decoded (the next BL31 boot clears it)' % (layout, TRACE_LAYOUT))
        return
    print('trace: boot generation %u, knob %#x, per-core rings %s' % (gen, knob, 'FROZEN (use --arm)' if freeze else 'armed'))
    # The system ring spans boots (the counter restarts at every reset): print it in recording
    # order, times relative to the record before (0 at a BOOT record).
    count, recs = ring(m, 0x40, 58)
    print('--- system ring: %u events (last %u shown, in recording order)' % (count, len(recs)))
    prev = None
    for ts, core, ev, d0, d1 in recs:
        dt = 0.0 if prev is None or ev == 1 else ((ts - prev) & 0xffffffff) / 24000.0
        prev = ts
        print('  +%10.3f ms  core%u  %-14s d0=%08x d1=%08x' % (dt, core, EVENTS.get(ev, str(ev)), d0, d1))
    allrecs = []
    for core in range(4):
        c, r = ring(m, 0x400 + core * 0x300, 46)
        n = {}
        for rec in r:
            n[rec[2]] = n.get(rec[2], 0) + 1
        last = ('last %s d0=%08x d1=%08x' % (EVENTS.get(r[-1][2], str(r[-1][2])), r[-1][3], r[-1][4])) if r else ''
        print('--- core %u ring: %u events; in window: ENTER %u WAKE %u WFI_RET %u; %s' % (
              core, c, n.get(4, 0), n.get(5, 0), n.get(6, 0), last))
        allrecs += r
    allrecs.sort()
    show(allrecs, allrecs[0][0] if allrecs else 0)
    m.close()

def write_hdr(fd, offset, value):
    m = page(fd, TRACE_BASE, mmap.PROT_READ | mmap.PROT_WRITE)
    struct.pack_into('<I', m, offset, value)   # no msync: /dev/mem rejects it, the write is direct
    v = struct.unpack_from('<I', m, offset)[0]
    m.close()
    return v

fd = os.open('/dev/mem', os.O_RDWR | os.O_SYNC)
if len(sys.argv) > 1 and sys.argv[1] == '--trace':
    trace(fd)
elif len(sys.argv) > 1 and sys.argv[1] == '--arm':
    print('freeze = %u' % write_hdr(fd, 0xc, 0))
elif len(sys.argv) > 2 and sys.argv[1] == '--knob':
    write_hdr(fd, 0xc, 0)
    print('knob = %#x' % write_hdr(fd, 8, int(sys.argv[2], 0)))
else:
    regs(fd)
