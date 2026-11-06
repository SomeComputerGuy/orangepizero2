# H616 VE H.264 encoder (cedrus stateless encoder): state

Task state file (AGENT-RULES "Budget"). Plan: `PLAN.md` section 4. Acceptance: `SPEC.md`, docs/datasheet-checklist.md W22.
Memory: project-ve-encoder.md. Updated 2026-11-06 by the ve-encoder agent (first implementation task).

## State: r1-r4 PASS on c32 (job 37); the 1366x768 fault is a read past the NV12 source buffer, fixed in c33, runner job 38 queued

- 2026-11-06 (job 37 fix agent): job 37 on c32 passed r1-r4 (720p/1080p, I and I+P, 44-54 dB, framing right, hw
  decode md5 = ffmpeg's, compliance only the justified G/S_PARM fail); r5 (1366x768) faulted at 0xfff83000 again, so
  the c32 macroblock-info change was not the fix. Root cause: the input stage reads past the end of the NV12 source
  buffer (see "Job 37" at the end). Fix **d6d2ce09b** on fix/sunxi-h616-venc (merged into test-cumulative
  **342cfa31c = c33**, Image md5 866f3ca37c446a2d200e90c53221b82b). Runner job 38 (harness/runner-queue/38-ve-encoder.md) re-runs the package
  on c33 with r6 720x480 and r7 854x480 (I+P) and check 9 (debugfs buffer list, source room).

- 2026-11-06 (job 35 fix agent): job 35 on c31 completed r1-r4 (rc 0, 3 ms/7 ms per picture) but no stream decoded,
  and r5 (1366x768) faulted. Root causes and fixes: **4727ed447** on fix/sunxi-h616-venc (merged into test-cumulative
  91b91f9dc = **c32**, Image md5 5521e882b85f511947ced0996eb2c3bb): see "Job 35" at the end. Runner job 37
  (harness/runner-queue/37-ve-encoder.md) re-runs the package on c32.

- 2026-11-06 (job 34 fix agent): job 34 on c29 probed and passed the topology checks, then every picture faulted
  (`Page fault for 0x0 (master 3, dir rd, L1 page table)` + `frame processing timed out!`, 0-byte streams) and
  v4l2-compliance had 4 failures. Root cause and fixes: **201516cc5 + 4d9a200e8** on fix/sunxi-h616-venc (merged into
  test-cumulative 1d1c9e149 = **c30**, Image md5 9723454c0c955ab5dbc6193c29d78436, 864 patches, 0 failed, 0 C
  warnings): see "Job 34" at the end. Runner job 35 (harness/runner-queue/35-ve-encoder.md) re-runs the package on c30.

- 2026-11-06 (stall agent): job 32 on c27 hung in the first `v4l2-ctl --all` on /dev/video1. Root cause in this patch
  set, fixed by **ac009bb5b + c307dd053** on fix/sunxi-h616-venc (merged into test-cumulative 3d88bb858 = c29):
  see "Job 32" at the end. The paragraph below describes f35cdf390.

- armbian-build branch **`fix/sunxi-h616-venc`** at **f35cdf390** (worktree `wt-venc`, from test-cumulative eb446f8cb),
  pushed to `fork` only. For the coordinator to merge into test-cumulative (next cumulative kernel, c24+).
  - `patches.media/h616-venc/0801..0809-*.patch`: the generic 7 patches of Paul Kocialkowski's 2026-05 stateless
    H.264 encode series + the OPi5 project's two fixes. **Byte for byte `~/orangepi5/patches/linux/0801-0809`**
    (keep it so: a fix in one project is a copy to the other). The Hantro patches 8-14 are not carried.
  - `media-cedrus-add-a-stateless-H-264-encoder.patch`: `cedrus_enc.c`, `cedrus_enc.h`, `cedrus_enc_h264.c`,
    encoder registers in `cedrus_regs.h` (the old unused jemk-era `VE_ISP_*`/`VE_AVC_*` defines dropped), second
    video device `cedrus-enc` on the same m2m device, `ctx->is_enc` dispatch, shared VE-reset helper
    `cedrus_engine_switch_reset()`. Kconfig selects `V4L2_H264` + `V4L2_H264_ENC`.
  - `media-cedrus-enable-H-264-encoding-on-the-H616.patch`: `CEDRUS_CAPABILITY_H264_ENC` + the 0x12011 flags.
  - Build: W=1 clean for drivers/media/v4l2-core and drivers/staging/media/sunxi/cedrus (kernel-check/work-venc,
    linux-sunxi64-edge config: `CONFIG_V4L2_H264_ENC=y`). Full build (kernel-check/build-kernel.sh, ARMBIAN=wt-venc,
    WORK=kernel-check/work-venc): 856 patches applied, 0 failed, Image+modules+dtbs exit 0, 0 C warnings
    (kernel-check/run-venc-all.log).
- Project repo: `harness/research/ve-encoder/{PLAN.md (re-planned), RESULTS.md, runner/{venc-job.sh,HANDOFF.md},
  tools/{h264enc-test.c,build.sh}}`, `harness/runner-queue/27-ve-encoder.md`. Test tool binary `tools/out/h264enc-test`
  (static aarch64, built against the patched tree's uAPI headers; rebuild with `tools/build.sh`).
- Decode behaviour unchanged: the decoder node, its formats, controls and job path are the same code; only
  `cedrus_device_run()` gained the `is_enc` branch and the reset helper was factored out.

## What the first board run must answer (job 27, HANDOFF.md checks)

1. Probe: `cedrus ... Encoder registered as /dev/videoN`, 21 controls.
2. v4l2-compliance on the encoder node: 0 failures (unknown yet how it treats a stateless encoder; failures
   are to be fixed or justified one by one).
3. All-intra encodes at 720p/1080p/1366x768 decode with host ffmpeg: right frame count, no errors, PSNR-Y >= 30 dB.
4. I+P encodes (GOP 10) at 720p and 1080p: same.
5. The board's `v4l2slh264dec` decodes our streams bit-exactly (md5 = ffmpeg's).
6. No IOMMU fault, no `frame processing timed out`, no `encode failed` in dmesg.

Diagnostics by symptom are in PLAN.md 4.2 step 1.

## Design decisions taken (and why)

- Stateless uAPI (user, 2026-11-05); the core does headers/RC/DPB, cedrus only programs registers.
- Second video node on ONE m2m device rather than Bootlin's proc/engine rework: keeps the 13k-line patched decoder
  untouched, serialises encode and decode jobs on the engine for free, one IRQ handler. Cost: the m2m MC helper's
  one-set bookkeeping (PLAN 4.3).
- Vendor ("h6") register conventions for the H616 behind `CEDRUS_ENC_FLAG_*` variant flags, V3s (Bootlin) as the
  default: both are documented register maps (BliKVM lab record, Bootlin branch); no vendor code was read.
- CAVLC only for now: the hardware CABAC bit is known, the "fix mode num"/cabac_init_idc relation is not.
- Max 2048x2048 until the 0xbc4 line buffer for wider pictures is known (datasheet says 4096x4096: W22 open).
- EPTB: hardware does it; our rbsp ops toggle PARA0 bit 31 at byte boundaries (raw bits off, payload on), as the
  vendor library does; `ue`/`se` are left to the core (software Exp-Golomb through `bits`).

## Open items / next step

- **Next step: the runner runs job 38 (harness/runner-queue/38-ve-encoder.md) on c33 or later.**
  Then a fresh agent reads `logs/runner-venc/results.txt` + the summary and fixes what failed (PLAN 4.2 step 1), or,
  on PASS, continues with PLAN 4.2 steps 2-4 (CABAC A/B, NV21/YUV420 input, RC statistics).
  Copy 0810 (SPS/PPS nal_ref_idc) to ~/orangepi5/patches/linux/ (the 08xx core series is shared byte for byte). If an IOMMU fault remains,
  its address tells which buffer: a fault inside/just past one of the aux regions = that region is too small (double it);
  a fault at 0 again = yet another address register (the ISP output 0xa70/0xa74 and 0xb9c's neighbours are the
  remaining unwritten ones); a fault at a non-zero address = a programmed buffer read past its end (recon/sub-pixel).
- docs/status.md "Video encode" row and item 9 are the coordinator's to update (GAP -> IN PROGRESS, branch + job 27).
- W22 (4096x4096, CBR/VBR 256k-100M, ROI x8, MJPEG): PLAN 4.2 steps 5-6; CBR/CQ already exist in the core.

(The armbian commit f35cdf390 message names the job as 26; it was renumbered to 27 because 26-g2d.md took the number first.)

## Job 32 (2026-11-06, c27): STALLED, root cause = the encoder's media entities registered twice (fixed, c29)
- Summary harness/runner-queue/done/32-ve-encoder.summary.md: probe PASS ("Encoder registered as /dev/video1"), MEDIA
  line empty, dmesg-probe.txt shows `cedrus_probe+0x398/0x440` twice (the trace of the boot WARNING at
  drivers/media/mc/mc-device.c:619 `WARN_ON(entity->graph_obj.mdev != NULL)` in media_device_register_entity()), then
  `v4l2-ctl -d /dev/video1 --all` produced nothing (enc-all.txt empty) for 180 s; the restore reboot took ~6 min.
- Root cause: cedrus_probe() called `v4l2_m2m_register_media_controller(dev->m2m_dev, &dev->vfd_enc, ...)` after the
  decoder's call on the same M2M device. The helper keeps ONE sink entity, ONE proc entity and their pads in
  `struct v4l2_m2m_dev` (and reuses `source_pad` for the new source entity): the second call re-registers the
  decoder's sink/proc (WARN_ON x2) and re-adds their pads to `mdev->pads` from both media_entity_pads_init() (mdev
  already set) and media_device_register_entity(). list_add_tail() of a node that is already the list tail links it
  to itself: the pad list becomes `source, proc0, proc1, sink, sink, sink, ...`. MEDIA_IOC_G_TOPOLOGY (first thing
  v4l2-ctl -D/--all and v4l2-compliance do on a node with a media device, decoder or encoder) spins forever in
  media_device_get_topology() under graph_mutex: unkillable, no console message (CONFIG_PREEMPT, no softlockup
  detector), every later media access blocks, reboot waits out the unit stop timeouts. The same hang took down job
  29-g2d (its device-discovery loop ran v4l2-ctl -D on /dev/video0 first). The empty MEDIA line is the broken
  topology too (and /sys/class/media/*/model was checked with the wrong path pattern; now recorded verbatim).
- Fix (kernel): `patches.media/h616-venc/media-cedrus-register-the-encoder-s-own-media-entities.patch`
  (ac009bb5b; c307dd053 adds the series.conf line that ac009bb5b forgot, so c28 lacks the fix and c29 is the first
  kernel with it): the encoder gets its own source (the vdev entity), proc (MEDIA_ENT_F_PROC_VIDEO_ENCODER) and sink
  entities, pads and V4L interface node on the same media device, created and removed like the helper's
  (`cedrus_enc_register_media()/cedrus_enc_unregister_media()` in cedrus.c, storage in struct cedrus_dev). The
  single M2M device (job serialisation on the engine) is unchanged. Compile-checked W=1; built into c29.
- Fix (package, runner/venc-job.sh): nodes from /sys/class/video4linux/*/name (cedrus-enc / cedrus), media node and
  model recorded, `STEP` lines + `timeout -k 5` on every step, new probe values boot_warnings / media_node /
  media_info (v4l2-ctl -D on the encoder prints "Media Driver Info") / dec_D_rc, stall diagnostics
  (files/stall-diag-venc.txt), restore through restore-kernel.sh (DTB too), 500 s restore wait, FIX=c307dd053,
  ssh ConnectTimeout + ServerAlive (harness/ssh.sh).
- Re-queued as harness/runner-queue/34-ve-encoder.md. Next: a fresh agent reads results.txt + the summary (PLAN 4.2
  step 1 symptom table).

## Job 34 (2026-11-06, c29): FAIL, root cause = the engine reads through address registers left at 0 (fixed, c30)
- Summary harness/runner-queue/done/34-ve-encoder.summary.md, logs logs/runner-venc/ (files/venc/compliance.txt, r1-r5.txt,
  dmesg-chunk.txt). PASS: boot_warnings 0, media_info 1, dec_D_rc 0 (the job 32 hang is gone), 21 controls, probe.
  FAIL: media_node none; compliance_failed 4; r1-r5 rc 6 (tool: "frame 0: timeout waiting for the encoder"), 0-byte
  .h264; dmesg per encode `sun50i-iommu 30f0000.iommu: Page fault for 0x0000000000000000 (master 3, dir rd, L1 page
  table, status 0x8)` then, 2.0 s later, `cedrus 1c0e000.video-codec: frame processing timed out!`.
- Root cause (kernel). The headers went through the bit writer fine (no -110 from the sync-idle/put-bits polls), the
  fault comes right after the ENC_START trigger, on the first (I) picture already. The engine (IOMMU master 3) read an
  IOVA in the first MiB, i.e. through an address register holding 0: the setup, following the vendor sequence (BliKVM
  record, PLAN 1.6), wrote 0xb60 (motion vector buffer) = 0 and 0xbc4 (deblocking buffer) = 0 and never wrote 0xb9c
  (rate control buffer, vendor writes it only with RC on), 0xbc8 (temporal filter counts) or 0xba8/0xbac (REF1); the
  per-picture encoder reset clears them all. Without an IOMMU (vendor stack, BliKVM lab, V3s) a read of physical 0 is
  harmless and invisible (the lab only detected writes), so the record says "0xb60 = 0, nothing is written for it".
  Behind the IOMMU it is an L1 fault, the IRQ handler (iommu-sun50i-reset-the-sibling-masters patch) resets the master,
  the picture never finishes, the 2 s watchdog fires. The prefetch-walk faults (bit 31, c411b37fb) are already
  suppressed in c29, so this was a real access. Reference with an IOMMU: the T527 driver (dl/sunxi-venc-t527) gives
  0xb60 (UNK_BUF), 0xb9c (SCRATCH_BUF) and 0xbc4 (LINE_BUF) real buffers at every size ("frame-sized is safe"), and the
  older A20/H3 map (jemk) had a 0xb60 buffer of ALIGN(W,4)*H*8 bytes.
- Fix (kernel) `patches.media/h616-venc/media-cedrus-enc-give-every-encoder-address-register-a-buffer.patch`
  (201516cc5): one `struct cedrus_enc_h264_aux` allocation per context at start_streaming with regions for 0xb60
  (2 x ALIGN(W,4)*H*8), 0xb9c (2 x (12*H + 500)), 0xbc4 (2 x 8*W*16) and 0xbc8 (another 0xb60-sized region), programmed
  before every picture through cedrus_enc_addr() (>> 8 on the H616); REF1 Y/C point at the reference picture. New
  define VE_ENC_AVC_RC_BUF_ADDR (0xb9c). IOMMU stays on, every master translated. For 1080p the allocation is 12 pages.
- Compliance (kernel) `media-cedrus-enc-fix-the-v4l2-compliance-failures.patch` (4d9a200e8, + series.conf lines):
  TRY_FMT/S_FMT `!pix.sizeimage`: the tool sends a format of all ones (createInvalidFmt), sizeimage 0xffffffff aligned
  up to 256 wrapped to 0 -> clamp to CEDRUS_ENC_CODED_MAX_SIZE = 64 MiB (also keeps STM_BIT_MAX = size*8 in 32 bits).
  SUBSCRIBE_EVENT: V4L2_CID_MIN_BUFFERS_FOR_OUTPUT is for stateful encoders only (v4l2-test-controls.cpp:1184), nothing
  read it -> dropped, **20 controls**. G/S_PARM (v4l2-test-formats.cpp:1445 `node->is_m2m && !is_stateful_enc`): kept,
  the stateless encode uAPI needs the frame rate for the SPS VUI and the core's rate control and the OPi5 Hantro/VEPU580
  encoders fail the same test (orangepi5 codec-quality RESULTS.md); v4l2-compliance 1.32 predates the uAPI. Expected
  after the fix: Failed: 1, and the package's `compliance_unexpected` (fail lines other than formats.cpp(1445)) = 0.
  The two `Failed to setup encoding job: -22` at 45 s are the compliance "Requests" test queuing requests without the
  SPS/PPS/encode controls (the core refuses, the test passes): expected; the decoder logs the same for a bad request.
- Fix (package): media node looked up in /sys/bus/media/devices (media devices are on a bus; the tool itself found
  /dev/media0), fallback /dev/media0; `compliance_unexpected`; `dmesg_encode_failed` over the encode steps only
  (files/venc/dmesg-encodes.txt, DMESG-ENCODES-START marker); FIX=4d9a200e8; HANDOFF checks 1, 2, 7 updated.
- Build: c30 = test-cumulative 1d1c9e149 (merge of 4d9a200e8), kernel-check/run-cumul-c30.log: 864 patches applied,
  0 failed, build exit 0, 0 C warnings; Image md5 9723454c0c955ab5dbc6193c29d78436. cedrus dir compile-checked W=1 too.
- Re-queued as harness/runner-queue/35-ve-encoder.md. Code: compare against the T527 per-frame sequence
  (dl/sunxi-venc-t527/sunxi-venc/sunxi_venc_h264.c) for anything else that differs once the first picture completes.

## Job 35 (2026-11-06, c31): streams undecodable (32-bit puts dropped) + r5 fault (MB info buffer short) (fixed, c32)
- Summary harness/runner-queue/done/35-ve-encoder.summary.md; evidence archived in logs/job35-c31/ (results, encoder
  logs, compliance, dmesg, files/head-hex.txt). Note: the summary attributed the fault to r1 and said r2+ were aborted;
  results.txt shows r1-r4 all completed (rc 0, frames/keyframes right, ~3.2 ms at 720p, ~7 ms at 1080p) and only r5
  (1366x768, frame 0: "timeout waiting for the encoder") faulted: dmesg is checked after the chunk. HANDOFF now says so,
  and the package records dmesg per run.
- Streams: every one begins `07 42 c0 28 ...` (r1 head `0742c028965402802dd0c208ce3c3065b804...`): no Annex B start
  code anywhere, SPS/PPS NAL headers 0x07/0x08 (nal_ref_idc 0), the IDR slice header 0x65 right, and the SPS ends right
  after timing_info_present_flag = 1. Every missing piece is a 32-bit put: the core writes the start code as one u(32)
  (v4l2_h264_enc_rbsp_start_code) and num_units_in_tick/time_scale as u(32); the engine's bit writer drops a put of 32
  bits silently (STARTTRIG NUM_BITS 13:8 holds 32, but nobody ever put more than 24: jemk and the T527 driver write a
  start code as 24 zero bits + 16 bits, Bootlin splits u32 into bytes). Proof on the host
  (tools/job35-repair.py: start codes and the two timing fields put back, ref_idc 3): r1 30 frames PSNR-Y 49.2 dB,
  r2 (I+P) 47.6, r3 (1080p I) 53.9, r4 (1080p I+P) 44.4, all frames, no ffmpeg error. So the engine programming
  (ISP, reconstruction, references, P pictures, EPTB, slice header) is right.
- Fix 1 (`media-cedrus-enc-put-at-most-24-bits-at-a-time.patch`): cedrus_enc_h264_put_bits() splits every put into
  pieces of <= 24 bits, MSB first, each masked to its width.
- r5 fault `Page fault for 0x00000000fff83000 (master 3, dir rd, L2 page table)`: L2 = unmapped page in a mapped 1 MiB
  region. dma-iommu rounds IOVA ranges < 32 pages up to a power of two, size-aligned; the only encoder buffer whose end
  can be 0xfff83000 is 12 KiB at 0xfff80000: the macroblock info buffer (0xbc0), sized like the V3s map (4 KiB per 32 MB
  columns: 3 pages for 86 columns). 1280x720 (same 12 KiB, 45 rows vs 48) did not fault; 1920x1080 (16 KiB = whole IOVA
  range) reads into the neighbour if it overreads. (Inference from the address; no IOVA dump exists:
  CONFIG_DYNAMIC_DEBUG is off.) Fix 2 (`media-cedrus-enc-give-the-macroblock-info-buffer-a-picture-s-size.patch`): a
  picture's size (ALIGN(W16,32) x ALIGN(H16,128) x 3/2), as the T527 driver. IOMMU on. If job 37 still faults, the
  address again names the buffer by the same arithmetic (rec/subpix next).
- Fix 3 (`0810-media-h264-Write-parameter-sets-with-a-non-zero-nal_ref_idc.patch`, core): SPS/PPS with nal_ref_idc 3
  (H.264 7.4.1 forbids 0). Shared-core patch: copy to the OPi5 series.
- Compliance `fail: v4l2-test-codecs.cpp(161)`: it is in the DECODER node's section (/dev/video0; the package runs
  v4l2-compliance with -m, which tests every node of the media device). Known stock 1.32 limitation: the cedrus decoder's
  extra fourccs leave no codec mask, so stateful DECODER_CMD rules apply (impl-cedrus-compliance.md; fixed by our
  v4l-utils patches 0001-0003, not on the board). The encoder node had only the justified G/S_PARM fail. Package:
  compliance values from the encoder node's section only, decoder fails as `compliance_dec_fail` (information).
