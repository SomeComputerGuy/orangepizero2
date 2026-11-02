# sunxi-7.3: drm/sun4i: add the pixel blend mode property to DE2/DE3 planes

Branch: `pr/fix/sunxi-drm-blend-mode` (161ac57a5). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
`drm_plane_create_blend_mode_property()` on UI and DE3 VI planes (pre-multiplied, coverage, none) and
`BLD_PREMUL_CTL` programmed per pipe in the mixer commit.

## Why
7.x warns six times per boot ("pixel format with alpha exposed but blend mode not setup") on DE33, and the same on
every DE2/DE3 board. KMS assumes pre-multiplied alpha but the blender multiplied again (coverage blending).
Earlier attempt: Roman Stratiienko's 2020/2022 series, not merged; this follows Jernej's review of it.

## Testing
Orange Pi Zero2: 0 blend-mode warnings (board PASS). Display output with an HDMI monitor not yet checked.

## Upstream status
Not in mainline; candidate for dri-devel after an HDMI check.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
