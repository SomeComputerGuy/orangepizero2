# W25: H616 G2D as a V4L2 mem2mem colour converter and scaler

State file of the task (datasheet item W25, docs/datasheet-checklist.md 2.5.3). Memory: project-g2d.md.

## State (2026-11-06, after job 33)
- **Now:** job 33 (c29) = probe/compliance PASS, every mixer job TIMEOUT (see "Job 33"). Follow-up patch 5 on
  `fix/sunxi-h616-g2d-selftest` 3f6c487d3 (worktree wt-g2d, pushed to fork, merged (ff) into test-cumulative = **c31**):
  BSP power-up order + both engines clocked + probe self-test. Runner job `harness/runner-queue/36-g2d.md` (c31+).
  Next (fresh agent after job 36): read the two `selftest` dmesg lines, table in "What job 36 decides".
- src/sun50i-g2d/* is now the state AFTER patch 5. Do not re-run src/mkpatches.py (it would fold patch 5 into patch 3);
  further changes go into a new patch diffed against kernel-check/work-cumul (the post-series tree).
- Kernel work: armbian-build branch `fix/sunxi-h616-g2d` (worktree `wt-g2d`, off `test-cumulative` eb446f8cb), pushed to
  `fork`, NOT merged (coordinator merges). Commit: see "Commits". Four patches in
  `patch/kernel/archive/sunxi-7.3/patches.media/h616-g2d/` (series.conf, end) and `CONFIG_VIDEO_SUN50I_G2D=m`:
  1. `clk: sunxi-ng: h616: Add the G2D bus reset` (RST_BUS_G2D = 64, G2D_BGR_REG 0x63c bit 16; mainline has the clocks
     CLK_G2D/CLK_BUS_G2D/CLK_MBUS_G2D but no reset).
  2. `dt-bindings: media: Add Allwinner H616 G2D` (allwinner,sun50i-h616-g2d.yaml).
  3. `media: sunxi: Add Allwinner H616 G2D colour conversion and scaling driver` (drivers/media/platform/sunxi/sun50i-g2d/).
  4. `arm64: dts: allwinner: h616: Add the G2D node` (g2d@1480000, SPI 90, clocks bus/mod/mbus, iommus = <&iommu 6>).
- Host checks: full kernel build (kernel-check/work-g2d), W=1 on the driver and the CCU file, dtc, dt_binding_check +
  CHECK_DTBS: see "Host checks".
- Board: NOT TESTED yet (job 26 BLOCKED by the DTB install, job 29 STALLED by the cedrus encoder's media bug; neither
  reached a G2D ioctl). Runner job `harness/runner-queue/33-g2d.md` (c29+), package `runner/{g2d-job.sh,HANDOFF.md}`,
  test tool `tool/` (g2dconv.c for the board and the host, g2dcmp.py). Results land in `logs/runner-g2d/`.
- Patch sources of truth: `src/sun50i-g2d/*`, `src/allwinner,sun50i-h616-g2d.yaml`, generated into the worktree by
  `src/mkpatches.py` (string edits of the post-series files in kernel-check/work-cumul). Re-run it after editing src/.

## What the driver does
V4L2 m2m, single-planar API, one contiguous buffer per frame, MMAP + DMABUF, VB2 dma-contig through the IOMMU (master 6,
prerequisite fix 4f711b354 already merged). Path used: video overlay V0 -> coarse decimator (HDS/VDS, engaged above 8x
horizontal / 4x vertical downscale) -> VSU scaler (4-tap, 32 phases, also upsamples chroma to 4:4:4; engaged for every
YUV source and for every size change) -> blender pipe 0 in COPY mode, ROP pass-through, colour space = source's -> CSC2
(only when RGB <-> YUV) -> write-back (does the chroma subsampling of YUV outputs).
- Formats (both queues, 18): XR24 AR24 BX24 BA24 XB24 AB24 RX24 RA24 (32-bit), BGR3 RGB3, RGBP; NV12 NV21 YU12 YV12,
  NV16 NV61 422P. Sizes 8..2048, step hsub/vsub; plane-0 pitch 16-byte aligned (a larger user pitch up to 2x is kept).
- CSC matrices are computed from the OUTPUT-queue colorimetry (ycbcr_enc 601/709/2020/240M, limited or full range), Q10
  fixed point; constants carry a +0.5 rounding bias. The capture queue inherits the colorimetry.
- Filter coefficients are generated (Catmull-Rom cubic, stretched by the downscale ratio); RGB sources get a linear
  vertical luma filter like the vendor does, YUV sources the cubic one. 4:2:0 chroma phase -0.25 (Q20 0xffff0000-ish
  value as the vendor's 0xfffc0000).
- Every job: mixer AHB reset pulse, program, enable the finish interrupt, start; 500 ms watchdog -> reset + buffers
  returned with ERROR + "job timed out" in dmesg. Runtime PM: bus + mod (300 MHz) + mbus clocks, CCU reset, TOP gates.
- Not done (W25 remainder): rotation/flip (ROT engine at 0x28000, V4L2_CID_ROTATE/HFLIP/VFLIP), UI overlays/blending,
  P010/P210/Y8/ARGB2101010/4444/1555, packed YUYV (different VSU path), crop/compose selection.

## Register notes (vendor BSP g2d_bsp_v2.c/g2d_regs_v2.h as reference, dl/vendor-5.4; manual has no register chapter)
- TOP 0x0000: SCLK_GATE/HCLK_GATE/AHB_RESET bit0 mixer, bit1 rot; SCLK_DIV; IP_VERSION 0x10. Vendor opens with 0x3 in
  all three and pulses AHB_RESET before each blit.
- MIXER 0x0100: CTL bit31 start (bits 4-7 scan order); INT bit0 finish flag (write 1 to clear), bit4 enable.
- V0 0x0800: ATTCTL = alpha<<24 | premul<<17 | fmt<<8 | alpha_mode<<1 | en; MBSIZE/SIZE (h-1)<<16|(w-1); COOR; PITCH0-2;
  LADD0-2; HADD = high bytes of the three planes; HDS/VDS_CTL0/1 coarse decimator ((mid<<16)|in, chroma variant).
- VSU 0x8000: CTRL bit0 en, bit8 held while writing coefficients, bit16 YUV; OUT_SIZE; Y/C_SIZE, H/VSTEP Q20, phases;
  Y_HCOEF 0x200, Y_VCOEF 0x300, C_HCOEF 0x400 (32 words of 4 x s8 taps summing to 64; tap -1 in the low byte).
- BLD 0x0400: EN_CTL bit8+n pipe enable; CH_ISIZE/OFFSET; CTL Porter-Duff factors (COPY 0x00010001, SRCOVER
  0x03010301); BLD_SIZE; OUT_COLOR bit0 premul, bit1 YUV colour space; ROP_CTL 0xf0 pass; CSC_CTL bit n enables CSC n;
  CSC n coefficients at 0x110 + 0x30 n, 12 words (3 rows: c0 c1 c2 const, Q10, two's complement 32-bit).
- WB 0x3000: ATT = format; SIZE; PITCH0-2; LADD/HADD per plane.
- Format codes: ARGB8888 0 .. BGRX8888 7 (name = little-endian word, so ARGB8888 = V4L2 ABGR32), RGB888 8, BGR888 9,
  RGB565 0xa; YUV422 SP UV 0x24 / VU 0x25 / planar 0x26; YUV420 SP UV 0x28 / VU 0x29 / planar 0x2a (= DE2 VI codes + 0x20,
  so 0x28 = NV12); Y8 0x30; P010 0x34; P210 0x36.
- Open question settled by the test, not by the sources: for planar YUV420 the vendor's g2d_set_info points hardware
  plane 1 at the third user plane; mainline DE2 (same code family) writes the DRM plane order (plane 1 = U). The driver
  assumes hardware plane 1 = U, 2 = V (YV12 swapped in the table). g2dcmp.py reports `uvswap 1` if the opposite holds.
- IOMMU: the manual (3.12, TLB6 prefetch note) suggests disabling the prefetch for G2D; the merged master-6 fix enables
  it for master 6 like the others. Keep as is unless job 26 shows iommu faults/garbage on this master (then the fix is a
  one-bit change of `sun50i_h616_variant.tlb_prefetch`, not a bypass).

## Host checks (2026-11-06, kernel-check/work-g2d, log kernel-check/run-g2d-build.log)
- Full build of test-cumulative eb446f8cb + the 4 patches: `patches applied: 849, failed: 0`, `build exit: 0; C warnings: 0`,
  sun50i-g2d.ko built (CONFIG_VIDEO_SUN50I_G2D=m), `DT_CHECK ok: g2d@1480000` and `allwinner,sun50i-h616-g2d` in the
  decompiled Zero2 DTB (clocks 0x22/0x21/0x37 = CLK_BUS_G2D/CLK_G2D/CLK_MBUS_G2D, reset 0x40 = 64, iommus <&iommu 6>).
- `make W=1 drivers/media/platform/sunxi/sun50i-g2d/ drivers/clk/sunxi-ng/ccu-sun50i-h616.o`: no output, exit 0.
- dtc: `dtbs exit: 0; dtc warnings: 17`, all pre-existing in unrelated files (sun50i-a64-pine64-7inch-lcd.dtso reg_format /
  pci / i2c / spi prerequisites, sun50i-h5-nanopi-r1s-h5.dtb) because this was a full tree build; none in sun50i-h616*.
- `make dt_binding_check DT_SCHEMA_FILES=media/allwinner,sun50i-h616-g2d.yaml`: exit 0, no finding for the schema (only the
  optional dt-check-style helper fails to import ruamel on this host, and the pre-existing hm5065.yaml parse error);
  `make CHECK_DTBS=y DT_SCHEMA_FILES=media/allwinner,sun50i-h616-g2d.yaml allwinner/sun50i-h616-orangepi-zero2.dtb`: exit 0,
  no g2d finding (dt-validate 2026.9).

## What job 26 decides (mechanical results -> next change)
- probe FAIL (no device): dmesg in files/g2d/probe-dmesg.txt: clock/reset names, IRQ, IOMMU attach.
- compliance failures: FAILLINE lines name the ioctl; fix in the driver.
- rgb-copy / rgb-* not exact: pitch/plane layout or format code mapping of the RGB entry (table in sun50i-g2d.c).
- rgb2yuv max_dev > tol with Y right and U/V wrong: CSC row order or the WB chroma order; `uvswap 1` on yu12/yv12 only:
  flip `swap_uv` of YU12/YV12 (hardware plane 1 = V).
- yuv2rgb wrong everywhere: VSU/CSC2 direction or BLD_OUT_COLOR_YUV; wrong at the borders only: cubic edge handling
  (border 2 already excluded, raise to 4 only if the interior is right).
- scale-* wrong but same-size right: VSU step/phase (Q20) or coefficient word order (tap -1 in the low byte).
- scale-down8 wrong, scale-down6 right: coarse decimator CTL1 encoding.
- TIMEOUT: the mixer never raised INT bit0: start bit / interrupt enable bit / clock gating; check `g2d_timeouts`.
- iommu_faults > 0: an address/pitch bug (fault address tells which plane) or the TLB6 prefetch note above.
- gst element 0: the v4l2 plugin did not pick the device (needs V4L2_CAP_VIDEO_M2M + a convert-capable format set).

## Commits
- armbian-build fix/sunxi-h616-g2d: 04964f921 `sunxi-7.3: H616 G2D as a V4L2 m2m colour converter and scaler (W25)` (off test-cumulative eb446f8cb, pushed to fork, unmerged).
- project repo: this file, runner/, tool/, src/, harness/runner-queue/26-g2d.md, .gitignore lines.

## Job 26 (2026-11-06, c25): BLOCKED, root cause = DTB never installed (package/harness bug, not the driver)
- Summary harness/runner-queue/done/26-g2d.summary.md: "no bound sun50i-g2d driver at 1480000.g2d". files/ was empty (the
  package collected nothing when blocked).
- Evidence: harness/serial.log 01:52:42 (the c25 trial boot): `Load fdt: /boot/dtb/allwinner/sun50i-h616-orangepi-zero2.dtb`,
  `53821 bytes read` = the image's stock DTB (c22 = 53965, c25 = 54481 bytes in kernel-check/vdec-serve). The g2d@1480000
  node exists only in the new DTB; harness/research/vdec-perf/install-kernel.sh installed Image + modules only (cumul-build.sh
  stages sun50i-h616-orangepi-zero2.dtb.<tag> but nothing used it), so there was no 1480000.g2d platform device at all.
  sun50i-g2d.ko was in modules-c25.tgz and has MODULE_DEVICE_TABLE(of); the IOMMU is untouched.
- Fix (project repo): install-kernel.sh installs the tag's DTB (stock copy kept as <dtb>.stock, the path becomes a symlink
  like /boot/Image; U-Boot follows it), new harness/research/vdec-perf/restore-kernel.sh (Image, DTB, modules .good,
  fallback disarmed, reboot) used by the packages' restore(), harness/research/vdec/vdec-fallback.sh re-points the DTB to
  .stock on the fallback and on every boot of a non-trial Image (safety net for older packages that only flip /boot/Image).
  g2d-job.sh verifies the DTB md5 after the boot and, when blocked, collects files/blocked-<tag>/{dmesg.txt,state.txt}
  (DT node status, devices_deferred, modinfo, lsmod, platform drivers).
- Re-queued as harness/runner-queue/29-g2d.md (kernel 04964f921 unchanged; c26 has it). Next: a fresh agent judges job 29
  with "What job 26 decides" above.

## Job 29 (2026-11-06, c27): STALLED, root cause = cedrus encoder media bug (kernel, not the G2D; package hardened)
- Summary harness/runner-queue/done/29-g2d.summary.md: probe PASS (bound, iommu group, 300 MHz), then the chunk's first
  `v4l2-ctl -d /dev/video0 -D` (the device-discovery loop over /dev/video*) never returned; stall watchdog after 240 s;
  the restore reboot took ~6 min ("BOARD UNREACHABLE" is only the 300 s wait of the old restore()).
- Root cause (also job 32-ve-encoder, same minute-one hang): the cedrus encoder patch f35cdf390 (c26/c27) called
  `v4l2_m2m_register_media_controller()` a second time on the shared M2M device. The helper owns one sink/proc entity
  set per M2M device, so the call re-registered them (the boot `WARNING: mc-device.c:619 media_device_register_entity`
  x2 with cedrus_probe in the trace) and, because media_entity_pads_init() and media_device_register_entity() both
  list_add_tail() the pads of an already registered entity, the media device's pad list ended with the sink pad linked
  to itself (simulated step by step: `... KP -> KP -> KP ...`). MEDIA_IOC_G_TOPOLOGY, which v4l2-ctl -D/--all and
  v4l2-compliance issue on any node of the media device, then loops forever in media_device_get_topology() with the
  graph mutex held: unkillable (CONFIG_PREEMPT keeps the box alive, no softlockup detector in this config), so every
  later V4L2 media access blocks and `systemctl reboot` waits out the stop timeouts.
- Kernel fix: fix/sunxi-h616-venc ac009bb5b "media: cedrus: register the encoder's own media entities" (+ c307dd053
  series.conf entry; c28 was built before it and lacks the fix), merged into test-cumulative 3d88bb858 = **c29**.
- Package fixes (runner/g2d-job.sh): the G2D node is found through /sys/class/video4linux/*/name (no ioctl on foreign
  nodes); every step prints `STEP <name>` and runs under `timeout -k 5`; `boot_warnings` and `cedrus_D_rc` (v4l2-ctl -D
  on the cedrus decoder, i.e. the topology ioctl) are recorded in probe.txt; on a stall the host logs the step name,
  collects files/stall-diag-g2d.txt (D/R tasks + /proc/PID/stack + dmesg tail) and the restore wait is 500 s; the
  kernel must also contain c307dd053 (BLOCKED otherwise); ssh (harness/ssh.sh and the scp options) has
  ConnectTimeout + ServerAliveInterval. harness/serial.log turned out to carry a second board's console (another Zero2
  on the PM-debug U-Boot, with rtcwake cycles at 04:44/04:45/05:08): its lines are not ours; the OOPS watch on that
  file can misfire.
