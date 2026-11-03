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
