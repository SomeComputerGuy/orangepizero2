# CPU idle + system suspend (Orange Pi Zero2 / H616) — research + implementation

Worktree `/home/aruni/orangepizero2/wt-pm` (Armbian build framework, base
`stonking-orangepizero2` @ 88948c3). TF-A `lts-v2.14.11` (`PLAT=sun50i_h616 DEBUG=1 bl31`),
U-Boot v2026.10, kernel 7.3.1 (`patch/kernel/archive/sunxi-7.3`). Nothing pushed, board
untouched. Starting point measured on the board: `cpuidle current_driver: none`, TF-A
`PSCI: Suspend is unavailable`, no idle-states in the DT, s2idle works, no `mem`/deep.

## 1. Research summary (what the silicon and the firmware ecosystem offer)

### No management core on the H616
* Andre Przywara's H616 bring-up series: "the SoC gets the management controller removed,
  which in turn removes *some*, but not all of the devices formerly dedicated to the ARISC
  (CPUS)"; Icenowy Zheng: "H616 has no SRAM A2" (where BL31 + crust live on A64/H5/H6).
  Sources: <https://groups.google.com/g/linux-sunxi/c/x4jU5zFITro>,
  <https://lists.infradead.org/pipermail/linux-arm-kernel/2021-January/632104.html>.
* Crust (the open SCP firmware that gives A64/H5/H6 their idle + suspend) lists A23, A64,
  A83T, H3, H5, H6 only (README "Supported devices"); it runs on the OpenRISC AR100 which
  the H616 does not have. <https://github.com/crust-firmware/crust>
* Consequently upstream TF-A `plat/allwinner/sun50i_h616/platform.mk` sets
  `SUNXI_PSCI_USE_SCPI := 0`, `SUNXI_PSCI_USE_NATIVE := 1`, and `sunxi_idle_states[]` is
  empty; `sunxi_native_pm.c` only implements CPU_ON/CPU_OFF/SYSTEM_OFF/SYSTEM_RESET
  (verified in the lts-v2.14.11 tree and on upstream master, 2026-11-02).

