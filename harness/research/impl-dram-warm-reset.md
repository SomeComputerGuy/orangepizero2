# H616 SPL DRAM misdetection after a watchdog reset (512 MiB / "not supported")

Branch `fix/sunxi-h616-dram-warm-reset` (fork, off `stonking-orangepizero2` 04ba728ea),
commit `5e3896880dfce366337251c8b8b33284b9d1e49b`. Patch:
`patch/u-boot/v2026.10-sunxi64/sunxi-dram-retry-transient-training-failures.patch`.
Worktree `/home/aruni/orangepizero2/wt-dram`; build dir `kernel-check/work-dram/`.
(The commit message says "26 patches apply". The build log says 25, mine included.)

## 1. What the log shows

`harness/serial.log` (lines from 2026-11-03 ~01:15):

```
[01:13:25] Out of memory: Killed process 36891 (test_basic) ...
           (2 min of silence: the system livelocks, the 16 s watchdog fires)
[01:15:29] U-Boot SPL 2026.10_armbian-2026.10-S5508-P5bdb-... (Nov 02 2026 - 22:44:34)
[01:15:29] DRAM:This DRAM setup is currently not supported.
[01:15:29] resetting ...
[01:15:29] U-Boot SPL ... (same build)
[01:15:29] DRAM: 512 MiB          <- U-Boot proper "DRAM:  512 MiB", Linux MemTotal 477000 kB
[01:22:47] reboot: Restarting system
[01:22:47] DRAM: 1024 MiB         <- normal again
```

Statistics over the whole log (script `/tmp/claude-scripts/spl.py`): there are **78 SPL boots**. 76 gave
`DRAM: 1024 MiB` (U-Boot proper `1 GiB`). The breakdown by reset type:

| preceding event | count | result |
|---|---|---|
| `reboot: Restarting system` (PSCI SYSTEM_RESET -> TF-A -> watchdog) | 37 | all 1024 MiB |
| `reboot: Power down` + Meross power-on | 11 | all 1024 MiB |
| harness power cycles (`MARK ...`) | ~10 | all 1024 MiB |
| U-Boot `reset` | 2 | 1024 MiB, 1x 512 MiB (the panic-induced one above) |
| unclean resets (kernel panic, RCU stall / hard lockup NMI, hangs -> watchdog) | ~17 | 16 x 1024 MiB, **1 x "not supported" (the OOM livelock)** |

So the failure is **not** "every watchdog reset". 16 other unclean or watchdog resets, several of them
after hard lockups, came up fine, on this SPL build and on older ones. The event happened once. It
happened after minutes of OOM thrashing, with avs2dec/deqp/test_basic workloads, the CPU busy and the
DRAM saturated. The next SPL pass 0.5 s later was only partly degraded (512 MiB), and 7 minutes later
everything was normal.

## 2. Code path (U-Boot v2026.10 = master for these files)

- `board/sunxi/board.c:713` prints `DRAM:` and then calls `sunxi_dram_init()`
  (`arch/arm/mach-sunxi/dram_sun50i_h616.c:1343`).
- `sunxi_dram_init()` -> `mctl_auto_detect_rank_width()` in `arch/arm/mach-sunxi/dram_dw_helpers.c:12-52`.
  This tries, in order, 32-bit/2 ranks, 32-bit/1 rank, 16-bit/2 ranks and 16-bit/1 rank. Each attempt
  is a full `mctl_core_init()`: `mctl_sys_init()`, which asserts the MBUS/DRAM/PLL5 resets, then
  `mctl_ctrl_init()` and `mctl_phy_init()`, which runs write leveling, read calibration, read training
  and write training. Each training step gets 5 tries; TPR10 0xf83438 enables all four. The scan
  **returns the first combination that trains** and otherwise calls
  `panic("This DRAM setup is currently not supported.\n")` (line 51). That is the message in the log.
  The other copies of the string in `dram_sun50i_h616.c` are DRAM-type `default:` cases, which are
  unreachable for DDR3.