- Re-queued as harness/runner-queue/33-g2d.md. Next: a fresh agent judges job 33 with "What job 26 decides" above.

## Job 33 (2026-11-06, c29): probe PASS, every mixer job TIMEOUT (kernel), plus two package count/parse bugs
- Summary harness/runner-queue/done/33-g2d.summary.md, logs logs/runner-g2d/. PASS: bound, /dev/video2, iommu group,
  300 MHz, boot_warnings 0, compliance 48/0, no IOMMU fault, no Oops. FAIL: 49/49 conversions `BUFERR` + no_output,
  67x `job timed out, mixer status 00000000`, gst both no_output.
- BUFERR = the client's DQBUF returned the buffers with V4L2_BUF_FLAG_ERROR: the 500 ms watchdog completes a job the
  mixer never finished with VB2_BUF_STATE_ERROR. compliance -s (1280) buf.check(q,last_seq) / (1735) captureBufs x6 is
  the same thing seen by v4l2-compliance (its streaming loop gets ERROR buffers). Not separate bugs.
- The decisive value: at the timeout MIXER_INT reads 00000000. The driver wrote 0x10 (FINISH_EN) into it right before
  the start bit, so even the enable bit did not stay: the mixer registers did not hold what was written and the engine
  never ran (no finish flag, no interrupt, no DMA, hence no IOMMU fault). TOP responds (IP_VERSION 01010100 at probe),
  so the bus clock, CCU reset (0x63c bit 16), MBUS gate (0x804 bit 10), the IRQ number (GIC 122 = SPI 90, manual) and the
  IOMMU master (6) are not what fails. Register offsets/bits were re-checked against g2d_regs_v2.h/g2d_bsp_v2.c (the
  sun50iw9 build of the BSP uses g2d_driver.c + g2d_bsp_v2.c, not g2d_rcq): MIXER 0x100 CTL bit31 / INT bit0 + en
  bit4, V0 0x800, BLD 0x400 (CSC2 0x570), WB 0x3000, VSU 0x8000, ROT 0x28000: all identical.