### What TF-A Gerrit has (review.trustedfirmware.org, query `project:TF-A/trusted-firmware-a allwinner`, 2026-11-02)
* Nothing implements native CPU_SUSPEND or SYSTEM_SUSPEND for any Allwinner SoC. Related
  merged work: `e2b18771` "feat(allwinner): provide CPU idle states to the rich OS"
  (Samuel Holland, SCPI-only: `fdt_add_cpu_idle_states()` + `sunxi_idle_states[]`),
  change 22821 "fix(allwinner): enable dtb modifications for CPU idle states" (A. Skvortsov,
  A64, 2024-10). Pending refactors that touch the same files: 44621 "make native PM A53
  specific" (J. Skrabec/A. Przywara, renames `sunxi_native_pm.c` → `sunxi_native_pm_a53.c`),
  44620 "use generic GIC driver", 55194-55205 A523/A733 series (A. D'Silva). Our patches are
  written against lts-v2.14.11 and will need a trivial file rename on top of 44621.
* `sun50i_a64/sunxi_idle_states.c` (crust-backed) documents the SCPI power-state encoding:
  `cpu-sleep` 0x00010003 (800/1500/25000 µs), `cluster-sleep` 0x01010013 — we reuse the
  encoding so one idle table serves both PSCI back ends.

### The CPUIDLE hardware block (the key enabler)
* linux-sunxi wiki "CPUIDLE": hardware block in R_CPUCFG on R40/H6 and newer that
  "implements the CPU/cluster idle process in hardware"; registers at R_CPUCFG
  (0x07000400 on H616): 0x100 CPUIDLE_EN, 0x104 CLOSE_FLAG, 0x108 CPUIDLE_PEND,
  0x10c CPUIDLE_WAKE, 0x110 CPUIDLE_STAT, 0x140/0x144 PWR_SW/CONFIG delays
  (<https://linux-sunxi.org/CPUIDLE>; the site blocks automated fetches, summary via search
  snippets + TF-A's `sunxi_cpucfg_ncat.h`, which defines exactly these registers).
* Upstream TF-A already uses it for CPU_OFF on H6/H616/A133:
  `sunxi_cpu_power_off_self()` writes the enable keys 0x16aa0000 / 0xaa160001 to
  CPUIDLE_EN and the core's bit to CORE_CLOSE, then the PSCI core executes WFI and the
  hardware removes the core's power (`plat/allwinner/sun50i_h616/sunxi_power.c`).
* Allwinner's own kernel-side driver for the same block (linux-3.10
  `drivers/cpuidle/cpuidle-sunxi.c`, R40 generation) shows the full contract: enable with
  the two key writes, set PWR_SW_DELAY, per core: `gic_cpu_if_down()` (CPU interface
  **disabled** before sleeping), set CORE_FLAG bit, clean L1, leave SMP, WFI; the core is
  powered up again by hardware when an interrupt is pending for it and restarts at its reset
  vector. That the CPU interface is disabled proves the wake detection uses the GIC-400
  power-controller outputs (`nIRQOUT/nFIQOUT`, independent of GICC_CTLR) — the same
  signals crust reads back as `CPUIDLE_PEND_REG` on H6 (`drivers/css/sun50i-h6-css.c`).
* Allwinner's H616 BSP confirms the vendor TF-A does exactly this over PSCI:
  `orange-pi-5.4-sun50iw9` `arch/arm64/boot/dts/sunxi/sun50iw9.dtsi` has
  `cpu-idle-states = <&CPU_SLEEP>` on all four cores with
  `arm,psci-suspend-param = <0x0010000>`, `local-timer-stop`, entry 46 µs, exit 59 µs,
  min-residency 3570 µs, and no cluster state. Its suspend wake-source plumbing is an
  `allwinner,sunxi-wakeupgen` irqchip that forwards `irq_set_wake` to BL31 via SiP SMCs
  (`drivers/irqchip/irq-sunxi-wakeupgen.c`), i.e. the vendor BL31 also implements system
  standby on the CPU itself (its source is not published).

### DRAM self-refresh without an SCP
* The H616 DRAM controller is a DesignWare uMCTL2 (U-Boot `dram_sun50i_h616.h`: `statr`
  0x004, `pwrctl` 0x030, standard layout; bases `SUNXI_DRAM_COM_BASE 0x04810000`,
  `CTL0 0x04820000`, `PHY0 0x04830000` in `cpu_sun50i_h6.h`).
* Crust's H6 DRAM code (`drivers/dram/sun50i-h6-dram.c`, BSD-3-Clause) is the reference
  sequence: disable MBUS masters (MC_MAER0..2 = 0), set PWRCTL.selfref_en, poll
  STATR.operating_mode == 3 (self-refresh), optionally stop CK via PHY PGCR3 and the
  DRAM/MBUS clocks; resume in reverse and poll operating_mode == 1.
* The only agent left to run that sequence is CPU0, and it cannot execute from DRAM while
  the DRAM is in self-refresh: the code must run from SRAM. SRAM A1 (0x00020000, 32 KiB) is
  free after the SPL (BL31 itself lives in DRAM on the H616, `SUNXI_BL31_IN_DRAM`).
  TF-A maps the SRAM as device memory, execute-never, so the SRAM routine runs with the MMU
  off (BL31 is identity mapped, so turning the MMU off in DRAM code is seamless).
* Linux side: `psci_init_system_suspend()` registers `suspend_set_ops` when PSCI_FEATURES
  reports SYSTEM_SUSPEND, which makes `deep` appear in `/sys/power/mem_sleep`; the GICv2
  driver only saves/restores the per-CPU interface across suspend (arm64 has no
  CPU_CLUSTER_PM notifications), so firmware must keep the distributor powered — which the
  design below does.
* Timer: a `local-timer-stop` state needs a broadcast clock event device; mainline H616 has
  `timer@3009000` (`allwinner,sun50i-h616-timer`,`allwinner,sun8i-a23-timer`,
  `timer-sun4i.c`, DYNIRQ-capable), so the deep state is enterable (otherwise cpuidle would
  silently fall back to WFI).

### Decision — what is achievable on this silicon
| capability | verdict | mechanism |
|---|---|---|
| cpuidle state 0 (WFI) | already | kernel |
| cpuidle **core power-down** (`cpu-sleep`) | **implemented** (TF-A patch 1 + DT patch) | CPUIDLE block: CORE_CLOSE + WFI, hardware power-up on pending GIC IRQ, reset into BL31 warm entry |
| cpuidle cluster power-down (`cluster-sleep`) | **impossible natively** | cluster power-off needs an agent outside the cluster to power it on again (crust does this on H6 via `C0_PWROFF_GATING`/`C0_PWRON_RESET`); nothing exists on the H616. The CPUIDLE block only sequences cores. |
| SYSTEM_SUSPEND / Linux `mem` = `deep` | **implemented** (TF-A patch 2), experimental | CPU0 parks in SRAM A1 at 24 MHz, PLL_CPUX off, DRAM in self-refresh, cores 1-3 off (CPU_OFF by Linux), GIC on; any GIC-enabled IRQ wakes |
| VDD_CPU / rail power-off in suspend | **impossible** | with the CPU off nothing could switch the rails back on (AXP305 has no wake input other than its own IRQ into the dead SoC). Lowering VDD_CPU to the 24 MHz-safe minimum over RSB before entering SRAM is a follow-up (needs the DT regulator minimum, not hard-coded voltages). |
| DRAM clock/PLL_DDR off, PHY CK stop in suspend | follow-up | H616 PHY register layout differs from the H6 one crust drives; keep CK running in v1 (safe, DDR3 allows it) |
| wake sources | RTC alarm, any GPIO/EINT or peripheral IRQ Linux leaves enabled (`enable_irq_wake`), IR (R_IR) once the OS enables it | GIC distributor stays on, pending IRQ ends WFI |

## 2. Design (TF-A, native PSCI ops, platform-gated)

Patch 1 `feat(allwinner): offer CPU_SUSPEND natively on the H616`
(`patch/atf/atf-sunxi64/0001-…`):
* `allwinner-common.mk`: `SUNXI_NATIVE_CPU_SUSPEND ?= 0` (+define, requires native ops);
  `sun50i_h616/platform.mk` sets it to 1. A64/H5/H6/R329 BL31 binaries are unchanged
  (sizes verified identical).
* `sunxi_native_pm.c`: `cpu_standby` (WFI with SCR.IRQ), `validate_power_state` (CPU level
  only, SCPI encoding: standby/1 → retention, powerdown/3 → off), `pwr_domain_suspend`
  (= `gicv2_cpuif_disable(); sunxi_cpu_power_off_self();`, the CPU_OFF path),
  `pwr_domain_suspend_finish` (= on_finish: per-CPU GIC init + CPU interface enable).
  The generic PSCI code has cleaned L1 and left SMP before, and executes the WFI that lets
  the CPUIDLE block gate the core; the hardware powers it back up on a pending interrupt
  and it resets into `bl31_warm_entrypoint` (RVBAR, as for CPU_ON).
* `sunxi_pm.c`: `sunxi_psci_has_cpu_suspend()`; log line `PSCI: CPU suspend is available
  natively` replaces `PSCI: Suspend is unavailable`.
* `sunxi_prepare_dtb.c`: add idle states to the DTB when the ops implement CPU_SUSPEND
  (not only for SCPI) and `/cpus/idle-states` does not already exist.
* `sun50i_h616/sunxi_idle_states.c`: `cpu-sleep` = 0x00010003, local-timer-stop,
  entry 100 / exit 150 / min-residency 4000 µs (initial estimates; vendor 46/59/3570).

Patch 2 `feat(allwinner): implement SYSTEM_SUSPEND natively on the H616`
(`patch/atf/atf-sunxi64/0002-…`), `SUNXI_NATIVE_SYSTEM_SUSPEND` (H616 only):
* `get_sys_suspend_power_state` → all levels OFF (advertises SYSTEM_SUSPEND);
  `pwr_domain_suspend` leaves the GIC CPU interface **enabled** for the system state;
  `pwr_domain_pwr_down` (the "may not return" hook) → `sunxi_native_system_suspend_pwr_down()`.
* `sunxi_native_suspend.c` (runs with D-cache off, L1+L2 cleaned by PSCI's
  `cortex_a53_cluster_pwr_dwn`, other cores already CPU_OFF): CPUX_AXI_CFG mux → OSC24M,
  PLL_CPUX disabled; copies the SRAM routine word-wise into SRAM A1; sets SCR_EL3.IRQ so a
  pending Non-secure IRQ ends the WFI (PSTATE.I stays masked, nothing is taken);
  `sunxi_standby_jump()` turns MMU/caches off and branches into SRAM.
* `sunxi_standby_sram.S`: position independent, no stack/DRAM: save MAER0..2 and clear
  them; PWRCTL |= selfref_en|selfref_sw; poll STATR.op_mode==3 (bounded); `dsb; isb; wfi`;
  restore PWRCTL; poll op_mode==1 (bounded); restore MAERs; store a status word
  (valid | entry-timeout | exit-timeout) to a DRAM variable; `br bl31_warm_entrypoint`.
  Bounded polls make a wrong assumption about the controller degrade to "CPU0 in WFI at
  24 MHz, DRAM active" instead of a hang.
* Resume path: warm boot → `psci_cpu_suspend_to_powerdown_finish` →
  `sunxi_native_system_suspend_finish()`: PLL_CPUX re-enabled with LOCK_ENABLE, wait for
  LOCK (1 ms bound), restore CPUX_AXI_CFG, report
  `PSCI: system resumed, DRAM was in self-refresh` (or a WARN naming the failed step),
  then GIC per-CPU init; Linux resumes at `cpu_resume`, re-onlines CPUs 1-3 via CPU_ON.

Kernel (`feat/sunxi-h616-cpuidle-dt`): `patches.armbian/arm64-dts-sun50i-h616-add-cpu-idle-states.patch`
adds `/cpus/idle-states/cpu-sleep` (same parameters) and `cpu-idle-states = <&cpu_sleep>`
to all four cores, because U-Boot does not propagate TF-A's DTB amendment into the kernel
DTB Armbian loads (same reason the bl31 reserved-memory node is static in the dtsi).
No kernel config change needed: the built `.config` already has `CPU_IDLE`, `CPU_IDLE_GOV_MENU`,
`DT_IDLE_STATES`, `ARM_PSCI_CPUIDLE(_DOMAIN)`, `CPU_PM`, `SUSPEND`, `PM_SLEEP_SMP`,
`RTC_DRV_SUN6I`, `RTC_SYSTOHC`.

## 3. Branches / commits (wt-pm, Armbian fork; TF-A source commits in `kernel-check/work-pm/atf`)

| branch | commit | content |
|---|---|---|
| `feat/atf-h616-psci-cpu-suspend` | 0f98d19 | `patch/atf/atf-sunxi64/0001-feat-allwinner-offer-CPU_SUSPEND-natively-on-the-H616.patch` |
| `feat/atf-h616-system-suspend` (on top of the previous) | 91bda74 | `patch/atf/atf-sunxi64/0002-feat-allwinner-implement-SYSTEM_SUSPEND-natively-on-the-H616.patch` |
| `feat/sunxi-h616-cpuidle-dt` | 8f4186a | `patches.armbian/arm64-dts-sun50i-h616-add-cpu-idle-states.patch` + `series.conf` |
| **`wt-pm-integration`** | 88be7bb, bff53ed | merges of the above onto stonking-orangepizero2 |

TF-A source branch `feat/h616-native-suspend` in `kernel-check/work-pm/atf` (clone of
lts-v2.14.11): 71143e8 (patch 1), b7bf314 (patch 2) — ready for `git push` to Gerrit
after a rebase on master (needs the 44621 rename if that lands first).

`kernel-check/build-uboot.sh` gained `ATFPATCHDIR` (default `atf-sunxi64`): applies
`patch/atf/<dir>/*.patch` (+`board_<BOARD>/`) to a pristine TF-A tree exactly like
Armbian's `advanced_patch`, and rebuilds bl31 only when the patch-set hash changes
(`$WORK/atf-patches.sha`). Default behaviour without patches is unchanged
(backup of the previous script: `build-uboot.sh.bak-pm`).

## 4. Build results

* TF-A, all sunxi64 platforms with both patches (`kernel-check/work-pm/atf`, ccache,
  `DEBUG=1 bl31`): sun50i_h616 57460 B (was 53364; +4 KiB for the suspend code, well inside
  the 256 KiB DRAM region), sun50i_a64 45272 B, sun50i_h6 45172 B, sun50i_r329 41076 B —
  the last three byte-identical in size to the unpatched build (gated code compiled out);
  no compiler warnings in the new files. The SRAM routine disassembles to 40 instructions
  with no literal loads or absolute addresses (position independent, as required).
* `ARMBIAN=wt-pm WORK=kernel-check/work-pm/uboot kernel-check/build-uboot.sh` (integration
  branch): `TF-A patch applied: 0001…`, `0002…`, `bl31.bin: 57460 bytes (TF-A patches: 2,
  set 1f23abd2d34ccbe1)`, U-Boot `patches applied: 25, failed: 0`, `build exit: 0`,
  `u-boot-sunxi-with-spl.bin 899305 bytes` (fits SPI NOR, SPL 40960).
* `ARMBIAN=wt-pm WORK=kernel-check/work-pm/kernel STAGE=dtbs kernel-check/build-kernel.sh`:
  `patches applied: 709, failed: 0` (the new DT patch applies after the display-pipeline
  patch that touches the neighbouring context), all allwinner DTBs + 55 H616 overlays built,
  `DT_CHECK ok: cpu-idle-states / arm,psci-suspend-param / local-timer-stop`; the decompiled
  Zero2 DTB has `/cpus/idle-states/cpu-sleep` (0x10003, 100/150/4000 µs) referenced by all
  four CPUs, `timer@3009000` enabled (broadcast source) and the static `secmon@40000000`
  reservation. The kernel Image/modules are unchanged (no config change) — only the DTB
  needs replacing on the board for the cpuidle test; the full Armbian image rebuild on
  `wt-pm-integration` picks up everything.
* Artifacts for the board (sha256 in `SHA256SUMS`): `kernel-check/work-pm/out/`
  `u-boot-sunxi-with-spl.bin` (06b0b2de…), `bl31.bin` (038878f3…),
  `sun50i-h616-orangepi-zero2.dtb` (3fc9fadc…).

## 5. Board test plan (coordinator)

### 5.0 Flash / roll back
* New image: `kernel-check/work-pm/out/u-boot-sunxi-with-spl.bin` (BL31 inside the FIT; copy
  of `work-pm/uboot/build/`). Write at 8 KiB: `dd if=u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1k seek=8 conv=fsync`
  (or `write_uboot_platform_mtd` for SPI NOR). Kernel DTB:
  `kernel-check/work-pm/out/sun50i-h616-orangepi-zero2.dtb` → `/boot/dtb/allwinner/` on the
  board (keep a copy of the old one) (the full image rebuild via `./compile.sh
  opiz2-printserver` on `wt-pm-integration` produces both).
* Roll back: previous known-good bootloader
  `/home/aruni/orangepizero2/kernel-check/work-uboot/out/u-boot-sunxi-with-spl.bin`
  (same `dd` command). Software-only fallbacks that keep the new bl31:
  `cpuidle.off=1` on the kernel command line (no deep idle), or at runtime
  `echo 1 | tee /sys/devices/system/cpu/cpu*/cpuidle/state1/disable`; for suspend simply
  keep using `s2idle` (`echo s2idle > /sys/power/mem_sleep`).

### 5.1 Boot log (serial), expected new lines from BL31
```
NOTICE:  BL31: v2.14.11(debug):...
INFO:    PSCI: CPU suspend is available natively        <- was: PSCI: Suspend is unavailable
INFO:    Changed devicetree.
```
Linux: `dmesg | grep -i 'psci\|cpuidle'` →
`psci: probing for conduit method from DT.`, `psci: PSCIv1.1 detected in firmware.`,
`psci: SMC Calling Convention v1.x`, `cpuidle: using governor menu`,
`cpuidle-psci: ... ` (no "failed" lines). `cat /sys/devices/system/cpu/cpuidle/current_driver`
→ `psci_idle` (was `none`). `cat /sys/power/mem_sleep` → `s2idle [deep]` (or `[s2idle] deep`;
`deep` being listed is what patch 2 adds).

### 5.2 cpuidle
```
grep . /sys/devices/system/cpu/cpu*/cpuidle/state*/name      # state0 WFI, state1 cpu-sleep
grep . /sys/devices/system/cpu/cpu*/cpuidle/state1/{usage,time,above,below,rejected}
sleep 10; grep . /sys/devices/system/cpu/cpu*/cpuidle/state1/{usage,time}
```
Expected: `usage` and `time` (µs) of `state1` increase on all four CPUs while idle;
`rejected` stays 0 (non-zero = firmware returned an error for CPU_SUSPEND → wrong bl31).
Hotplug still works: `echo 0 > /sys/devices/system/cpu/cpu3/online; echo 1 > ...`.
Stress: `for i in $(seq 200); do sleep 0.05; done` and a few minutes of
`ping -i 0.2 <host>`; no RCU stalls / "NOHZ tick-stop error" messages. Latency check for the
estimates in the DT/TF-A table: `above` (state too deep) vs `below` (too shallow) counters,
and `cyclictest -t4 -p80 -i1000 -l20000` max latency should stay well under 1 ms.
Power (Meross plug): idle consumption should drop versus the pre-patch idle baseline (cores
now power-gate instead of WFI at 1.5 GHz; the magnitude depends on how often the governor
picks state1 — compare `time` to wall time).

### 5.3 suspend-to-RAM
```
dmesg -w &   # or keep the serial console
echo deep > /sys/power/mem_sleep
rtcwake -m mem -s 10
```
Expected on serial: Linux `PM: suspend entry (deep)`, `Disabling non-boot CPUs ...`,
`psci: CPU1..3 killed` (CPU_OFF), then silence ≈ 10 s (BL31 prints nothing while in SRAM),
then on wake BL31 (DEBUG build) prints
`INFO:    PSCI: system resumed, DRAM was in self-refresh`, Linux `Enabling non-boot CPUs`,
`PM: suspend exit`, `rtcwake` returns, `date` advanced by ~10 s, network/USB/console work
(round trip like the existing s2idle 12 s test). Repeat 10x in a loop
(`for i in $(seq 10); do rtcwake -m mem -s 5; sleep 3; done`) and once with a longer
`-s 120` to confirm the RTC alarm wake and DRAM integrity (run `memtester 64M 1` or
`sha256sum` of a large file before/after).
Power: the plug should show a clear drop relative to s2idle (expected order: a few hundred
mW less; cores off, CPU0 at 24 MHz, DRAM in self-refresh; USB/Ethernet PHY still powered).

Failure signatures and what they mean:
* `WARN: PSCI: DRAM did not enter self-refresh` and the system resumes fine → the
  controller rejected `selfref_sw/selfref_en` (poll timed out); suspend worked as "CPU0 WFI
  at 24 MHz" only. Report the line; next step is to read STATR/PWRCTL from U-Boot (`md.l
  0x04820004 1; md.l 0x04820030 1`) and compare to the uMCTL2 version.
* `WARN: PSCI: DRAM did not leave self-refresh` → should not happen with the entry working;
  if DRAM is corrupt the kernel will oops right after — power-cycle, roll back bl31.
* No output at all after the ~10 s and no wake → CPU0 did not leave WFI: a wake IRQ did not
  reach the GIC (check the RTC alarm actually fires with s2idle first), or the SRAM routine
  faulted (MMU-off fault at EL3 = hang). Power-cycle via the Meross plug; the kernel log on
  the next boot has nothing (RAM lost). Roll back bl31 or keep `s2idle`.
* `PSCI: PLL_CPUX failed to lock` → system still runs at 24 MHz; cpufreq will reprogram the
  PLL on the next frequency change; report.
* Resume but immediate Oops/hang → suspect DRAM state; roll back, report.

### 5.4 What to collect
`dmesg`, the serial log (TF-A INFO/WARN lines), the cpuidle sysfs counters before/after,
`cat /sys/kernel/debug/wakeup_sources`, Meross power readings (idle baseline, cpuidle on,
s2idle, deep).

## 6. Sources
* TF-A lts-v2.14.11 `plat/allwinner/*` (local: `kernel-check/work-uboot/arm-trusted-firmware`),
  master copies of `sunxi_native_pm.c`, `sunxi_pm.c`, `sunxi_prepare_dtb.c`,
  `sun50i_h616/platform.mk`, `sun50i_a133/sunxi_power.c` (raw.githubusercontent.com, 2026-11-02).
* TF-A Gerrit REST `changes/?q=project:TF-A/trusted-firmware-a+allwinner` (60 newest),
  changes 22821 and 44621 patches.
* linux-sunxi wiki: CPUIDLE, PPU, H616 (via search snippets; direct fetch returns 403).
* Allwinner `H616_User_Manual_V1.0` (local PDF, `kernel-check/work-audio/vendor/`; CCU
  register names/offsets; the CPUIDLE block is not documented there — it refers to the
  separate "H616_CPU_AP_Note").
* Vendor BSP: `orangepi-xunlong/linux-orangepi` branch `orange-pi-5.4-sun50iw9`
  (`arch/arm64/boot/dts/sunxi/sun50iw9.dtsi`, `drivers/irqchip/irq-sunxi-wakeupgen.c`);
  `tinalinux/linux-3.10 drivers/cpuidle/cpuidle-sunxi.c` (kernel-side CPUIDLE block driver).
* crust: `README.md`, `drivers/dram/sun50i-h6-dram.c`, `drivers/css/sun50i-h6-css.c`.
* U-Boot v2026.10 `arch/arm/include/asm/arch-sunxi/{dram_sun50i_h616.h,cpu_sun50i_h6.h,clock_sun50i_h6.h}`.
* Linux 7.3.1 `drivers/cpuidle/cpuidle-psci.c`, `drivers/firmware/psci/psci.c`,
  `drivers/clocksource/timer-sun4i.c`, `drivers/irqchip/irq-gic.c`,
  `arch/arm64/boot/dts/allwinner/sun50i-h616.dtsi`.
* Samuel Holland, "[RFC PATCH] arm64: dts: allwinner: a64/h5: Add CPU idle states"
  <https://groups.google.com/g/linux-sunxi/c/Av5NCD5a5VI>; xnux.eu log 077 (cpuidle needs
  `SUNXI_AMEND_DTB`).

## 7. Board round 1 (coordinator, 2026-11-02): hang with new bl31 + new DTB — analysis

Observed: (A) new bl31 + new DTB via boot.scr → `PSCI: CPU suspend is available natively`,
`Starting kernel ...`, then nothing, no network, also with `earlycon=... keep_bootcon`;
(B) new bl31 + original DTB, manual `booti` with hand-written bootargs → boots;
(C) old bl31 + new DTB via boot.scr → boots.

### Root cause (from code; to be confirmed with E1-E3 below)
1. **The kernel in (A) almost certainly booted — it is just silent.** Armbian's
   `boot-sun50i-next.cmd` builds `bootargs` with `loglevel=${verbosity}` and `verbosity`
   defaults to **1** (KERN_ALERT only), so neither `Booting Linux on physical CPU` (pr_info)
   nor earlycon output shows: `loglevel` filters the early console too. (B) was the only case
   with full kernel output, and only because its bootargs were typed by hand without
   `loglevel=1`. Nothing in the kernel touches `/cpus/idle-states` before
   `parse_early_param()` (setup.c: `setup_machine_fdt` 292 → `parse_early_param` 299 →
   `psci_dt_init` 351 → `smp_init_cpus` 358), so a pre-console hang caused by the DTB is not
   plausible; U-Boot's part up to the jump is identical in (A) and (B) (no `CONFIG_GICV2`
   SGI kick, no `ARMV8_PSCI`, no idle-state handling in U-Boot).
2. **What then kills it is the first real `cpu-sleep` entry**: (A) is the only combination
   where Linux has idle states *and* the firmware accepts CPU_SUSPEND. In (C) the old bl31
   returns NOT_SUPPORTED and cpuidle just counts `rejected`; in (B) there is no state to
   enter. Once `cpuidle-psci` registers (device_initcall, right after SMP bring-up, while the
   system is mostly idle), every core soon requests `cpu-sleep`, TF-A disables its GIC CPU
   interface, sets CORE_CLOSE and executes WFI. If the CPUIDLE block does **not** power the
   core off and back on autonomously (or the woken core fails in BL31), the core never
   returns: with the CPU interface disabled, the WFI cannot be ended by an interrupt either.
   One by one all four cores vanish → exactly "no console, no network, for minutes".
   This also explains why CPU_OFF "works" today without proving anything: a hot-unplugged
   core that merely sits in WFI with its GIC interface off is indistinguishable from a
   powered-down one.
3. **Why there was no firmware message either**: Allwinner's BL31 registers its console with
   the BOOT|CRASH scope only; `bl31_main()` switches to the RUNTIME scope before handing over,
   so WARN/ERROR/INFO from PSCI handlers — including a C-level `panic()` such as
   `Unexpected affinity info state` if a woken core finds AFF_STATE_OFF — are never printed.
   (Only an EL3 exception crash dump would have been visible.) The suspend diagnostics in
   §5.3 were therefore unobservable as built; fixed by the debug patch below.

Open hardware question this leaves (not answerable from documentation available to me; the
linux-sunxi CPUIDLE wiki page blocks fetches and the User Manual defers to the unpublished
"H616_CPU_AP_Note"): whether the CPUIDLE block (a) actually gates the core on
CORE_CLOSE+WFI with only the two CPUIDLE_EN key writes (crust on H6 does the power switching
itself and only reads CPUIDLE_PEND), (b) powers it up again on a pending GIC interrupt
without software touching CPUIDLE_WAKE / the power-switch registers, and (c) which signal it
samples (GIC-400 `nIRQOUT` vs the CPU-interface `nIRQ`, i.e. whether disabling the CPU
interface first is allowed — Allwinner's R40 kernel driver did disable it). The vendor H616
DT's very short cpu-sleep latencies (46/59 µs) are also compatible with a lighter vendor
implementation than a full core power-down, so the vendor precedent is weaker than assumed.

### New artifacts (`kernel-check/work-pm/out/`, `SHA256SUMS`)
* `u-boot-sunxi-with-spl-dbg.bin` / `bl31-dbg.bin` (10be530c… / 2caa3994…): same as before
  plus `patch/atf/atf-sunxi64/0003-debug-allwinner-runtime-console-and-cpu-sleep-tracing.patch`
  (wt-pm-integration 2449f22, bring-up only): BL31 console gets the RUNTIME scope in DEBUG
  builds, and the first cpu-sleep entry/wakeup of every core is reported:
  `INFO: PSCI: core N enters cpu-sleep (clamp XX, idle stat XXXXXXXX)` /
  `INFO: PSCI: core N woke from cpu-sleep` (or `... from system suspend`), plus the
  §5.3 system-suspend lines now actually reach the serial port.
* `sun50i-h616-orangepi-zero2-idletest-cpu3.dtb` (c13fd740…): the new DTB with
  `cpu-idle-states` removed from cpu@0..2 — only CPU3 may enter cpu-sleep, so a core that
  never comes back costs one core, not the system.
* `harness/h616-pm-regs.py`: dumps C0_CPU_STATUS, resets, power switches, CPUIDLE_EN/
  CORE_CLOSE/PEND/WAKE/STAT, delays via /dev/mem (root; `CONFIG_STRICT_DEVMEM` is off).

### Experiments requested (in this order; each is safe to abort by power cycle + rollback)
E1 — confirm the silent-boot reading (new dbg bootloader + new DTB, boot.scr path):
`verbosity=7` and `extraargs=ignore_loglevel earlycon=uart8250,mmio32,0x05000000 keep_bootcon`
in armbianEnv.txt. Expect the normal kernel log up to around
`cpuidle: using governor menu` / `psci_idle` registration (and SMP bring-up), then the TF-A
lines `PSCI: core N enters cpu-sleep (clamp 00, idle stat ...)`; whether any
`PSCI: core N woke from cpu-sleep` follows is the decisive observation. If a core woke and
BL31 panicked, the runtime console now shows `PANIC at PC …`/`Unexpected affinity info state`.
Record the last 30 lines.

E2 — does the CPUIDLE block power a core off at all? (new dbg bootloader + ORIGINAL DTB,
boots normally, no idle states): as root
`python3 h616-pm-regs.py` → `echo 0 > /sys/devices/system/cpu/cpu3/online` → `python3
h616-pm-regs.py` → `echo 1 > …/cpu3/online` → dump again. Interesting fields after the
offline: `C0_CPU3_PWR_SWITCH` 0xff = hardware really removed power (CPUIDLE block works for
power-off), 0x00 with `C0_CPU_STATUS` bit 19 set = core merely parked in WFI (block inert →
my CPU_SUSPEND can never work as written); `CPUIDLE_STAT`/`CORE_CLOSE_FLAG` values tell
whether the request was consumed; `PWR_SW_DELAY`/`CONFIG_DELAY` defaults.

E3 — does a powered-down core come back? (new dbg bootloader + `…-idletest-cpu3.dtb`,
`verbosity=7`): after boot, `grep . /sys/devices/system/cpu/cpu3/cpuidle/state1/{usage,time,rejected}`
twice 10 s apart, `taskset -c 3 true; echo rc=$?`, `dmesg | grep -i 'rcu\|stall\|cpu3'`, serial
for `core 3 enters cpu-sleep` / `core 3 woke`. Outcomes: usage grows and `woke` printed →
mechanism works, (A) must have died from something else (then collect E1's tail);
`enters` but never `woke`, taskset hangs/RCU stall on CPU3 → hardware does not auto-wake (or
wakes into a BL31 failure that the runtime console will now show).
Variant E3b if E3 shows no wake: same DTB, but first `echo 0 > …/cpu3/online; echo 1 > …`
(so CPUIDLE_EN has been written once by CPU_OFF before any idle) — tells whether the enable
sequence must precede the first CORE_CLOSE by more than a few instructions.

E4 — SYSTEM_SUSPEND independently of cpuidle (new dbg bootloader + ORIGINAL DTB):
`echo deep > /sys/power/mem_sleep; rtcwake -m mem -s 10` with the serial console open.
Expect ~10 s silence then `INFO: PSCI: system resumed, DRAM was in self-refresh` (or one of
the WARN lines of §5.3) and `PM: suspend exit`. If the board never returns: power cycle; the
SRAM standby path is then the suspect (report whether the `PSCI: core 1..3 killed`/`Disabling
non-boot CPUs` lines appeared, i.e. how far Linux got).

### What I will do with the results
* E2 power switch 0xff + E3 wake → keep the design, tune latencies, drop the debug patch.
* E2 0xff but E3 no wake → the block needs explicit wake programming: next iteration keeps
  the GIC CPU interface enabled during cpu-sleep (so `nIRQ` can serve as the wake request)
  and/or programs `CPUIDLE_WAKE`/IRQ-mask registers; E1/E3 register dumps (`idle stat`)
  guide that.
* E2 0x00 (no power-off) → the CPUIDLE block is inert with this enable sequence; fall back to
  a software core power-down: `cpu-sleep` becomes a retention state (WFI in EL3 with the
  cluster clock untouched) until the block is understood, and CPU_OFF's "works" status gets
  a note upstream.
* E4 result decides whether patch 2 ships as is.

## 8. Board round 2 (E1-E4) — findings, fixes, next experiments

### What E1-E4 established
* **E2**: the CPUIDLE block does gate a core: after `CPU_OFF` of CPU3, `C0_CPU3_PWR_SWITCH`
  = 0xff, `PWROFF_GATING` bit 3 set, `DBG_REG0` bit 3 cleared, `CPUIDLE_EN` = 0xaa160001
  (sticky), `CORE_CLOSE` reads back 0 (consumed), `CPUIDLE_STAT` 0x07 → 0x8d → 0x87 after
  `CPU_ON`. Default `PWR_SW_DELAY` = 8, `CONFIG_DELAY` = 6, `CPUIDLE_WAKE` = 0.
* **E1** (loglevel theory confirmed): cores enter cpu-sleep (`core 3 enters`, `core 1 enters
  (clamp 0, idle stat 89)`), are gated, and **never come back** — no `woke`, no BL31 panic;
  21 s later RCU stalls on CPUs 1 and 3. So the block powers a core off on CORE_CLOSE+WFI but
  does **not** power it up again on a pending interrupt with the sequence used (GIC CPU
  interface disabled, `CPUIDLE_WAKE` untouched). `CPUIDLE_WAKE` (0x10c, 0 by default) is the
  obvious candidate for the missing "allow/perform wake-up" step; the alternative is that the
  block samples the CPU interface's nIRQ (so the interface must stay enabled). Both are now
  selectable at runtime (below) instead of guessing with one rebuild per hypothesis.
* **E3** was void: `cpuidle-psci` registers nothing unless CPU0 has idle states (probe
  unwinds with -ENODEV) — the single-core DTB approach cannot work; the runtime knob replaces it.
* **E4**: `PM: suspend entry (deep)` … `Suspending console(s)`, then no BL31 output and a
  cold `U-Boot SPL` 13.6 s later. Explanation that fits the code: the debug patch enabled the
  RUNTIME console scope, and `sunxi_pwr_domain_suspend_finish()` prints `INFO` lines on
  resume — but Linux's 8250_dw driver gates the UART0 clock when it suspends the console
  (`pm_runtime_put_sync_suspend` → `clk_disable_unprepare`), so `console_16550_putc` spins
  forever on LSR.THRE in EL3; systemd's `RuntimeWatchdogSec=15` (sunxi-wdt) then reset the
  board. A hang inside the SRAM routine is the other candidate; the two are indistinguishable
  without the console and that is exactly what the trace page below settles. Important
  corollary: BL31 must never print from a resume path (the stock BOOT-only console scope
  made that harmless before; the debug patch broke it).
* **Ethernet RX dead in 3/5 boots and `=> reset` hanging** (debug bootloader only): nothing in
  the three BL31 patches runs at boot time except (a) adding the idle-states nodes to
  **U-Boot's own** DTB (`fdt_add_cpu_idle_states`, phandles max+1), (b) advertising
  CPU_SUSPEND/SYSTEM_SUSPEND in PSCI_FEATURES and (c) — debug patch v1 only — the RUNTIME
  console scope, which makes BL31 print `WARN("Unimplemented Standard Service Call …")` on
  UART0 for every SMCCC probe Linux makes at boot (TRNG, vendor hyp, …) with interrupts
  masked in EL3, interleaved with Linux's own console traffic. None of them touches the CCU,
  R_PRCM, SPC, PMIC rails, EMAC/PHY, GIC configuration or the MBUS at boot (MAER0..2 are only
  saved/cleared/restored inside the SRAM standby routine). U-Boot's `reset` on the H616 does
  not use PSCI at all (`reset_cpu()` writes the timer-block watchdog directly,
  `arch/arm/mach-sunxi/board.c`), so BL31 cannot have hung it; "no output after `=> reset`"
  (not even U-Boot's own `resetting ...`) points at the UART/console path. U-Boot proper is
  the same build in both images (FIT payload sizes identical: 895209 vs 899305 bytes =
  exactly the 4096-byte bl31 growth). The one BL31 behaviour that is new *and* intermittent in
  effect is (c); it is removed in debug v2. If the RX-dead boots persist with v2 they are
  independent of this work; please then capture `cat /proc/interrupts | grep -i eth`,
  `ethtool -S end0 | grep -i rx`, `dmesg | grep -i 'emac\|rgmii\|phy'` on a bad boot and count
  bad boots for known-good vs new over ≥5 boots each.

### Fixes / changes in this round (wt-pm-integration f16d24d)
* Debug patch v1 (runtime console) **dropped**. Debug patch v2
  `patch/atf/atf-sunxi64/0003-debug-allwinner-pm-trace-page-and-experiment-knob.patch`:
  * **PM trace page** at `0x4003f000` (last page of the BL31 reservation, mapped non-cacheable,
    one lock-free 62-record ring per core, records `{cntpct, event|core, d0, d1}`; survives
    warm/watchdog resets — the boot generation counts them). Events: BOOT, CPU_ON, CPU_OFF
    (CPUIDLE_STAT/PEND), SLEEP_ENTER (mode | STAT<<8, PEND), SLEEP_WAKE (STAT, PEND),
    SLEEP_WFI_RET, STANDBY, SYS_SUSPEND (CPUX_AXI_CFG, PLL_CPUX), SYS_JUMP (knob, entry),
    SYS_RESUME (standby result, PLL locked), SYSTEM_RESET, SYSTEM_OFF. Read with
    `harness/h616-pm-regs.py --trace` (Linux) or `md.l 0x4003f000 0x400` (U-Boot).
  * **Experiment knob** at `0x4003f008` (`h616-pm-regs.py --knob N`; BL31 resets it to 0 at
    every boot, so a bad setting can never survive a watchdog reset). Bits 2:0 = cpu-sleep
    mode: **0** WFI in EL3 then restart through `bl31_warm_entrypoint` (no power-down, always
    safe — this is now the boot default, so the full-DTB image boots and runs); **1**
    CORE_CLOSE + WFI, GIC CPU interface off (the original design, known not to wake); **2**
    CORE_CLOSE + WFI, CPU interface left on; **3** = 1 + this core's `CPUIDLE_WAKE` bit set
    before closing; **4** = 2 + `CPUIDLE_WAKE` bit. In modes 0/2/4 the WFI is executed by the
    platform hook and a returning WFI restarts the core through the warm boot path instead of
    the generic panic. Bit 4: suspend skips the DRAM self-refresh; bit 5: suspend keeps the
    CPU clock/PLL; bit 6: suspend runs the standby routine from DRAM (no SRAM, no
    self-refresh) — for bisecting E4.
  * `CPU_OFF` clears the core's `CPUIDLE_WAKE` bit (an offline core must not be woken).
* Patches 1 and 2 unchanged (the final wake sequence goes into patch 1 once known).
* Artifacts: `kernel-check/work-pm/out/u-boot-sunxi-with-spl-dbg.bin` / `bl31-dbg.bin`
  (7f69ae18… / 77823ee3…); DTB `sun50i-h616-orangepi-zero2.dtb` 3fc9fadc… unchanged
  (use the full one; the cpu3-only DTB is useless, see E3).

### Experiments, round 3 (dbg v2 bootloader; new DTB unless stated; `verbosity=7`,
`extraargs=ignore_loglevel no_console_suspend`; disable the systemd watchdog for the suspend
tests: `mkdir -p /etc/systemd/system.conf.d && printf '[Manager]\nRuntimeWatchdogSec=0\n' >
/etc/systemd/system.conf.d/nowdt.conf && systemctl daemon-reexec`)

**F0 — baseline, boot default (mode 0)**: boot must complete normally with
`current_driver = psci_idle`, `state1/usage` increasing on all CPUs (each entry is WFI in EL3
+ a warm-boot restart; expect ~tens of µs more exit latency than a plain WFI, otherwise
harmless). Serial: `INFO: PM trace page at 0x4003f000, boot generation 0`. Then
`h616-pm-regs.py --trace` must show BOOT, the CPU_ON of cores 1-3 and alternating
SLEEP_ENTER/SLEEP_WAKE pairs per core (d0 low byte = 0). This validates the warm-restart path
that the suspend design depends on. Also repeat the Ethernet/`reset` checks here (5 boots).

**F1 — wake experiments** (each: set knob, wait 20 s, dump; if the system freezes, let the
watchdog/power-cycle reset it, then read the trace at the U-Boot prompt with
`md.l 0x4003f000 0x400` or from the next Linux boot with `--trace`, the page survives a
warm reset):
`h616-pm-regs.py --knob 3` → cores close with their CPUIDLE_WAKE bit set, CPU interface off.
Success = SLEEP_WAKE records with the same count as SLEEP_ENTER and the system stays alive.
If dead: `--knob 4` (WAKE bit + CPU interface on) on the next boot, then `--knob 2`
(CPU interface on, no WAKE bit). Please report for each mode: alive or not, the last ~10
trace records (SLEEP_ENTER d0 gives STAT, d1 PEND at entry; SLEEP_WFI_RET means the core was
not gated and restarted itself), and `h616-pm-regs.py` register dump while cores are asleep
(`CPUIDLE_PEND`/`STAT`/`WAKE`, power switches) if the system is still alive.
Keep `--knob 1` as the control (expected: dead, as in E1).

**F2 — suspend bisect** (original or new DTB, knob mode bits = 0, watchdog off,
`no_console_suspend`): run `echo deep > /sys/power/mem_sleep; rtcwake -m mem -s 10` with
`--knob 0x40` (standby routine in DRAM, no self-refresh, CPU clock lowered), then
`--knob 0x10` (SRAM, no self-refresh), then `--knob 0x00` (full: SRAM + self-refresh). After
each resume: `--trace` (expect SYS_SUSPEND, SYS_JUMP, SYS_RESUME with d0 = 0x80000000 for a
clean self-refresh cycle, 0x80000001/2 for entry/exit timeouts, d1 = 1 PLL locked) and `date`.
If a step never resumes: power cycle and dump the surviving trace — the last record tells
whether the failure is the SRAM jump (SYS_JUMP present, no SYS_RESUME) or the warm-boot path
(SYS_RESUME present, no Linux `PM: suspend exit`).

## 9. Board round 3 (F0-F2) — findings and state (updated as work progresses)

### Findings
* **F0 PASS** (mode 0): psci_idle active, trace works, Ethernet RX fine on 4/4 boots → the
  RX-dead boots were caused by debug v1's runtime console (removed).
* **F1**: `CPUIDLE_WAKE` bit n **is the wake enable**. Decoded trace of the mode-4 run
  (`pm-trace-knob4-uboot.txt`): cores 1-3 enter cpu-sleep (d0 = `…04`), are gated, and come
  back **through `bl31_warm_entrypoint`** (SLEEP_WAKE records without SLEEP_WFI_RET, PEND bit
  of the core set, 0.4-75 ms later) — repeatedly. **Core 0** entered mode 4 at t=143714 ms and
  1.35 s later a BOOT record from core 0 appears (gen 2): core 0 alone restarts in the BROM
  (→ SPL under the live kernel → crash). Root cause: the BROM boots core 0 in AArch32; the SPL
  switches it to AArch64 with the RMR instruction, which does **not** set core 0's
  `AA64nAA32` configuration bit in `CPUCFG C0_CTRL_REG0` (TF-A's CPU_ON sets it for cores 1-3
  only, which is why they wake correctly). When the CPUIDLE block powers core 0 up it samples
  the pin → AArch32 → reset vector 0 = BROM. Fix: program AArch64 for **all** cores at BL31
  init (crust does the same in `css_init`). Mode 2 (CPU interface on, no WAKE bit) does not
  wake; mode 3 (WAKE, CPU interface off) was killed by the core-0 issue before it could be
  judged. `CPUIDLE_STAT` decodes as `(gated cores << 4) | (cores in WFI)`.
* **F2 PASS** in all three modes (0x40 DRAM-only, 0x10 SRAM/no-SR, 0 full). Full mode resumes
  ~4.6 s late: the two self-refresh status polls are count-based (1e6 MMIO reads at 24 MHz ≈
  2.3 s each) and evidently both ran to their limit, i.e. `STATR.operating_mode` never read
  3 and/or 1 — the controller did not enter (or did not report) self-refresh. The DRAM
  survived, so nothing was corrupted. Next build: time-based polls (CNTPCT, 20 ms) and the
  STATR values recorded in the result word so the trace shows what the controller reports.

### State / next steps (for whoever continues)
* Code: TF-A tree `kernel-check/work-pm/atf`, branches `feat/h616-native-suspend` (patches 1+2)
  and `debug/h616-pm-trace` (debug on top); Armbian `wt-pm` (`wt-pm-integration`, topic
  branches `feat/atf-h616-psci-cpu-suspend`, `feat/atf-h616-system-suspend`,
  `feat/sunxi-h616-cpuidle-dt`). Build: `ARMBIAN=…/wt-pm WORK=…/kernel-check/work-pm/uboot
  kernel-check/build-uboot.sh`; artifacts copied to `kernel-check/work-pm/out` + SHA256SUMS.
* Round-4 work items: (1) AA64 for all cores at init + WAKE bit in the cpu-sleep path → patch
  1 default; (2) time-based SR polls + STATR in result → patch 2; (3) trace: separate
  non-wrapping system ring, freeze after a warm reset until re-armed; (4) tool: no msync,
  `--arm`; (5) experiments: mode 1 (= patch-1 sequence) and mode 2 (CPU interface on) with
  the core-0 fix, full suspend with trace; (6) then drop the debug patch, tune latencies,
  measure power, submit upstream.

### Round 4 changes (wt-pm-integration 7309d3f, on stonking 76237ba; TF-A tree branches
`feat/h616-native-suspend` 20aab9b + 82ffe5d, `debug/h616-pm-trace` 0b820e1)
* **Patch 1** (`0001-…`, now the intended final sequence): `sunxi_cpu_set_aarch64()` and all
  cores programmed for AArch64 in `plat_setup_psci_ops()` (the core-0 → BROM fix);
  `pwr_domain_suspend` arms `CPUIDLE_WAKE` bit n, disables the GIC CPU interface, CORE_CLOSE
  (= old experiment mode 3); `pwr_domain_suspend_finish` and `pwr_domain_off` clear the WAKE
  bit; `SUNXI_CPUIDLE_{PEND,WAKE,STAT}_REG` defined in `sunxi_cpucfg_ncat.h`.
* **Patch 2** (`0002-…`): self-refresh polls are now bounded by CNTPCT (20 ms each instead of
  1e6 MMIO reads ≈ 2.3 s each — the 4.6 s late resume), and the result word carries the last
  `STATR` value seen by a timed-out poll (bits 15:8 entry, 23:16 exit), so the trace's
  SYS_RESUME d0 tells what the controller reports.
* **Debug patch** (`0003-…`): trace page re-laid out — system ring (BOOT, SYS_*, SYSTEM_*,
  58 records, never overwritten by idle events) at 0x40, per-core rings (46 records) at
  0x400 + core*0x300; per-core rings **freeze** after a warm reset (header word 0x0c) until
  `h616-pm-regs.py --arm` (or any `--knob`) clears the flag — a post-mortem survives the next
  boot. New mode map (bits 2:0): **0** WFI only (boot default), **1** the patch-1 sequence
  (WAKE + CPU interface off), **2** WAKE + CPU interface on, **3** = 1 with core 0 never gated,
  **4** = 2 with core 0 never gated. Modes 0 and 2 run the WFI in the platform hook with a
  warm restart on return. Bits 4-6 for suspend unchanged.
* Tool: no `msync` (EINVAL on /dev/mem), `--arm`, new layout decoding. Systemd watchdog
  override file must sort after `watchdog.conf`, e.g. `zz-nowdt.conf`.
* Artifacts (`kernel-check/work-pm/out/`, SHA256SUMS): `u-boot-sunxi-with-spl-dbg.bin`
  ed27bfae…, `bl31-dbg.bin` 97dab76a…, DTB 3fc9fadc… (unchanged), `h616-pm-regs.py`.

### Experiments, round 4 (dbg v3 + full DTB, verbosity=7, ignore_loglevel no_console_suspend)
**G0** boot (mode 0): as F0; `--trace` must show BOOT in the system ring and SLEEP_* per core.
**G1** `--knob 1` (= patch-1 sequence, all cores incl. core 0): the decisive test. Alive after
60 s, SLEEP_WAKE count == SLEEP_ENTER count per core, no SLEEP_WFI_RET, no BOOT/gen bump →
patch 1 is done. If core 0 still restarts in the BROM (SPL banner, gen+1): read
`md.l 0x4003f000 0x400` at the prompt or `--trace` after the reboot (rings frozen), then
`--knob 3` (core 0 excluded) to keep going, and report the `CPUCFG C0_CTRL_REG0`
(0x09010010) value from `h616-pm-regs.py` output… (add: `python3 -c` read of 0x09010010 —
bits 27:24 must be 0xf after boot with this bl31).
**G2** `--knob 2` (CPU interface on) for comparison: alive or not, any SLEEP_WFI_RET.
**G3** full suspend (`rtcwake -m mem -s 10`, knob 0, watchdog off): resume must now be on time
(≤ ~100 ms late); `--trace` system ring: SYS_SUSPEND, SYS_JUMP (d0 0, d1 0x20000), SYS_RESUME
d0 — 0x80000000 = clean self-refresh cycle; 0x8000xx01 = entry timed out with STATR xx;
0x80xx0002 = exit timed out. Report d0 verbatim; it decides how patch 2's self-refresh
request must be adapted (e.g. `selfref_sw` only, or `STATR` field layout) or whether the
DRAM was in self-refresh all along (then measure power vs s2idle on the Meross plug).
**G4** with G1 passing: 30 min idle soak + `cyclictest -t4 -p80 -i1000 -l600000`, then
`state1/{usage,time,above,below}` to tune the DT/TF-A latencies; power: idle before/after.

### What makes the patches final
* Patch 1: G1 passes (all cores wake via BL31), G4 soak clean → drop the debug knob, keep the
  sequence; tune `entry/exit/min-residency` from `above/below`; mention CPU_OFF only parking
  cores before this change in the commit message. Upstream: rebase on master (44621 renames
  `sunxi_native_pm.c`), push to review.trustedfirmware.org.
* Patch 2: G3 shows 0x80000000 (or the adapted request does) and resume on time; then decide
  the follow-ups (VDD_CPU lowering, DRAM clock/PLL gating) by power measurement.
* DT patch: unchanged unless latencies move.

## 10. Round 5 (analysis of round-4 board results G0-G3, fixes, next experiments)

Input: `pm-round4-results.md`, `pm-trace-g1.txt`, `pm-trace-g2.txt`. All work was code/analysis
only (no board access).

### 10.1 Root causes
* **G1 lost wakeup = a read-modify-write race on the shared `CPUIDLE_WAKE` register.**
  Patch 1 (round 4) did `mmio_setbits_32(CPUIDLE_WAKE, BIT(core))` in `pwr_domain_suspend`
  and `mmio_clrbits_32(...)` in `pwr_domain_suspend_finish`. CPU_SUSPEND at the core level
  (end_pwrlvl 0) takes **no PSCI lock** (`psci_acquire_pwr_domain_locks` starts at level 1),
  so cores entering/leaving idle at the same time interleave their RMWs and drop each
  other's bits. Evidence in `pm-trace-g1.txt`: core 1's last record is
  `159946.935 ms core1 SLEEP_ENTER d0=00004401 d1=00000000` and core 0 has
  `159946.935 ms core0 SLEEP_ENTER d0=00004401` with the *same timestamp* (same µs) - both
  read WAKE (= core 2's bit) and wrote it back with only their own bit, core 0's write
  landing last. From then on every core-0 record shows `CPUIDLE_PEND` bit 1 set
  (`d1=...2/3/6/e`) and `CPUIDLE_STAT` high nibble containing core 1 (`0x6e`, `0xee`,
  `0xaa`): core 1 is gated with an interrupt pending and is never powered up, i.e. its
  WAKE bit was missing. Other near-simultaneous entries a few µs apart (e.g. 159808.923 /
  .926 ms) survived because their RMW windows (~2 APB accesses) did not overlap. The
  "Possible timer handling issue on cpu=0" is a consequence: the tick-broadcast device is the
  sun4i timer (`allwinner,sun50i-h616-timer`, rating 350, `CLOCK_EVT_FEAT_DYNIRQ`, so its
  SPI follows the CPU with the earliest expiry). When core 1 was lost the broadcast IRQ was
  targeted at it (the stuck PEND bit 1), so no CPU got broadcast timer events any more and
  every CPU in `local-timer-stop` idle stopped seeing its timers. Kernel config/DT checked:
  `CONFIG_GENERIC_CLOCKEVENTS_BROADCAST=y`, `CONFIG_SUN4I_TIMER=y`, timer@3009000 present,
  arm64 also registers the hrtimer fallback (lower rating) - the broadcast setup is correct.
* **G2 hang = GIC CPU interface left enabled while gating.** With the interface on, an
  interrupt reaches the core's nIRQ while it sits in WFI with CORE_CLOSE set; the WFI can
  then end while the CPUIDLE block is part-way through the power-down. G2's last record is
  `core1 SLEEP_ENTER d0=00004002 d1=0000000d` followed by `SLEEP_WFI_RET d0=40 d1=0f`
  (core 1 left WFI, STAT shows it neither in WFI nor gated) and nothing after it - the core
  died in the warm-restart path, half powered down, with its WAKE bit just cleared by its
  own racy `clrbits`. The other cores then spin on IPIs/CSD to the lost core, a silent hang
  shorter than the 21 s RCU stall timeout, so only the 15 s watchdog fired. Mode 2 is
  inherently racy; it is removed from the knob (2/4 now behave as 0). Note G2 also showed
  that the block wakes cores with the interface on (core 3: 23 ENTER/23 WAKE, 0 WFI_RET), so
  PEND is not only GIC-400 nIRQOUT; the interface must be off because nothing but the block
  may end the WFI, not because the block would not see the interrupt.
* Checked and **not** a cause: `sunxi_pwr_domain_suspend_finish` re-runs
  `gicv2_pcpu_distif_init()` (clears the core's PPI enables, `ICENABLER0 = ~0`), but Linux's
  GICv2 CPU_PM notifier (`gic_cpu_save/restore`, CONFIG_CPU_PM=y, called by cpuidle-psci
  for non-retention states) restores the PPI enables/config after every idle exit. Left as
  is. Concurrent `CORE_CLOSE` writes: in the G1 collision both cores were gated, so the
  register behaves per-bit/latched; no change.
* **[WRONG, see 10.6] G3 STATR 0xaa = self-refresh request ignored.** 0xaa & 3 = 2 = operating mode
  *power-down*: the controller just idled into automatic power-down after the masters were
  disabled; the `PWRCTL` write (selfref_en|selfref_sw) had no effect. On this uMCTL2 U-Boot
  (`dram_sun50i_h616.c` lines 1039-1045) changes `PWRCTL.selfref_sw` only between
  `SWCTL = 0` and `SWCTL = 1` + `SWSTAT.sw_done_ack`, then polls `STATR & 3` - i.e.
  selfref_sw is treated as quasi-dynamic. Patch 2 now does the same handshake on entry and
  exit, polls the low 2 bits, and on exit accepts any mode other than self-refresh (the idle
  controller may go straight back to power-down, which made the old "== normal" exit poll
  time out as well). crust's H6 sequence (MAER = 0, `PWRCTL.selfref_en`, poll STATR == 3)
  was fetched for comparison; it has no handshake but runs on the AR100 against the H6
  controller. Not yet proven on the board: G3' below decides it, and records enough
  (`SYS_DRAM`, `SYS_SR`, `SYS_PWRCTL`) to choose the next step without another build.
  Also fixed: the 32-bit timeout argument was compared as 64 bits in the routine
  (`mov x3, x4` without zero-extension).
* **Trace oddity "system ring: 47625 events" = stale page of the previous layout.** The
  v2 BL31 kept one 62-record ring per core at `0x40 + core*0x3f0`; the v3 BL31 reused the same
  magic, so after the warm reboot into v3 it kept the page and read v2's core-0 ring
  (count 47625 < the 0x10000 sanity limit) as its system ring at 0x40. The SLEEP_* records at
  ~69430 ms are v2 core-0 records; each later boot only added one BOOT record (47626,
  47627). Neither a decoder nor a ring-logic bug in v3 itself. Fix: header word 0x10 = layout
  version (3); a page with another version is cleared at boot; the tool refuses to decode a
  foreign layout. The per-core rings in G1/G2 are valid (each had > 46 events since the v3
  boot, so every slot was rewritten).

### 10.2 Changes (local commits only)
TF-A tree `kernel-check/work-pm/atf` (old commits kept as tags `round4/feat-native-suspend`
= 82ffe5d, `round4/debug-pm-trace` = 0b820e1):
* `feat/h616-native-suspend`: **be4caff** patch 1 - `sunxi_cpuidle_wake_enable()`: WAKE bit
  set in the CPU_ON finisher and for the boot CPU in `sunxi_set_native_psci_ops()`, cleared
  in CPU_OFF (all under the PSCI system lock); the idle path no longer touches WAKE;
  `sunxi_cpuidle_enable()` (H616 `sunxi_power.c`) enables the block once at setup and is a
  no-op when already enabled (no interleaved unlock sequences); suspend_finish only
  re-initialises the GIC CPU interface. **6e711aa** patch 2 - SWCTL/SWSTAT handshake around
  `PWRCTL.selfref_sw`, `STATR & 3` polls, exit accepts "not self-refresh", report struct
  `{result, statr_entry, statr_exit, pwrctl}` (result bits 2/3 = SWSTAT ack timeout on
  entry/exit), WARN text carries the values, timeout zero-extended.
* `debug/h616-pm-trace`: **4b91179** - layout version, events `SYS_DRAM` (13: STATR, PWRCTL
  before suspend; a second one with knob 0x08: STATR, PWRCTL | SWSTAT<<16 after clearing
  powerdown_en), `SYS_SR` (14: STATR at self-refresh entry / after exit), `SYS_PWRCTL`
  (15: PWRCTL read back after the request, STATR at resume); explicit
  system-vs-core event classification; sleep events' d1 = `PEND | WAKE << 8`; knob modes
  0/1/3 only; knob bit 3 (0x08) = clear `PWRCTL.powerdown_en` before suspend (restored on
  resume).
Armbian `wt-pm` (patch files regenerated with `git format-patch 3fab517..debug/h616-pm-trace`):
`feat/atf-h616-psci-cpu-suspend` **53882e9**; `feat/atf-h616-system-suspend` merge cb30e10 of the former
+ **0d19624**; `wt-pm-integration` merge 49dc15f + **399b06a** + **bbab6a9**.
`harness/h616-pm-regs.py`: layout check, system ring printed separately in recording order,
per-core summary (ENTER/WAKE/WFI_RET counts, last record), DRAM controller registers and
`C0_CTRL_REG0` in the default dump, new event names.

### 10.3 Artifacts (`kernel-check/work-pm/out/`, SHA256SUMS; round-4 files in `out/round4/`)
`u-boot-sunxi-with-spl-dbg.bin` 484465df05d6…, `bl31-dbg.bin` a68b1581976a… (embedded at
0xc489c of the U-Boot image), `sun50i-h616-orangepi-zero2.dtb` 3fc9fadc62ba… (unchanged),
`h616-pm-regs.py` 9d66f1cf9ddd…. Built incrementally (`build-uboot.sh`, ARMBIAN=wt-pm,
WORK=work-pm/uboot; TF-A rebuilt because the patch set changed, U-Boot incremental + ccache).
Boot default is knob 0 (mode 0, WFI only + warm restart): the board always boots.

### 10.4 Next board experiments (in order)
Setup as round 4 (dbg bootloader written at 8 KiB like before, full DTB, `verbosity=7`,
`extraargs=ignore_loglevel no_console_suspend`); tool copied to the board as
`/root/h616-pm-regs.py`. Exact commands are in the round-5 report to the coordinator and
repeated here:

**H0 boot, mode 0** - `sha256sum` of the image = 484465df05d6…; after boot:
`python3 /root/h616-pm-regs.py --trace | head -4` -> `boot generation 0`, system ring 1
event (BOOT) - the stale page has been cleared (first boot of this BL31 after the round-4
one; generation 0 even on a warm reboot because the layout changed). `python3
/root/h616-pm-regs.py` -> `CPUIDLE_WAKE = 0000000f`, `CPUIDLE_EN = aa160001`,
`C0_CTRL_REG0` bits 27:24 = f; note the DRAM lines (expect STATR low bits 1 or 2, SWCTL 1,
SWSTAT 1). `grep -A3 'Broadcast device' /proc/timer_list` -> `sun4i_tick`. Pass: all of
that + psci_idle + Ethernet as in G0.

**H1 cpu-sleep (patch-1 sequence)** - `python3 /root/h616-pm-regs.py --knob 1`, then an
accelerator that produces many simultaneous idle entries (the race needed them):
`for c in 0 1 2 3; do taskset -c $c sh -c 'while :; do sleep 0.003; done' & done`, sample
every minute for 10 min (`python3 /root/h616-pm-regs.py | grep -E 'WAKE|PEND|STAT'`;
`grep . /sys/devices/system/cpu/cpu*/cpuidle/state1/usage`), then `kill %1 %2 %3 %4` and
another 20 min plain idle. Pass: alive 30 min, `dmesg | grep -iE 'rcu|stall|timer handling'`
empty, `CPUIDLE_WAKE` 0000000f in every sample, state1 usage grows on all CPUs, `--trace`:
ENTER == WAKE (± 1) per core, WFI_RET 0, every SLEEP_* d1 has bits 15:8 = 0f. If it dies:
read `--trace` on the next boot (rings frozen) - the lost core's last ENTER d1 bits 15:8 tell
whether its WAKE bit was set when it was gated (set -> a hardware wake-loss, next idea:
abort the power-down when the core's own PEND bit is set after the CPU interface is off;
not set -> some other writer).

**H2 suspend-to-RAM** (knob 0, systemd watchdog off via `zz-nowdt.conf`):
`dd if=/dev/urandom of=/dev/shm/t bs=1M count=200; sha256sum /dev/shm/t;
echo deep > /sys/power/mem_sleep; rtcwake -m mem -s 10; sha256sum /dev/shm/t;
python3 /root/h616-pm-regs.py --trace | sed -n '/system ring/,/core 0 ring/p'`. Expected
system ring: SYS_SUSPEND, `SYS_DRAM d0=STATR d1=PWRCTL`, `SYS_JUMP d0=0 d1=00020000`,
`SYS_RESUME d0=80000000 d1=1`, `SYS_SR d0=<STATR with low bits 3> d1=<low bits != 3>`,
`SYS_PWRCTL d0=<PWRCTL with bit 5 set>`. Pass: SYS_RESUME d0 = 80000000, hash unchanged,
resume on time; then `for i in $(seq 10); do rtcwake -m mem -s 5; sleep 3; done` and the hash
again. Reading the failure cases: d0 bit 2 (`8000xx05`) = no SWSTAT ack on entry (the
handshake is not how this controller wants it; SYS_PWRCTL d0 shows whether bit 5 latched);
d0 bit 0 with SYS_PWRCTL bit 5 set and STATR still `..aa` = request accepted but the
controller stays in power-down -> **H2b**: same commands with `--knob 0x08` (powerdown_en
cleared first; the extra SYS_DRAM record shows PWRCTL bit 1 = 0 and SWSTAT in bits 16+).
**H3** (after H1+H2 pass): G4 soak as planned (30 min idle + `cyclictest -t4 -p80 -i1000
-l600000`, `state1/{usage,time,above,below}`), Meross power: idle mode 0 vs knob 1, s2idle vs
deep.

### 10.5 State / to continue
* If H1 passes: patch 1 is final apart from latency tuning; drop the debug patch, rebuild a
  release bl31, then the DT/TF-A latencies from H3. If H2 passes: patch 2 is final; consider
  the follow-ups (DRAM clock gating/PGCR3 CKEN like crust, VDD_CPU lowering) by power data.
* The TF-A commit messages describe the round-5 behaviour (WAKE under lock, SWCTL handshake);
  re-check the patch-2 message wording once H2 has confirmed or refuted the handshake.
* Vendor sun50iw9 BL31/standby sources and the linux-sunxi CPUIDLE wiki were not consulted
  this round (not available locally); the conclusions above rest on the traces, TF-A's PSCI
  locking, U-Boot's DRAM init and crust's H6 driver.

### 10.6 Round-5 board results and the real G3 cause (2026-11-02)
* H1 (knob 1, 10 min sleep-loop load + 20 min idle): **PASS** - 32 min alive, no RCU/timer
  warnings, CPUIDLE_WAKE 0x0f in every sample, PEND 0; state1 usage flat under the 3 ms
  loop (residency 4 ms > 3 ms, expected), growing on all cores in idle (19k/6.3k/6.5k/6.8k).
  The WAKE-under-lock fix of patch 1 holds.
* H2/H2b (deep, knob 0 / 0x08): functionally PASS (rc 0, on time, 200 MB tmpfs hash OK,
  10x loop OK, WiFi/BT/end0 fine), but SYS_DRAM/SYS_SR read 0xaa and SYS_RESUME 8000aa01.
* **Real cause (found by the coordinator): wrong DRAM block addresses.** Patch 2 used
  0x04810000 (MC_COM) / 0x04820000 (controller) - the *A133* bases from U-Boot's
  `cpu_sun50i_h6.h` (`#elif CONFIG_MACH_SUN50I_A133`); the H616 has COM 0x047fa000, CTL0
  0x047fb000, PHY 0x04800000. All MAER/PWRCTL/STAT/SWCTL accesses hit an unused range
  (reads 0xaa / 0 / 7): the masters were never disabled and no self-refresh was ever
  requested, so suspend so far was "CPU0 in WFI at 24 MHz with DRAM active". The 10.1
  explanation (ignored plain write, quasi-dynamic selfref_sw) was wrong; the handshake is
  kept only because U-Boot's H616 init uses it. Real controller on the board: MSTR
  c1040401 (DDR3), STAT 1, PWRCTL 0, PWRTMG 00402010, SWCTL 1, SWSTAT 1, DFIMISC 0.
  Offsets re-checked against U-Boot's H616 `struct sunxi_mctl_ctl_reg` (statr 0x004, pwrctl
  0x030, swctl 0x320, swstat 0x324) and `struct sunxi_mctl_com_reg` (maer0-2 0x020-0x028).
  Self-refresh needs only the controller + COM (MAER); the PHY is not touched (crust's H6
  PGCR3 CKEN gating is a power optimisation for later, and the H616 PHY is not the H6
  PUB layout). Since PWRCTL is 0, knob 0x08 (clear powerdown_en) is a no-op on this board.