- `panic()` -> `do_reset()` -> watchdog reset -> second SPL pass.
- The Zero2 normally lands on 32-bit/1 rank (cols 10, rows 15 -> 2^28 x 4 B = 1 GiB). 512 MiB with a
  clean scan means the 32-bit/1-rank training failed and a 16-bit combination trained. It is less
  likely a size-probe row misdetection: the probe calls `mctl_core_init()` twice
  (`dram_dw_helpers.c:96,122`) **and ignores the result**, as does the final
  `mctl_core_init()` in `sunxi_dram_init()` (h616.c:1355). So an untrained controller there could
  also produce a false alias and therefore a wrong row count.

### What survives a watchdog reset, and what doesn't explain it

- DRAM controller, PHY, MBUS, PLL_DDR0, DRAM mod clock: `mctl_sys_init()` (h616.c:95-142) puts all of
  them into reset and re-programs them on **every** `mctl_core_init()`, so each of the 4 attempts starts
  from a reset controller/PHY. Upstream already does the "full reset before init". It is not the gap.
- DDR3 devices: the uMCTL2 runs its own init sequence (INIT0 skip bits cleared in
  `dram_timings/h616_ddr3_1333.c:89`) and drives RESET# low for `INIT1.dram_rstn_x1024` = 0x42. That
  is 66x1024 DFI cycles, about 188 us at the 360 MHz core clock. JEDEC asks for 100 ns at stable power
  and 200 us at power-up. CKE stays low for the INIT0 reset default pre_cke (about 0x4e, about
  220 us), which is less than JEDEC's 500 us. The newer A523 DDR3 timings use 0x156/0x1f2 (about 1 ms
  and 1.4 ms). That is a real spec gap, but it is identical for cold and warm boots, and the cold
  boots never fail. I did **not** change it without board data (see "follow-ups").
- R_PRCM `RES_CAL_CTRL`/`OHMS240` are not reset by the watchdog, but `sunxi_dram_init()` rewrites
  them idempotently every boot. Our TF-A SYSTEM_SUSPEND patch touches no PRCM pad-hold bits
  (`0x250`), and no suspend happened in that boot.
- VDD-DRAM (AXP305 DCDCD) is not reset by the watchdog. The SPL re-sets it to 1500 mV
  (`CONFIG_AXP_DCDC4_VOLT`) before DRAM init, and TF-A reported 1.500 V afterwards.
- Retained DRAM contents cannot fool the aliasing probe. The pattern is address-derived, written only
  at physical address 0, and restored afterwards. In the failing boot the panic came *before* any probe.

The failure persisted through 4 full controller+PHY resets and DDR3 RESET# pulses within one
pass, was half gone 0.5 s later and was fully gone minutes later. That fits an **analog/thermal
transient** (die/DRAM temperature after the livelock, fixed DX/CA drive and ODT, training at 720 MHz)
better than a stale-register bug. **This cannot be proven from the log alone**, because the SPL has
no debug output and there is no temperature in the log.

**Confidence:**
- Code mechanism: high. The panic site and the "first trained combination wins" fallback to 16-bit
  are the only paths that produce exactly these two lines.
- Physical trigger: low to medium (transient training failure under heat/stress; not reproduced).

## 3. Upstream / vendor

- U-Boot master `dram_sun50i_h616.c` and `dram_dw_helpers.c` are byte-identical to v2026.10. The
  latest commits are "sunxi: dram: only probe DRAM inside the addressable range" (2026-10-26) and
  "detect non-power-of-2 sized DRAM chips". Jernej's 2025 "sunxi: h616: fix DRAM size detection"
  series fixed the address-wrap probe ("1 GiB board shows 2 GiB occasionally", Armbian forum).
  There is no upstream fix or report for training failure after a warm or watchdog reset, and no
  retry logic.
- Vendor: orangepi-build uses boot0/libdram blobs (legacy) or plain mainline (`v2021.10-sunxi`, "next").
  It has no GPL DRAM code to compare against (see `orangepi-build-mining.md`). libdram's A133 port
  switches INIT1 between 0x420000 and 0x1f20000 on a tpr13 flag (`dram_timings/a133_lpddr4.c:78`),
  which is the only warm-boot-related knob visible.