- Package: FIX=4727ed447, per-run dmesg (rN.dmesg.txt, rN dmesg_iommu/dmesg_timeout), head_hex (first 32 bytes),
  start_first/start_codes/nal_sps/nal_pps/nal_idr/nal_p/sps_ref_idc (check 8), hwdec_md5_match needs > 0 frames (job 35
  "matched" two empty outputs), HANDOFF exit-3 reporting clarified.
- Build: c32 = test-cumulative 91b91f9dc, kernel-check/run-cumul-c32.log: 868 patches applied, 0 failed, build exit 0, 0 C warnings, 0 dtc warnings; Image md5 5521e882b85f511947ced0996eb2c3bb. The two cedrus/core objects rebuilt with the fixes.


## Job 37 (2026-11-06, c32): r1-r4 PASS; r5 1366x768 faults on the page after the NV12 source buffer (fixed, c33)
- Summary harness/runner-queue/done/37-ve-encoder.summary.md; evidence archived in logs/job37-c32/ (results.txt, OOPS,
  files/r5.txt, r5.dmesg.txt, compliance, ...). Checks 1, 2 PASS; r1-r4 PASS on checks 3-6 and 8 (PSNR-Y 49.2, 47.6,
  53.9, 44.5 dB, hwdec md5 match, framing right); r5 frame 0 "timeout waiting for the encoder" after
  `Page fault for 0x00000000fff83000 (master 3, dir rd, L2 page table, status 0x8)`, the same address as job 35 on c31.
