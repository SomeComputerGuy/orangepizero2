# sunxi-7.3: backport 7.4 PM fixes (s2idle without suspend_ops->begin, DPM watchdog in all phases)

Branch: `pr/fix/sunxi-pm-s2idle-dpm-backports` (122232836). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
`4785d5faa935` "PM: suspend: Do not call suspend_ops->begin()/end() for s2idle" and `33392343c74e` "PM: sleep: Add DPM
watchdog to prepare/late/early/noirq/complete phases". `CONFIG_DPM_WATCHDOG` stays off (it panics on timeout).

## Why
On 7.3 every s2idle cycle on a PSCI platform runs `psci_system_suspend_begin()`, so drivers see
`pm_suspend_via_firmware()` true and take "firmware cuts power" paths. Not in linux-7.3.y as of 2026-11-01.

## Testing
Kernel-check 692/0, Image built, 0 new warnings. Board: s2idle and the 100-cycle suspend soak ran on kernels with
this patch (harness/research/impl-pm.md).

## Upstream status
In Linux 7.4; drop at the bump unless 7.3.y picks them up first.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