## 4. The fix (`sunxi-dram-retry-transient-training-failures.patch`)

All changes are in the shared `dram_dw_helpers.c`, which H6, H616 and A523 use, plus one line in
H616 `sunxi_dram_init()`:

1. `mctl_auto_detect_rank_width()` uses a table of the 4 combinations and runs up to 3 passes. It
   keeps the **most demanding combination that trained in any pass**. Later passes only try
   combinations more demanding than the current best, and it panics only if nothing trained in any
   pass. On the Zero2 the normal cost is 2 extra (fast-failing) 32-bit/2-rank attempts.
2. New `mctl_core_init_retry()` (up to 3 tries). It is used for both size-probe inits and the final
   H616 init, which previously ignored training failure. On a persistent failure it behaves exactly
   as before.
3. If a retry was needed, the SPL prints ` (training retried)` inside the DRAM line, e.g.
   `DRAM: (training retried) 1024 MiB`, so a test can grep for it.

This is the "retry instead of falling back to a wrong size" option. It is generic and
upstream-shaped (checkpatch clean). A board that really lacks a geometry fails training for it
reliably, so extra passes do not change detection on healthy boards.

Build: `HOSTCFLAGS=-DOPENSSL_ENGINE_STUBS ARMBIAN=wt-dram WORK=kernel-check/work-dram kernel-check/build-uboot.sh`.
This is the rootless, ccache'd mirror of Armbian's U-Boot build: compile.sh needs sudo, and the
HOSTCFLAGS is what `uboot.sh` adds on OpenSSL-4 hosts. 25/25 patches applied with 0 failures; the
build exits 0 with no warnings in the touched files. Output:
- `spl/u-boot-spl.bin`: 36848 B (+192)
- `sunxi-spl.bin`: 40960 B
- `u-boot-sunxi-with-spl.bin`: 899305 B
Output is in `kernel-check/work-dram/build/` (version string `_armbian-check`, not for flashing as a
release).

## 5. Board test plan (when the board is free)

Flash the Armbian-built U-Boot from the merged branch (SD: `dd ... seek=8` / `armbian-install`).
Then, on serial (`harness/serial.log`):

1. Cold boot x3 (Meross off/on): expect `DRAM: 1024 MiB` with no `(training retried)`. This confirms
   the extra passes do not change normal detection. Check that SPL to `Trying to boot` time is
   unchanged within the log granularity.
2. Soft reboots x20 (`reboot`): `grep -c 'DRAM: 1024 MiB'` must equal the boot count.
3. Watchdog resets x20 with no load. Use a real hardware watchdog expiry: the kernel's
   `sunxi-wdt` is armed by systemd (16 s), so freeze its pinger, e.g.
   `echo 1 > /proc/sys/kernel/sysrq; echo c > /proc/sysrq-trigger` with `kernel.panic=0` (the panic
   hangs and the watchdog fires about 16 s later). Expect `1024 MiB` every time. Also run a variant
   with `panic=1`, which takes the PSCI reboot path.
4. **The real reproducer:** heat plus a livelock. Run `stress-ng --cpu 4 --vm 2 --vm-bytes 90%`
   (or the avs2dec + deqp + test_basic mix) until OOM thrash, let the watchdog fire, and repeat 10x.
   Then grep `DRAM:` for each pass. On the unpatched SPL the expected failure rate is low (1 in the
   log). With the fix, the expected outcome is `1024 MiB`, possibly with `(training retried)`, and
   never 512 or "not supported". Read the SoC temperature just before the reset
   (`cat /sys/class/thermal/thermal_zone*/temp` in a loop to the console) to test the thermal
   hypothesis.
5. If `(training retried)` shows up or a failure persists: build the SPL with `#define DEBUG` in
   `dram_dw_helpers.c` (prints the combination tested) and `dram_sun50i_h616.c` (prints which
   training step failed) to pin the failing step and lane.

## 6. SPI NOR