- Root cause (**inferred from the IOVA arithmetic, not proven by an IOVA dump**; job 38's debugfs list and the timeout
  report will prove or refute it). dma-iommu allocates top down and aligns every range to its size rounded up to a power
  of two (ranges < 32 pages are also rounded up in size). The test tool allocates OUTPUT, then CAPTURE, then
  start_streaming allocates MB info, aux, rec/subpix. At 1366x768 the first OUTPUT buffer is 1376 x 768 x 3/2 =
  1585152 bytes = exactly 387 pages (r5.txt: "output 1366x768 stride 1376 size 1585152"): it lands in the topmost
  2 MiB slot, 0xffe00000-0xfff82fff, so 0xfff83000 is the first page after it; frame 0 uses it. No other buffer of the
  run can end at 0xfff83000 (coded and, on c32, MB info are also 387 pages but are allocated later, lower; on c31 MB info
  was 3 pages and the address was the same, which rules MB info out). The "L2 page table" type (L1 entry valid) fits a
  mapped buffer just below. So the input stage reads past the end of the NV12 picture. 1366x768 is the only tested size
  whose macroblock-aligned picture fills its last page to the byte: 1280x720 has 20 KiB of slack in its last page
  (16 chroma lines; chroma at stride x 720, buffer sized for 736 lines), 1920x1080 15 KiB (8 lines), so the overread is
  shorter than 15 KiB. The BliKVM lab encoded 1366x768 correctly with stride 1376 (W16), so the engine does use the
  stride register (not a 64-aligned stride); the overread is either extra chroma lines or a burst rounded past the last
  line (1366 is the only tested width that is not a multiple of 64). Without an IOMMU (vendor stack, lab) the read is
  invisible. Not width-in-MBs or recon/ref: an I picture's first read past a buffer, and recon/subpix sizes have slack.
