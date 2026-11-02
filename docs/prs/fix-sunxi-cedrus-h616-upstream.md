# sunxi-7.3: cedrus: use the upstream 7.4 H616 video engine commits

Branch: `pr/fix/sunxi-cedrus-h616-upstream` (4300ecb5e). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
Replace the 2021-era Cedrus H616 variant and VPU node patches with upstream `1f24d4307515` and `eabc3c090e81`
(Chen-Yu Tsai / Jernej Skrabec). The node now uses the H616 IOMMU (`iommus = <&iommu 3>, <&iommu 2>`) and claims
SRAM C and the VE SRAM.

## Why
Same code as the Armbian patch plus IOMMU/SRAM wiring as merged upstream; the old node bypassed the IOMMU.

## Testing
Kernel-check 690/0, Image + modules built. Board (Orange Pi Zero2, 7.3.1): MPEG-2, H.264, HEVC, VP8 bit-exact;
1080p H.264 150 fps, 1080p HEVC 310 fps, IRQ-count verified (docs/status.md); no IOMMU faults.

## Upstream status
In Linux 7.4; drop at the 7.4 bump.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