BROM boot order is SD first, then SPI NOR. Every boot in this log came from `MMC1` except 4
`sunxi SPI` boots during the SPI-boot test. The SPI copy only runs when no bootable SD is present,
but it contains the same SPL DRAM code. **If `/dev/mtd0` still holds U-Boot** (first bytes
`eGON.BT0` at offset 4), reflash it with the new `u-boot-sunxi-with-spl.bin`
(`flashcp -v ... /dev/mtd0`) after the SD test passes. If it was erased (all 0xFF, per the T2 revert
step in `impl-uboot.md`), nothing is needed.

## 7. Follow-ups, deliberately not in this patch (need board data)

- JEDEC-compliant DDR3 init timing for H616 (INIT0 pre_cke >= 500 us, INIT1 RESET# >= 200 us, like
  the A523 DDR3 values 0x156/0x1f2): costs about 2.5 ms per `mctl_core_init()`. Try it if step 4
  still fails.
- Do the detection at a lower DRAM clock and then run the final init at CONFIG_DRAM_CLK, as the
  A523 driver does (`dram_sun55i_a523.c:1476`, `config.clk = 360`), for margin.

## 8. Board results (2026-11-03, SD image 16cdd50a9, SPL "Nov 03 2026 - 01:42:44" with this patch)

| test | runs | SPL DRAM line | "(training retried)" |
|---|---|---|---|
| cold boot (clean poweroff + Test Plug 2 off/on) | 3 | 3 x `DRAM: 1024 MiB` | 0 |
| `reboot` | 20 | 20 x `DRAM: 1024 MiB` | 0 |
| hardware watchdog (sysrq-c, kernel.panic=0, SPL about 15 s after the panic) | 20 | 20 x `DRAM: 1024 MiB` | 0 |
| hot/loaded watchdog reproducer | 0 valid | n/a | n/a |

MemTotal was 997772 kB every time. Pre-reset temperatures were 50-54 °C (cpu) and 48-51 °C (ddr). The
reproducer used stress-ng (72-78 °C cpu, 62-69 °C ddr) and then `kill -STOP 1` to starve the watchdog.
That never caused a reset, because the kernel ignores SIGSTOP to PID 1. Next time, freeze a process
that holds /dev/watchdog open instead, or reach a real OOM livelock. The SPI NOR (/dev/mtd0) holds the
old SPL "Nov 02 2026 - 00:31:49" (eGON.BT0, no retry code), so it needs reflashing (not done).

## 9. Hot-OOM watchdog resets (2026-11-03, image 4321861ff, same SPL "Nov 03 2026 - 01:42:44" = 5e3896880)

Raw per-reset data, serial excerpts and the two scripts (`hotwdt.py` host driver, `wdhold.py` board-side
holder) are in `dram-warm-reset/board-hot-oom-2026-11-03.txt` and the same directory.

**Load (every run):** `stress-ng --cpu 4 --cpu-method matrixprod --vm 2 --vm-bytes 100% --vm-keep --bigheap 1`.
The 4 cores are busy, 2 vm workers keep rewriting all free RAM, and bigheap grows through RAM plus the
487 MiB zram until the kernel OOM-kills it, then restarts. That gave 11-20 real
`Out of memory: Killed process` events per run before the reset.

**Trigger 1, "holder" (20 runs plus 1 validation run).** At runtime, systemd's RuntimeWatchdog is released
with `busctl set-property ... RuntimeWatchdogUSec t 0`. This is not persisted, and systemd re-arms 15 s on the
next boot (checked after every run). `wdhold.py` (mlocked, oom_score_adj -1000, nice -20; SCHED_FIFO
is refused in the ssh cgroup) opens `/dev/watchdog0` and sets WDIOC_SETTIMEOUT=5 s (10 s for the validation run).
It pets every 0.5 s for 90 s of load, then stops petting **without closing the fd**, and keeps writing a
temperature line to /dev/kmsg (crit, so it reaches serial) every second. The driver checks with `fuser`
that the holder's PID owns the device before it starts the load.

How we know this is a hardware watchdog reset:
- Linux stays alive and keeps logging up to the reset: no-pet lines at +1 ... +(T-1) s and OOM kills
  continue. Then the SPL banner appears with no `reboot:` / `Restarting system` line, and there is no panic.