- Fix (kernel) `patches.media/h616-venc/media-cedrus-enc-give-the-source-buffer-room-for-the-engine-s-read-past-its-end.patch`
  (d6d2ce09b + series.conf line): raw format sizeimage = bytesperline x (ALIGN(h,16) x 3/2 + 16), one more macroblock
  row of luma (22 KiB at 1366), so odd widths work rather than being refused; NV12 layout (chroma at bytesperline x
  height) unchanged; IOMMU on. Diagnostics: the IOVA and size of every buffer of the last encode job (source, coded,
  mb-info, mv, rc, line, tfcnt, rec, rec-subpix, ref, ref-subpix) in /sys/kernel/debug/cedrus/encoder-buffers and as
  dev_err lines after an encode `frame processing timed out!`. The MB info buffer keeps a picture's size (T527), its
  comment no longer blames the fault on it. W=1 clean (cedrus dir).
- Package: FIX=d6d2ce09b; debugfs mounted if needed, rN.buffers.txt per run, results buffers_file / source_bytes /
  source_room (check 9); runs r6 720x480 and r7 854x480 (10 frames, IDR every 5 + P, QP 26); `cnt` helper fixes the
  "dmesg_iommu 0\n0" double value (grep -c prints 0 and fails, then `|| echo 0` printed another 0).
- If r5 still faults on c33: the dump names the buffer. A fault past the source buffer's new end = the overread is
  longer than one MB row (then size it by the dump's distance); a fault elsewhere = another buffer, same arithmetic.
- Build: c33 = test-cumulative 342cfa31c, kernel-check/run-cumul-c33.log: 869 patches applied, 0 failed, build exit 0, 0 C warnings; the 17 dtc warnings are the pre-existing pine64-7inch-lcd overlay and nanopi-r1s-h5 ones (as c30; c32 rebuilt no DTBs); Image md5 866f3ca37c446a2d200e90c53221b82b.