* Fix: TF-A `feat/h616-native-suspend` **87decaa** (patch 2: bases 0x047fa000/0x047fb000,
  comment + message corrected), `debug/h616-pm-trace` **da069c2** (rebased); round-5 commits
  tagged `round5/feat-native-suspend`, `round5/debug-pm-trace` (TF-A) and `round5/*` (wt-pm).
  wt-pm: `feat/atf-h616-system-suspend` **0c9e2ff**, `wt-pm-integration` merge 2a113ef +
  **1575806**. `h616-pm-regs.py` uses the H616 bases (+ DFIMISC).
* Artifacts (`out/`, SHA256SUMS; round-5 copies in `out/round5/`): debug
  `u-boot-sunxi-with-spl-dbg.bin` 02d6d6638b72…, `bl31-dbg.bin` 760dcd09a259…; clean (patches
  1+2 only, no trace/knob; built from a temporary patch tree `kernel-check/tmp/r6-clean`)
  `u-boot-sunxi-with-spl.bin` b88ccfba76a6…, `bl31.bin` 35571f0d3f82…; tool b7f94a3358ba….
* Now the routine really disables the MBUS masters and puts DDR3 into self-refresh, so the
  next H2 is the first real self-refresh test (risk: a failed SR exit corrupts DRAM ->
  power-cycle; `--knob 0x10` skips self-refresh as a fallback). Expected: SYS_DRAM d0 = 1
  (STAT normal) d1 = 0 (PWRCTL), SYS_RESUME d0 = 80000000, SYS_SR d0 low bits 3 (likely 0x23,
  software self-refresh), d1 low bits 1, SYS_PWRCTL d0 = 0x20.