- STOP->SPL was 4.0-5.0 s (mean 4.2) with a 5 s timeout and 9.5 s with a 10 s timeout. The gap follows the
  programmed timeout, measured with the serial logger's ~0.5 s granularity.
- During the 90 s of petting under the same load, no run ever reset.

**Trigger 2, "oompanic" (5 runs), a real kernel OOM.** systemd keeps the 15 s watchdog. Set with runtime
sysctl only: `vm.panic_on_oom=1`, `kernel.panic=0`. The first real OOM panics (`Kernel panic - not syncing:
Out of memory: system-wide panic_on_oom is enabled`) and the kernel hangs, so systemd stops petting and
sunxi-wdt fires. The panic->SPL time was 8.5-13.1 s, which fits a 15 s timeout with the last pet at most 7.5 s
earlier. The DRAM is idle for those ~10 s.

**Trigger 3, natural OOM livelock (1 case, the exact original chain).** While sizing the load at
06:44, ssh stopped answering after OOM kills, serial went silent after the last kill at 06:46:09, and
systemd's own 15 s watchdog reset the board at 06:46:31 (`DRAM: 1024 MiB`). A second attempt to reproduce
this on purpose (07:46-07:59: more than 100 OOM kills over 10.5 min, cpu up to 77.7 °C) never livelocked. A
livelock is not repeatable on demand, so trigger 2 replaced it.

| set | resets | temp at trigger (cpu / ddr, °C) | final DRAM | `(training retried)` | SPL panic | 512 MiB | ssh-up after SPL |
|---|---|---|---|---|---|---|---|
| holder, 5 s (and 10 s validation) | 21 | 71.1-75.6 / 62.4-66.8 (mean 74.2 / 65.3) | 21 x 1024 MiB / 1 GiB | **2** (runs 14, 19) | **1** (run 14) | 0 | 26.0-30.3 s |
| oompanic (real kernel OOM) | 5 | 67.0-75.3 / 61.1-65.8 | 5 x 1024 MiB | 0 | 0 | 0 | 26.4-28.8 s |
| natural livelock | 1 | ~65 / ~57 (2 min before) | 1024 MiB | 0 | 0 | 0 | ~25 s |

MemTotal was 997768 kB after every reset (27/27).

**Run 14 reproduced the original failure, and the fix contained it:**

```
[07:31:08.735] wdhold: STOP petting (timer) at t=90s; expect HW watchdog reset in 5s; cpu=74987 ddr=66806
[07:31:11.750] wdhold: no-pet +3.0s cpu=75554 ddr=66725
[07:31:12.755] U-Boot SPL 2026.10_armbian-... (Nov 03 2026 - 01:42:44 +0000)
[07:31:12.755] DRAM:This DRAM setup is currently not supported.
[07:31:12.755] resetting ...
[07:31:13.257] U-Boot SPL 2026.10_armbian-... (Nov 03 2026 - 01:42:44 +0000)
[07:31:13.257] DRAM: (training retried) 1024 MiB
```

In the first SPL pass, all 4 geometries failed training in all 3 passes, so the patch's panic ran. The
panic's `do_reset()` started a second pass about 0.5 s later. That pass still needed a retry, but this time
the widest geometry (32-bit/1 rank) trained, and the patch kept it. The original bug had the same shape:
"not supported", then 512 MiB on the next pass. The difference is the second pass: the unpatched SPL took the
first 16-bit geometry that trained and came up at 512 MiB, while the patched one kept retrying and got 1 GiB.
Run 19 needed a retry in a single pass (`DRAM: (training retried) 1024 MiB`), the case §4 was designed
for.

**Conclusions**

- 27/27 hot resets ended at 1 GiB, with no 512 MiB. The fix holds: no wrong size, and the board always boots.
- It does **not** prevent the first-pass panic. 1/21 hot holder resets still printed "not supported" and
  relied on the panic-reset for a second pass. Back-to-back retries, all within one SPL pass (under 0.5 s in
  total), are shorter than the transient.