- Differences to the BSP that c31 removes: the BSP releases the reset before the clocks, writes 0x3 (mixer AND rotate)
  into SCLK_GATE/HCLK_GATE/AHB_RESET in g2d_bsp_open(), pulses AHB_RESET 0 -> 0x3 (both engines) before every blit
  (g2d_bsp_reset()), and sets the start bit by read-modify-write; the driver had gated/reset the mixer bit only.
- Open hypothesis, decided by the c31 self-test: IP_VERSION 01010100 decoded with the field layout of the BSP's newer
  RCQ header (g2d_top_type.h: gsu_no 1:0, vsu_no 3:2, rtmx_no 4, rot_no 8) says rtmx 0, vsu 0, rot 1, i.e. a
  rotation-engine-only block; the H616 manual's G2D feature list (2.2.5.3 / 4.3) indeed names only formats, flip and
  rotate (no scaling, no blending), while Allwinner's G2D guide lists H616 among the full-feature SoCs. If the mixer
  is really absent the converter cannot exist on this SoC and W25 becomes rotate/flip through the ROT engine.
- Package bugs (fixed): `formats_cap` counted from "Capture" to the end of formats.txt = Capture + Output (36; the file
  has 18 + 18); now counted per `Type:` section. gst: the device parse printed the property blurb "Device", and the
  generic `v4l2convert` element is the first m2m converter found (default device /dev/video3 on this kernel, not the
  G2D): the package now lists the plugin's converter elements and uses the one whose default device is the G2D node
  (gst-elements.txt, `element_name`). The gst `not-negotiated`/`can't handle caps` errors were that other device.
