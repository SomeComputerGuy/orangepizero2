# sunxi-7.3: h616: video decoding to the chip spec (VP9 Profile 2, HEVC Main10, 6K, VC-1, MPEG-4)

Branch: `pr/feat/sunxi-h616-vdec-spec` (e7d134946). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What
Jernej Skrabec's unposted cedrus work for the H616 (github.com/jernejsk/linux-1 h616-cedrus / h616-mpeg4, 2026-10)
rebased onto the sunxi-7.3 series, plus five of ours: select V4L2_VP9, H.265 up to 6144x4320 on H616, 8-bit H.265
AFBC opt-in only, capture payload without private planes, VE reset when switching to or from VP9. 27 patch files,
one series.conf block at the end. Stacked on pr/fix/sunxi-cedrus-h616-upstream.

## Evidence (Orange Pi Zero2, VE 600 MHz, VDD-SYS >= 0.89 V)
H.264 4K 42.0 fps bit-exact 300/300; HEVC 8-bit 4K 81.8 fps, 6K 30.2 fps bit-exact; HEVC Main10 4K bit-exact,
24.5 fps via P010; VP9 Profile 2 4K bit-exact, 35.6 fps via P010. The 4K60 10-bit spec needs the AFBC 10-bit path
read by the display, not measured yet. AVS2: no driver anywhere.

## Upstream status
Unposted; patches keep Jernej's authorship. Two bugs in his VP9/P010 code were found on the board and should be
reported to him.

## Before opening
- Ask Jernej whether he agrees to Armbian carrying the unposted branch.
- Commit "keep 8-bit H.265 AFBC..." carries a `Claude-Session:` line in its message; drop it.
- Depends on pr/fix/sunxi-cedrus-h616-upstream and, for stable 4K decode, on the VDD-SYS floor in
  pr/group/sunxi-h616-thermal-gpu.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
