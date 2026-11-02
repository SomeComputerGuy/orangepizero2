# atf: sunxi64: H616: native PSCI CPU_SUSPEND and SYSTEM_SUSPEND; sunxi-7.3: cpu-sleep idle state

Branch: `pr/group/atf-h616-suspend` (de45e94a9). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What (3 commits)
- TF-A lts-v2.14.11 patch: CPU_SUSPEND for one core through the CPUIDLE block CPU_OFF already uses
  (`SUNXI_NATIVE_CPU_SUSPEND`, sun50i_h616 only).
- TF-A patch: SYSTEM_SUSPEND without an SCP: last CPU parks in SRAM A1 at 24 MHz, MBUS masters off, DRAM in software
  self-refresh, wake on any enabled GIC interrupt (`SUNXI_NATIVE_SYSTEM_SUSPEND`, sun50i_h616 only).
- Kernel DT: `cpu-sleep` idle state for the H616 (PSCI cpuidle).

## Why
TF-A reported "PSCI: Suspend is unavailable" on H616 (no SCP): no cpuidle beyond WFI and only s2idle.

## Testing (Orange Pi Zero2)
cpuidle 30-min soak PASS; suspend-to-RAM with DRAM self-refresh (STAT 0x223) 11/11 and then 100/100 rtcwake
cycles combined with cpuidle, 200 MB tmpfs hash intact; clean production BL31 verified (psci_idle active, 5x deep
rtcwake). A64/H5/H6 BL31 unchanged (options default off). Power saving not measured (no metering plug).

## Upstream status
Intended for review.trustedfirmware.org after rebasing onto TF-A master (harness/research/impl-pm.md §11).

## Notes
The DT idle state needs the patched BL31; without it psci cpuidle only logs and stays on WFI.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
