# H616 EMAC1: Armbian sunxi-7.3 patches vs. upstream 61240e48a67d (Linux 7.4)

Date: 2026-11-02. Question from impl-kernel.md §2 item 1 "Follow-up": does Armbian's EMAC1
support collide with upstream's, today on 7.3 or at the 7.4 bump? No code was changed. Other
boards' files were not touched.

## 1. What exists

| | Armbian sunxi-7.3 (today) | Upstream (torvalds master = v7.4-rc1, checked 2026-11-02) |
|---|---|---|
| Driver variant | `drv-net-stmmac-dwmac-sun8i-add-second-emac-clock.patch` (Andre Przywara, 2020): optional 2nd cell of `syscon` = register index, so EMAC1 hits 0x30 + 4 = 0x34; table entry `allwinner,sun50i-h616-emac` → `emac_variant_h6`. `drv-net-stmmac-dwmac-sun8i-add-h616-internal-phy.patch` (Alastair D'Silva, 2026-06, armbian #9952, rebased by us in `fix/sunxi-dwmac-sun8i-upstream-reset`): `emac_variant_h616_internal` (`soc_has_internal_phy = true`, MII/RMII/RGMII, H3 mdio-mux path without `H3_EPHY_SELECT`), compatible `allwinner,sun50i-h616-internal-emac`, and a chip-ID-derived MAC address when none is supplied (applies to **every** dwmac-sun8i instance) | `61240e48a67d` "net: stmmac: sun8i: add support for Allwinner H616 EMAC1" (James Hilliard / Richard Genoud, net-next, in 7.4): `sun8i_syscon_reg_field_emac1` (reg 0x34), `emac_variant_h616_emac1` (`soc_has_internal_phy = false`, RMII only, no delays), compatible `allwinner,sun50i-h616-emac1`; PHY bring-up left to the PHY driver |
| Binding | none (Armbian compatibles are not in any binding) | `allwinner,sun8i-a83t-emac.yaml`: `allwinner,sun50i-h616-emac1` standalone, `phy-mode` must be `rmii`; EMAC0 = `allwinner,sun50i-h616-emac0` + `allwinner,sun50i-a64-emac` |
| SoC DT node | `0301-arm64-dts-sun50i-h616-add-emac1-rmii-pins.patch`: `emac1: ethernet@5030000`, compatible `allwinner,sun50i-h616-emac`, `syscon = <&syscon 1>` | **no** `emac1` node in `sun50i-h616.dtsi` at v7.4-rc1 (only `emac0: ethernet@5020000`) |
| PHY | `drv-net-phy-ac300-phy-add.patch` (AC300, H618), `0202-drv-net-phy-ac200-ephy-add.patch` + `drv-mfd-ac200-add-ephy-syscon.patch` (AC200, H616) | no AC200/AC300 PHY driver in 7.4 |
| Users | Orange Pi Zero2W (`0302-...`), BigTreeTech CB1 (`...cb1-emac1-ac300.patch`), X96 Mate (`...x96-mate-enable-emac1.patch`), `dt_64/` Banana Pi M4 Berry, WalnutPi/WalnutPi ZeroW, X96Q | — |

The **Orange Pi Zero2 does not use EMAC1**: its Ethernet is EMAC0 + external RTL8211F over RGMII
(PI0–PI16). Its node is untouched by all of the above, except the chip-ID MAC fallback, which
only fires when U-Boot passes no address (ours does: `ethaddr` from the SID).

## 2. Conflicts today (7.3.1): none

- All dwmac-sun8i patches apply in series order on vanilla 7.3.1 (megous 0026–0028,
  `fix-ephy-clock-leak`, `reset-mac-after-phy-init`, `add-second-emac-clock`,
  `add-h616-internal-phy`): checked again here with `filterdiff | patch` on a vanilla copy
  (`kernel-check/prprep/emac1/a`, branch `s73`), and the full series applies 0-fail in every
  kernel-check run of the integration tree.
- 7.3 has neither the upstream compatible nor the variant, so Armbian's compatibles are the only
  ones; no double match is possible. The `syscon` index cell is only read when present, so
  EMAC0 (`syscon = <&syscon>`) is unaffected.

## 3. What breaks at the 7.4 bump (simulated)

Simulation: vanilla 7.3.1 `dwmac-sun8i.c` + the three 7.4 commits we know (`d9750b3c4c27`,
`fee9c17671b6`, `61240e48a67d`), then Armbian's remaining patches in series order
(branch `s74` in the same scratch repo):

| Patch | Result on 7.4 base |
|---|---|
| megous 0026–0028 (PHY regulator) | apply |
| `drv-net-stmmac-dwmac-sun8i-fix-ephy-clock-leak.patch`, `...-reset-mac-after-phy-init.patch` | **drop**: they are `d9750b3c4c27` / `fee9c17671b6`, now in the base |
| `drv-net-stmmac-dwmac-sun8i-add-second-emac-clock.patch` | 1/3 hunks FAIL (match table: upstream inserted `sun50i-h616-emac1` where the Armbian entry goes) |
| `drv-net-stmmac-dwmac-sun8i-add-h616-internal-phy.patch` | 1/8 hunks FAIL (same match-table context) |

The rejects are context-only; semantically the two implementations overlap:

1. Two ways to reach the 0x34 clock register (Armbian `syscon` index vs. upstream variant field).
   For a sunxi-7.4 tree, the coherent choice is upstream's: EMAC1 node `compatible =
   "allwinner,sun50i-h616-emac1"`, `syscon = <&syscon>`, `phy-mode = "rmii"`; drop
   `add-second-emac-clock.patch` and its `allwinner,sun50i-h616-emac` table entry.
2. Internal PHY model: Armbian runs the AC300 through the H3 internal-PHY/mdio-mux path
   (`soc_has_internal_phy = true`, `allwinner,sun50i-h616-internal-emac`); upstream says no H3
   EPHY controls, PHY driver does the work. Moving the boards means: the AC300 driver must do the
   power-up/calibration on its own (it already does SYSCON/bandgap per its commit message), the
   board DTs drop the `mdio-mux` wrappers and point `phy-handle` at the PHY on `mdio1`, and the
   `h616_internal` variant goes. **Needs a board with EMAC1** (Zero2W/CB1/BPi M4 Berry) — cannot
   be validated on the Zero2.
3. The chip-ID MAC fallback is Armbian-only and not part of either upstream patch; keep it
   (rebased onto the new match table) or move it to U-Boot. It changes nothing on boards whose
   bootloader supplies `local-mac-address`.
4. Upstream 7.4 has no `emac1` dtsi node, so `0301-...-add-emac1-rmii-pins.patch` stays (with the
   compatible change above) until the DT side lands upstream.

Minimal mechanical bump (no behaviour change, if the board migration is not done yet): keep both
Armbian patches, re-diff the match-table hunk after the upstream `h616-emac1` entry, drop the two
backports. Then Armbian and upstream compatibles coexist (different strings, no double bind).

## 4. Other sunxi-7.3 patches of ours that are upstream in 7.4 (drop at the bump)

- `drv-net-stmmac-dwmac-sun8i-fix-ephy-clock-leak.patch` = `d9750b3c4c27`
- `drv-net-stmmac-dwmac-sun8i-reset-mac-after-phy-init.patch` = `fee9c17671b6`
- `drv-staging-media-sunxi-cedrus-add-H616-variant.patch` = `1f24d4307515`,
  `arm64-dts-sun50i-h616-add-video-engine.patch` = `eabc3c090e81`
- `pm-suspend-do-not-call-suspend-ops-begin-end-for-s2idle.patch` = `4785d5faa935`,
  `pm-sleep-add-dpm-watchdog-to-all-phases.patch` = `33392343c74e`

Not upstream at v7.4-rc1, keep: `arm64-dts-sun50i-h616-orangepi-zero2-fix-emac-rx-delay.patch`
(master's Zero2 DTS still has `rgmii` + `allwinner,rx-delay-ps = <3100>`), the Zero2 GPU OPP,
thermal, cpuidle, VDD-SYS floor, mmc alias and regulator DT patches, the vdec work.

## 5. Checklist for whoever bumps sunxi to 7.4

1. Drop the six backports in §4.
2. Re-diff `add-second-emac-clock` and `add-h616-internal-phy` against the 7.4 match table (or do
   the migration in §3.1–3.2 with an EMAC1 board on the bench).
3. Run the kernel-check `STAGE=patch` and `STAGE=dtbs` for sunxi-7.4; Zero2: `ethernet@5020000`
   unchanged, `rgmii-rxid` patch still applies.
4. Board test on the Zero2: link at 1000, 10 cold boots with RX (the rgmii-rxid regression check).
