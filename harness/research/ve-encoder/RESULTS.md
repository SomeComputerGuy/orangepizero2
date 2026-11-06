# H616 VE H.264 encoder (cedrus stateless encoder): state

Task state file (AGENT-RULES "Budget"). Plan: `PLAN.md` section 4. Acceptance: `SPEC.md`, docs/datasheet-checklist.md W22.
Memory: project-ve-encoder.md. Updated 2026-11-06 by the ve-encoder agent (first implementation task).

## State: IMPLEMENTED, NOT BOARD-TESTED (runner job 27 queued)

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

- **Next step: coordinator merges f35cdf390 into test-cumulative, builds/serves the kernel, the runner runs job 27.**
  Then a fresh agent reads `logs/runner-venc/results.txt` + the summary and fixes what failed (PLAN 4.2 step 1), or,
  on PASS, continues with PLAN 4.2 steps 2-4 (CABAC A/B, NV21/YUV420 input, RC statistics).
- docs/status.md "Video encode" row and item 9 are the coordinator's to update (GAP -> IN PROGRESS, branch + job 27).
- W22 (4096x4096, CBR/VBR 256k-100M, ROI x8, MJPEG): PLAN 4.2 steps 5-6; CBR/CQ already exist in the core.

(The armbian commit f35cdf390 message names the job as 26; it was renumbered to 27 because 26-g2d.md took the number first.)