- The transient is real and depends on load or heat. Idle resets (§8) gave 0 retries in 43 (wdt, reboot and
  cold). Hot resets with the DRAM saturated up to the moment of reset gave 2 retry events in 21, 1 of them a
  full-scan failure. The oompanic runs, where the DRAM sat idle for about 10 s before the reset, gave 0 in 5
  (a small sample). This supports the analog/thermal transient hypothesis from §2. It is about the
  DRAM state right after a busy reset, not the SoC temperature alone: oompanic runs reached similar
  temperatures and saw no retries.
- Possible hardening, not done here: a delay between passes in `mctl_auto_detect_rank_width()` (for
  example tens of ms, so the retries span the transient), and/or the §7 items (JEDEC DDR3 init timing,
  detection at a lower DRAM clock). Re-run this test (`hotwdt.py hot-wdt 20 holder 5 90 ...`) and look for
  the "not supported" count to reach 0.

## 10. v2: retry with backoff, JEDEC init delays, and the board plan (host-only so far)

The goal is no "not supported" panic in the hot case. In §9 run 14, all 12 attempts of the v1 fix
(3 back-to-back passes over 4 geometries, a few ms in total) failed. The board was only saved by the
panic reset about 0.5 s later. So retries have to last longer than the transient.

### What the code already does per attempt

Every `mctl_core_init()` runs `mctl_sys_init()`, which:
- asserts the MBUS, DRAM and PLL5 resets and gates;
- switches PLL5 off, re-programs it and waits for lock;
- re-enables the clocks.

`mctl_ctrl_init()` then runs the uMCTL2 init with skip_dram_init=0. That drives the DDR3 RESET# and CKE
sequence and the MR writes, then DFI init and PHY training. A "full controller/PHY reset and re-init
(clock/PLL re-lock) per retry" is therefore already there. What v1 lacked is **time** between attempts.

### Vendor boot0/libdram (`orangepi-build/.../sun50iw9/bin/boot0_sdcard.fex`, Thumb-2, load 0x20000, disassembled)

- `init_DRAM` at 0x27254:
  - sets the same PRCM RES_CAL/OHMS240 bits as mainline;
  - sets VCC-DRAM (DDR3 default 1500 mV, `0x24500`);
  - runs `auto_scan` (`0x26f84`: rank/width at `0x26eec`, then size) **only if dram_tpr13 bits 0 and 11 are clear**;
  - then runs one `mctl_core_init` (`0x26d28`, "DRAM initial error : 1 !" on failure) and a simple memtest;
  - if the memtest fails, it does one more full init plus memtest.
  - After a scan it sets tpr13 |= 0x6001, and the vendor U-Boot writes the found para1/para2/tpr13 back
    into the boot0 header. **Later vendor boots, warm resets included, never re-detect the geometry.** That
    is why the vendor stack cannot come up at 512 MiB after a bad scan, a risk that mainline's scan on
    every boot creates.
- PHY training (`0x27058`): with **tpr10 bit 19** set, each step (write leveling, read calibration,
  read and write training) gets up to 5 tries; mainline does this unconditionally. If any step still
  fails, the vendor code **recursively re-runs the whole `mctl_core_init`, up to 10 times** (global
  counter, then "retraining final error"). The Zero2's tpr10 = 0xf83438 has bit 19 set, so the vendor
  does up to 10 full re-inits. Mainline never re-inits. There is no delay between them.
