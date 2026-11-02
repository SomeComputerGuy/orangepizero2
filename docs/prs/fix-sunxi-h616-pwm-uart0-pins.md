# sunxi-6.18, sunxi-7.3: h616: PWM3/PWM4 on PH0/PH1 overlays release UART0

Branch: `pr/fix/sunxi-h616-pwm-uart0-pins` (9bbaf3564). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
`sun50i-h616-pwm3-ph0` and `sun50i-h616-pwm4-ph1` also disable `&uart0`; `sun50i-h616-fixup.scr-cmd` drops
`console=ttyS0,115200` for `pwm3-ph0`, `pwm4-ph1` and the legacy `pwm34` name; `pwm4-ph1` gets the compatible line
the other seven overlays have. Same change in sunxi-6.18 and sunxi-7.3.

## Why
PH0/PH1 are UART0 TX/RX on every H616/H618 board. UART0 claims them at probe, so the vendor PWM driver's
`pinctrl_select_state()` at enable time fails and PWM3/PWM4 never output. The fixup logic only matched an overlay
called `pwm34`, which Armbian never shipped (it arrived with the BigTreeTech CB1 overlay set), so it was dead code.
Orange Pi's BSP pairs its `ph-pwm34` overlay with `disable-uart0` for the same reason.

## Testing
fdtoverlay on the Orange Pi Zero2 DTB (sunxi-7.3 build): all eight `sun50i-h616-pwm*` overlays apply alone and in
stacks; a pin-claim checker over the merged DT shows PH0/PH1 claimed by both serial@5000000 and the PWM channel
before, and no double claims after. The fixup script ran in sandbox U-Boot v2026.10: bootargs lose
`console=ttyS0,115200` for pwm3-ph0/pwm4-ph1/pwm34 and stay unchanged otherwise. No board run (it would take the
debug console).

## Notes
On the Zero2 the PI variants (pwm1-pi11 ... pwm4-pi14) collide with the RGMII pins (PI0-PI16) and cannot be used;
that is hardware, not changed here (harness/research/pre-pr-cleanup.md §2).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