### 10.7 Round-6 board results (final validation)
* Debug build 02d6d6638b72: H2 `SYS_DRAM d0=1`, `SYS_RESUME 80000000/1`, `SYS_SR 0x223/1`
  (STAT 0x223: operating mode 3 = self-refresh, selfref_type 2 = software), `SYS_PWRCTL 0x20`,
  hash OK; 10x loop 0 self-refresh misses; H3 knob 1 cpuidle + 100x `rtcwake -m mem -s 5`
  with 3-9 s random gaps: 100/100 rc 0, dt 7 s, 0 misses, blob hash OK, no oops/stall; idle
  usage 28140/16188/15263/15264.
* Clean build b88ccfba76a6 (patches 1+2 only; now on the board's SD card): psci_idle active,
  usage grows on all cores, 5x deep rtcwake OK, clean dmesg.
* **Power not measured**: the Meross MSS110 plug has no metering, so the idle (cpu-sleep vs
  WFI) and suspend (deep vs s2idle) savings are unquantified. Needs a USB power meter or a
  metering plug before the latency/residency tuning and the follow-ups (DRAM clock gating,
  VDD_CPU lowering) can be judged.
* The clean build has no knob: its cpu-sleep sequence is exactly the validated mode 1
  (GIC CPU interface off, CORE_CLOSE + WFI, WAKE set while online), and suspend is the
  validated knob-0 path (SRAM + self-refresh).

## 11. Upstream (TF-A) submission draft

Source: TF-A tree `kernel-check/work-pm/atf`, branch `feat/h616-native-suspend` = be4caff +
87decaa on lts-v2.14.11 (3fab517); 14 files, +628/-11. Before pushing to
review.trustedfirmware.org: rebase onto `master` (the native PM code was reorganised there,
e.g. change 44621 renames `sunxi_native_pm.c`; resolve accordingly), install Gerrit's
commit-msg hook for Change-Id, keep `Signed-off-by` (DCO), decide on `Assisted-by` per TF-A's
contribution policy, run `make checkpatch` / `make PLAT=sun50i_h616 DEBUG=0 bl31` and a
build of the other Allwinner platforms (a64, h6, r329: both options default to 0 there, so
their BL31 must be unchanged). The Armbian patch files are `git format-patch` output of
these two commits and stay the reference for what was board-tested.

### Cover letter
```
Subject: [PATCH 0/2] allwinner: H616: CPU_SUSPEND and SYSTEM_SUSPEND without an SCP

The H616 (and H618) has no management processor, so TF-A's
Allwinner port falls back to the native PSCI ops, which only implement
CPU_ON/CPU_OFF: Linux gets no cpuidle state beyond WFI and no
suspend-to-RAM ("PSCI: Suspend is unavailable").

The SoC has what is needed to do both from EL3:

 1. The CPUIDLE block in R_CPUCFG (already used by the native CPU_OFF)
    gates a core that executes WFI with its CORE_CLOSE flag set and,
    with the core's CPUIDLE_WAKE bit set, powers it up again when the
    GIC has an interrupt pending for it. Patch 1 uses this for a
    core-level power-down state ("cpu-sleep"), behind the new build
    option SUNXI_NATIVE_CPU_SUSPEND.

 2. With the other cores off, the last core can run from SRAM A1 at
    24 MHz, put the DRAM into self-refresh and wait for any interrupt
    the OS left enabled. Patch 2 implements SYSTEM_SUSPEND this way,
    behind SUNXI_NATIVE_SYSTEM_SUSPEND.

Both options default to 0 and are enabled for sun50i_h616 only; other
Allwinner platforms are unchanged.

Findings from bring-up that shaped the code:
 - The boot CPU must have its AA64nAA32 bit set explicitly: the SPL
   enters AArch64 through RMR_EL3, so a core 0 power-cycled by the
   CPUIDLE block otherwise restarts in AArch32 in the BROM.
 - CPUIDLE_WAKE is shared by all cores and core-level CPU_SUSPEND takes
   no PSCI lock; read-modify-writes from the idle path lost other
   cores' bits (a core gated without its bit is never woken). The bit
   is now set while a core is online and only changed under the PSCI
   system lock (CPU_ON finisher, CPU_OFF).
 - The GIC CPU interface must be disabled before CORE_CLOSE + WFI, or
   an interrupt can end the WFI while the block is gating the core.
 - Nothing may be printed on the resume path with a RUNTIME console
   scope: the OS may have gated the UART clock. With the port's stock
   BOOT|CRASH scope the finisher's INFO/WARN lines are silent at runtime.

Tested on an Orange Pi Zero2 (H616, DDR3, AXP305) with Linux 7.3
cpuidle-psci and "deep" mem_sleep: 30 min mixed load/idle soak with
cpu-sleep on all four cores (no lost wakeups, no RCU stalls), 100/100
rtcwake suspend cycles with cpu-sleep active, DRAM self-refresh
confirmed by the controller status (STAT 0x223) on every cycle, a
200 MB tmpfs checksum intact across all cycles, Wi-Fi/BT/Ethernet
working after resume.

Not done yet: lowering VDD_CPU / gating DRAM clocks during suspend,
and latency/residency tuning from power measurements.

Arun Iyengar (2):
  feat(allwinner): offer CPU_SUSPEND natively on the H616
  feat(allwinner): implement SYSTEM_SUSPEND natively on the H616
```

### Commit messages
The two commit messages in the TF-A tree are the upstream messages (read them with
`git log 3fab517..feat/h616-native-suspend`). Summary:
* **feat(allwinner): offer CPU_SUSPEND natively on the H616** - SUNXI_NATIVE_CPU_SUSPEND;
  standby type = WFI in EL3, power-down type = GIC CPU interface off + CORE_CLOSE + WFI,
  finisher re-enables the interface; CPUIDLE_WAKE only under the PSCI system lock; block
  enabled once at setup; AArch64 for all cores at setup; "cpu-sleep" in the H616 idle-state
  table (power_state 0x00010003, local-timer-stop, 100/150/4000 µs) added to the DTB when the
  ops implement CPU_SUSPEND and the DTB has no idle-states node yet.
* **feat(allwinner): implement SYSTEM_SUSPEND natively on the H616** -
  SUNXI_NATIVE_SYSTEM_SUSPEND; CPU to OSC24M, PLL_CPUX off, routine copied to SRAM A1,
  MMU/caches off, MBUS masters off, PWRCTL.selfref_sw via the SWCTL/SWSTAT handshake,
  STAT polls bounded at 20 ms, WFI with IRQs routed to EL3 and masked, reverse on wake,
  resume through bl31_warm_entrypoint, finisher relocks PLL_CPUX and reports the
  self-refresh outcome; H616 DRAM blocks at 0x047fa000 (MC_COM) / 0x047fb000 (controller).
Worth adding to the commit messages at submission time: the test results above (one
line each).