- During the rank/width scan the vendor sets tpr10 bit 28 and restores it afterwards.
- A warm-path special case exists only for **standby resume**. If RTC 0x070001f8 bit 16 is set, para1,
  para2, tpr13 and the trained tpr6/tpr11/tpr12 are read back from RTC GP registers 8-15 ("Use rtc to
  store dram tuning para"). Nothing is specific to a watchdog reset.
- `mctl_sys_init` (`0x26c3c`) is the same as mainline: 5 us reset holds and a PLL re-lock. For DDR3, INIT1
  is 0x420000 and INIT0 keeps the controller default, both the same as mainline. So the vendor is **not**
  JEDEC-compliant on pre_cke either.

### v2 changes (fix branch `fix/sunxi-h616-dram-warm-reset`, worktree `wt-dram`)

- `50035418f` (patch A, updates `sunxi-dram-retry-transient-training-failures.patch`):
  - Once something has trained, the behaviour is v1's: 2 more fast passes for the more demanding
    combinations, with no added cost on a healthy board.
  - **While nothing has trained**, retry with backoff of 20, 40, 80, 160, 320, 320 and 320 ms
    (8 passes, 1.26 s of delay) before the panic. After a delay was needed, the 2 extra passes are
    delayed too.
  - The size probe and the final init use the same backoff, 8 tries.
  - The DRAM line now reads `DRAM: (training retried: pass N, M ms) 1024 MiB`, so the length of the
    transient is measured. "(training retried)" stays greppable.
  - Built SPL is 37088 B (+240 B; max 0xbfa0 = 49056 B).
- `ed4e53b0c` (patch B, new `sunxi-dram-h616-ddr3-jedec-init-delays.patch`): H616 DDR3 INIT0.pre_cke =
  550 us (0xc2) and INIT1.dram_rstn = 200 us (0x47), both derived from the clock. It is kept separate so
  its effect can be told apart from A's.
- Detection at a lower DRAM clock (A523 style) was **not** done. The run-14 failure was a total failure
  of every geometry, and keep-widest already covers the wrong-geometry risk. The final 720 MHz init would
  still need the retry. On H616 the PHY setup branches on clk (<=672 and >500 MHz), so the change carries
  LPDDR3/LPDDR4 risk without data. It is the next step only if A+B still panic.

**Timing cost.** On a healthy boot, A adds 0 ms: it runs the same attempts as v1. B adds about
0.33 ms per init x 7 inits, about 2.3 ms. In a transient, the cost is 20 ms+ per delayed pass, plus up
to 2 delayed passes for wider geometries. If nothing trains at all, the panic comes after about 1.3 s
of backoff plus 32 failing inits. There is no watchdog running in the SPL after a reset, so this time
is not constrained.

Artifacts:

| build | patches | sha256 |
|---|---|---|
| A, `kernel-check/work-dram/out-A/u-boot-sunxi-with-spl.bin` | retry/backoff only | c6d8425fdfea25c32157bdbadf4adea59c5e60d064c6885c30bc599089f2af7e |
| B, `kernel-check/work-dram/out-B/u-boot-sunxi-with-spl.bin` | A + JEDEC delays | c9fa17a72b9fba14f46751aa8dc07b08b756b22824d2d68c61e6191daf4b3bb1 |

Both images are 899305 B. The SPL banner reads `U-Boot SPL 2026.10_armbian-check (Nov 03 2026 - 08:1x)`,
which tells them apart from the image's `Nov 03 2026 - 01:42:44` SPL.

### Board plan (when the board is handed over; SD only, SPI NOR left untouched as the fallback)

```sh
H=/home/aruni/orangepizero2/harness; K="-i $H/id_ed25519 -o UserKnownHostsFile=$H/known_hosts -o StrictHostKeyChecking=no"
# 0. sanity: SD = mmcblk0, rootfs on it, first partition starts above the U-Boot area
$H/ssh.sh 'lsblk -o NAME,SIZE,MOUNTPOINT /dev/mmcblk0; cat /sys/block/mmcblk0/mmcblk0p1/start; dd if=/dev/mmcblk0 bs=1 skip=8196 count=8 2>/dev/null; echo'
#    expect p1 start >= 8192 (4 MiB) and "eGON.BT0"
# 1. backup of the current SD copy (8 KiB .. 4 MiB), kept on the board and on the host
$H/ssh.sh 'dd if=/dev/mmcblk0 of=/root/sd-uboot-4321861ff.bin bs=1024 skip=8 count=4088 && sha256sum /root/sd-uboot-4321861ff.bin'
scp $K root@10.56.0.107:/root/sd-uboot-4321861ff.bin $H/research/dram-warm-reset/
# 2. write build A
scp $K /home/aruni/orangepizero2/kernel-check/work-dram/out-A/u-boot-sunxi-with-spl.bin root@10.56.0.107:/root/u-boot-A.bin
$H/ssh.sh 'sha256sum /root/u-boot-A.bin && dd if=/root/u-boot-A.bin of=/dev/mmcblk0 bs=1024 seek=8 conv=fsync,notrunc && sync &&
  cmp -n 899305 /root/u-boot-A.bin <(dd if=/dev/mmcblk0 bs=1024 skip=8 count=879 2>/dev/null) && echo WRITE-OK'
# 3. reboot; serial.log must show the new SPL banner (08:1x build), "DRAM: 1024 MiB", Linux up, MemTotal 997768 kB
# 4. 10x reboot; 3x cold boot: systemctl poweroff, wait for "reboot: Power down" in serial.log, then
#    scripts/board-power.py off/on (Test Plug 2 .240 only, never .245); all 1024 MiB
# 5. python3 harness/research/dram-warm-reset/hotwdt.py hot-wdt 60 holder 5 90 <out>   (reads wdhold.py from its own dir)
#    accept: 0 x "not supported", 0 x 512 MiB; record each "(training retried: pass N, M ms)"
# 6. only if step 5 shows a panic: repeat 2-5 with out-B (A + JEDEC delays)
```

**End of slot:** if A (or B) passes, meaning 0 panics and 0 x 512 MiB, it stays on the SD, since it goes into the next image anyway. If it fails or anything looks off, restore the 4321861ff copy. The report must say which SPL the SD holds.

**Restore** the original SD copy (the image's SPL "01:42:44"):

```sh
harness/ssh.sh 'dd if=/root/sd-uboot-4321861ff.bin of=/dev/mmcblk0 bs=1024 seek=8 conv=fsync,notrunc && sync && echo RESTORED'
```

If the board's copy is gone, push the host copy back first:
`scp $K harness/research/dram-warm-reset/sd-uboot-4321861ff.bin root@10.56.0.107:/root/`.

**Risk.** BROM falls back to SPI NOR only when the SD has no valid eGON header (in practice: pull the SD). A new SPL that
hangs would therefore not fall back, and recovery would need physical access or FEL. The healthy path
of A and B runs the same code as the tested v1 (A) or differs only in two init register values (B),
so this risk is low, but it is not zero.

**Sample size.** The §9 baseline was 1 panic and 3 transient events in 21 resets. With 20 runs, an
unchanged panic rate still gives 0 panics 38% of the time, so 20 runs cannot show a fix. **60 runs**
(about 2.7 h) brings that to about 5%. The "(training retried: pass N, M ms)" events are the more
sensitive signal: each one is a transient that v1 might not have survived.

## 11. v2 board results (2026-11-03, raw: `dram-warm-reset/board-v2-2026-11-03.txt`)

| build | reboot / cold | hot holder resets | 1024 MiB | retried | "not supported" panic | 512 MiB |
|---|---|---|---|---|---|---|
| A (backoff) | 10 / 3, all 1024 MiB | 21 (stopped after the panic) | 21 | 7 | **1** (run 20) | 0 |
| B (A + JEDEC delays) | 3 / 1, all 1024 MiB | 60 | 60 | 21 | **0** | 0 |

The temperature when petting stopped was 66-77 °C cpu.

**A, run 20.** All 8 passes failed (about 1.3 s), so the SPL panicked. The SPL after the panic reset needed pass 6 (1310 ms). The glitch therefore lasted about 3 s or more.

**B.** It recovered every time. The retries were spread out:
- 9 resolved by pass 2 (17-160 ms).
- 4 at pass 3 (167-329 ms).
- 4 at pass 4 (336-659 ms).
- 4 at pass 5 (666-988 ms).
- **3 needed pass 7-8 (1325, 1647 and 1655 ms).** That is at the edge of the 8-pass, 1.26 s backoff budget.

So B's 0/60 is real but has little margin. Whether the JEDEC delays help is not proven: 0/60 against 1/21 is not significant, and the retry rate is the same (35% against 33%).

**Recommendation.** Merge A+B and raise the budget: `MCTL_MAX_PASSES` 12, about 2.5 s more of 320 ms waits. Healthy boots still cost nothing extra. The SD was left on B per the keep rule. The queue reflash then replaces it with the 5cc24a7c8 image's U-Boot.
