# Pre-PR cleanup of the Armbian fork (2026-11-02)

Tree: `armbian-build` (remote `fork` = SomeComputerGuy/build; nothing pushed to `origin` = armbian/build).
Integration input: `stonking-orangepizero2` 9eadcc0fe (incl. `fix/uwe5622-5ghz-ap` 709f8b104).
Upstream base: armbian/build `main` c2908d26e (22 commits after 27a7f72; none touch sunxi or our files).
No board work, no full image builds; validation by patch-apply checks, sandbox U-Boot, fdtoverlay.
Scripts and logs: `kernel-check/prprep/`. Branch list with heads: `kernel-check/prprep/pr-branches.txt`.

## 1. OpenSSL 4 and U-Boot host tools (fix/uboot-sunxi64-host-tools-openssl4, 4a8b8ef19)

- `lib/functions/compilation/uboot.sh`: new `uboot_host_openssl_engine_workaround()`, called before the
  `post_config_uboot_target` hook. If host OpenSSL ≥ 4: if the U-Boot Makefile appends `$(HOSTCFLAGS)` to
  `KBUILD_HOSTCFLAGS` and a test link with `-DOPENSSL_ENGINE_STUBS` + `ENGINE_by_id`/`-lcrypto` succeeds, pass
  `HOSTCFLAGS=-DOPENSSL_ENGINE_STUBS`; else, with `CONFIG_TOOLS_LIBCRYPTO=y`, disable `TOOLS_KWBIMAGE` +
  `TOOLS_LIBCRYPTO`; else warn. OpenSSL 3 hosts: no-op. `patch/u-boot/v2026.10-sunxi64/tools-rsa-sign-openssl4-engine-stubs.patch` removed.
- Why the framework and not per-dir patches: covers all 49 `patch/u-boot/*` dirs and vendor trees; the gcc-14 host
  workarounds already live there; `compile_uboot_target` is not in the U-Boot artifact hash (no cache churn);
  nothing to remove per dir when upstream fixes it.
- Verified (wt-prprep-ubtest, v2026.10, `orangepi_zero2_defconfig`, `make tools`): unpatched fails to link;
  stubs path links and `mkimage` signs an RSA-2048 FIT; forced fallback disables LIBCRYPTO/KWBIMAGE and links.
- Upstream U-Boot: not fixed in master (`lib/rsa/rsa-sign.c` last changed 2025-11-11). Schuchardt "tools: fix
  building with OpenSSL 4.0" (2026-06, objection from Quentin Schulz); Kovsky "Add support for OpenSSL Provider API"
  v3 (2026-01) in review.
- Pushed: fork `fix/uboot-sunxi64-host-tools-openssl4` 0f3078155..4a8b8ef19 (fast-forward).

## 2. PWM overlays (fix/sunxi-h616-pwm-uart0-pins, d6633f686)

Checked with fdtoverlay on the Zero2 DTB (sunxi-7.3, kernel-check/work-vdec), alone and stacked; pin claims of all
enabled nodes compared with `prprep/pinconf.py` (`pwm-stacks.sh`, `pwm-matrix-before.log` / `-after.log`).

| Overlay | Pin (header) | Result on Zero2 |
|---|---|---|
| pwm1-ph3 | PH3 (pin 10) | clean; conflicts with overlays uart5 (PH2/PH3), i2c2-ph (PH3) |
| pwm2-ph2 | PH2 (pin 8) | clean; conflicts with uart5 |
| pwm3-ph0, pwm4-ph1 | PH0/PH1 = UART0 debug | **bug**: both claimed by serial@5000000 and PWM → PWM never outputs. Fixed |
| pwm1-pi11 … pwm4-pi14 | PI11–PI14 | collide with EMAC0 RGMII (PI0–PI16) on this board: hardware, not a bug |

Same channel on two pins: the last overlay wins (one `sunxi-pwms` subnode per channel). No conflicts with
i2c3-ph + spidev1_0 or orangepi-zero2-expansion + usb-otg-host + ir.