- Kernel: patch 5 `media: sunxi: sun50i-g2d: clock both engines and self-test the hardware at probe`
  (patches.media/h616-g2d/, series.conf after the DT patch), commit 3f6c487d3 on fix/sunxi-h616-g2d-selftest (off
  test-cumulative 1d1c9e149), fast-forward merged = c31. W=1 clean, checkpatch clean. The self-test never fails the
  probe; the timeout message now also prints CTL, TOP gates/reset, V0_ATTCTL, BLD_EN_CTL, WB_ATT and the IRQ count.

## What job 36 decides (the two probe lines `selftest regs:` and `selftest: mixer ...`)
- mixer_regs ok, mixer ok, conversions still failing -> a programming bug of the real job path (compare with the
  self-test's sequence, which uses the same overlay/blender/write-back helpers); use "What job 26 decides".
- mixer_regs ok, mixer ok, conversions pass -> the gating/reset order was the bug; go on with the W25 remainder.
- mixer_regs bad, rot_regs ok, rot ok -> the mixer is not there (or fused off) on this H616: the IP capability bits
  (rtmx 0 vsu 0) and the manual's feature list agree. Rework the driver into a ROT-engine m2m rotator/flipper (same
  register layout as mainline sun8i-rotate: CTL 0x00 bit0 en / bits 4-5 angle / bit 6 vflip / bit 7 hflip / bit31
  start, INT 0x04 bit0 flag / bit16 en), formats = what the ROT takes (same codes, no conversion), and record in the
  datasheet checklist that H616 G2D has no colour conversion/scaling; ask the coordinator before dropping the converter.
- mixer timeout/noirq with mixer_regs ok -> start bit or a missing enable (try MIXER_CTL bits / BLD_EN_CTL bit 0);
  noirq = flag set but no interrupt: IRQ routing (DT interrupt) or the enable bit.
- rot timeout too -> common cause (clock/reset/MBUS/IOMMU path): check the `top` values (expect 3/3/3).
- baddata -> address/pitch or format code; out0 vs in0 in the line tells byte order.
