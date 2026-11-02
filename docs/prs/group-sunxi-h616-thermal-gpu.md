# sunxi-7.3: h616 thermal trips with cooling maps; Orange Pi Zero2/Zero3 GPU DVFS and VDD-SYS floor

Branch: `pr/group/sunxi-h616-thermal-gpu` (e90d8d025). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What (4 commits)
1. `sun50i-h616.dtsi` CPU zone: passive 85 °C (cooling map to cpu0-3), hot 100 °C, critical 110 °C, replacing the
   vanilla 60/70 °C IPA trips that had no cooling maps.
2. Zero2/Zero3 Mali-G31 OPP table (306-600 MHz, 810-950 mV, from `dt_64/sun50i-h616-gpu-opp.dtsi`) and
   `CONFIG_DEVFREQ_GOV_SIMPLE_ONDEMAND=y`.
3. GPU as cooling device: `#cooling-cells` on `gpu`, passive 85 °C in `gpu-thermal`.
4. VDD-SYS (vdd-gpu-sys) floor 900 mV on Zero2/Zero3.

## Why
- With step_wise (Armbian's governor) the CPU never throttled; only the 110 °C shutdown protected the SoC.
- The GPU ran at a fixed 432 MHz without DVFS.
- The video engine shares vdd-gpu-sys: once devfreq dropped it to 810 mV at idle, 4K H.265/VP9 decoding
  corrupted CTBs intermittently. Board-measured: 6/13 runs bad at 810 mV, 0/6 at >= 890 mV.

## Testing (Orange Pi Zero2)
Trips 85/100/110 with cpufreq cooling devices PASS; sustained 1512 MHz under 4-core stress without throttling at
room temperature; panfrost devfreq 306-600 MHz; VE decode bit-exact with the floor (impl-cleanup.md §9,
impl-vdec.md). Kernel-check 694/0 on c2908d2.

## Upstream status
None of these are in mainline 7.4-rc1 (the Zero2 DTS still has no GPU OPPs; H616 dtsi still has 60/70 °C trips).
The shared-rail VE issue should also be reported upstream (the stock 7.4 VE node runs at 648 MHz on the same rail).

## Risk
Commit 1 changes every H616/H618 board's CPU trips; commits 2-4 only Zero2/Zero3 (shared
`sun50i-h616-orangepi-zero.dtsi`). Zero3 not tested here.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