Fix (sunxi-6.18 and sunxi-7.3): pwm3-ph0/pwm4-ph1 also disable `&uart0`; pwm4-ph1 gets its compatible line;
`sun50i-h616-fixup.scr-cmd` drops `console=ttyS0,115200` for pwm3-ph0, pwm4-ph1 and the legacy `pwm34` (before:
only `pwm34`, an overlay name Armbian never shipped; it came with the BTT CB1 set; Orange Pi's BSP pairs
`ph-pwm34` with `disable-uart0`). Script tested in sandbox U-Boot. Pushed to fork.
Not fixed (unreachable): vendor driver `sunxi_pwm_disable_dual()` reads `pwms` instead of `sunxi-pwms`.

## 3. EMAC1 vs. upstream (harness/research/prprep-emac1.md)

No conflict on 7.3.1. At the 7.4 bump `add-second-emac-clock` (1/3 hunks) and `add-h616-internal-phy` (1/8)
fail on the match-table context next to upstream `61240e48a67d`; the two implementations overlap semantically.
Migration plan and the list of six backports to drop are in the note. Zero2 rgmii-rxid patch still needed.
No code changed; other boards' files untouched.

## 4. Rebase onto armbian/build main

- 39 `pr/<topic>` branches: own commits cherry-picked onto c2908d2 (or onto their prerequisite `pr/` branch).
  None obsolete. series.conf conflicts (only because branches were developed on the integration) resolved by
  context-free replay (`series-merge.py`) for gpu-cooling, bt-no-blob, cpuidle-dt, emac-rxid, quiet-log, vdec,
  vdd-sys, 5ghz-ap. Stacked: uwe5622 bt-wake/regdomain/quiet-log/5ghz-ap/bt-no-blob on bump-driver-pin
  (bt-no-blob also carries services + powersave); tv-encoder on drm-blend-mode (+ DE33 rebase commit);
  gpu-cooling on gpu-opp; cpuidle-dt and atf-system-suspend on atf-cpu-suspend; vdec-spec on cedrus-h616-upstream.
- `stonking-orangepizero2-rebased` 556b18714 (87 commits): all pr branches merged in integration order
  (5ghz-ap after vdd-sys-floor, pwm-uart0-pins last), except realtek-phy-hwmon (the integration adds and reverts it).
  Tree vs. `stonking-orangepizero2`: every other file equals upstream main, series.conf identical; the only
  non-upstream differences are commits 4a8b8ef19 and d6633f686.
- Checks: sunxi-7.3 series 745 applied / 0 failed (as the integration) on the rebased branch and 0 failed on every
  pr branch; no series order inversions; u-boot v2026.10-sunxi64 24/0 (stubs patch gone), atf-sunxi64 2/0.
- 7 `pr/group/*` branches for the grouped PRs (cherry-picks of the pr branches): kernel series 0 failed each.
- All pushed to fork as new branches; no existing ref rewritten.

## 5. PR drafts: docs/prs/ (README.md has the order, dependencies and the not-ready list)

## 6. docs/status.md rewritten for 2026-11-02

## Decisions for the user

1. OpenSSL 4: framework-level workaround in uboot.sh (chosen) vs. per-dir patches.
2. PR grouping (docs/prs/README.md), especially one uwe5622 PR + a bt-no-blob follow-up, TF-A + cpuidle DT together.
3. AI attribution in Armbian PRs: commits carry `Assisted-by: Claude:...` (40 with `claude-fable-5-1`, 11 with
   `claude-opus-5-5` on the rebased branch). Keep, unify, or drop before opening. One vdec commit also has a
   `Claude-Session:` line. Not rewritten here (non-destructive rule).
4. Commits to squash/reword before opening: openssl (2 → 1), regulators (2 → 1), distro subject mentions a
   print-server profile that is not in the branch.
5. vdec-spec: ask Jernej Skrabec before carrying his unposted patches.
6. Ethernet: retest the 512 KiB TCP stall and large-ping loss on the image kernel before opening the Zero2 DT PR.
