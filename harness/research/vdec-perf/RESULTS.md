# vdec (cedrus H616) results and open items, 2026-11-05

Detail: harness/research/impl-vdec-main10-perf.md (§9.7 round 3, §9.8 round 4 + deferred ideas), impl-avs2.md (§8).
The board jobs still to run are packaged in runner/ (vdec-job.sh + HANDOFF.md). Job files:
harness/runner-queue/01-t1f9.md, 02-afbc.md, 03-soak3.md.

## Current state (cumulative kernel c9 = test-cumulative aa6e29312, VE at 624 MHz)
- **Bit-exact (P010 or linear):** H.265 Main10 P010 62.8 fps, AVS2 10-bit P010 61.3 fps, AVS2 AFBC 87.8 fps, VP9 P2
  P010 59.0 fps (round 3 on c2; nothing changed since).
- **VP9 P2 P010 4K60: deferred** (user). The limit is the IOMMU micro-TLB: 96 pages per 64x64 superblock, more than
  its 64 entries. The IOMMU stays on for every master. The untranslated opt-in was rejected and reverted (c8 only).
  The spec row counts as met through AFBC.
- **AVS2 uAPI v6:** merged, held for the joint RFC with rkvdec (docs/upstream-queue.md row 10).
- **test1.avs2 VE timeouts:** fixed. 91c6912a4 programs PIC_SIZE in whole 8x8 blocks; it is in c7 and later. All 2096
  pictures decode with 0 timeouts. Regression check: 4 other streams md5 PASS.

## Open items
1. **test1.avs2 (854x480, LCU 32, 8-bit) md5 mismatch: 72 of 2096 frames differ from davs2** (t1f9 on c9).
   - The differences come in bursts: 381-383, 889-895, and more (only the first 10 were captured).
   - Frame 382 is wrong although both its references (384 I, 380 B) match. The errors then spread to 381 and 383,
     which reference 382.
   - Other B pictures before an I picture (for example 46, 94) are fine, so the cause is content-dependent.
   - Hypotheses:
     a. Right-edge handling. 854 is not a multiple of 8: the VE codes 856 columns, and the last LCU column (x 832-855)
        is partial. Reference padding or MV clamping beyond x=853 may differ from davs2.
     b. Temporal direct / co-located MV scaling for particular POC distances.
     c. The kernel capture format (NV12 bpl 864, height 480): not likely, since 96 % of frames are exact.
   - Job 01-t1f9 prints, for frames 380-384 and 888-896, the differing pixels per plane and per 32x32 LCU (col,row),
     plus the full list of differing frames.
     - If every difference starts in LCU column 26 (x ≥ 832): (a). Compare MV clamping or padding with davs2
       (kernel-check/avs2-build/davs2-8) and the vendor library (kernel-check/dl-vdec/re/libawavs2.dis,
       Avs2SetHeaderReg).
     - Otherwise: (b). Dump the co-located picture's reference POC table.
   - The host tools work: harness/avs2dec builds with `-I <kernel>/usr/include`, and `-p -v` maps output frames to
     picture headers (/tmp/vdq/a2/out.map approach).
2. **AFBC capture md5: inconclusive.** afbc-check2 on c9, logs/queue-afbc/.
   - The board's Mesa fork at /root/opiz2-mesa/main is missing. The system Mesa 26.2.4 rejects every AFBC YUV dma-buf
     import (EGL 0x3009), so no frame was compared. This is an environment problem, not a VE result.
   - Job 02-afbc blocks cleanly while the fork is missing. Deploying the Mesa fork to the board is for the GPU/Mesa
     owner.
   - The checker's header stats also printed "body offsets ... out-of-range 31779". Re-check its header parsing
     (afbc/afbc-gpu-check.c -H) if the import works and frames still mismatch.
   - Tooling and method: commit 58d5407, kernel-check/afbc-dumps/report-draft.md (§10/§10.1, to be appended to
     impl-vdec-main10-perf.md with a §10.2 results table).
3. **Soak (gate): job 03-soak3 on c9.** Earlier results:
   - c7, 4174 s: VP9/H.265/VP9-AFBC 42/42 OK, VDD-SYS 900 mV, max 70.5 C, 0 timeouts. The AVS2 runs never ran
     because /root/avs2 was missing; that is fixed in the board scripts.
   - c8, partial, 1593 s: 18/18 OK including AVS2, 0 timeouts.
4. **IOMMU page faults on c9:** `sun50i-iommu: Page fault for 0x00000000fff00000 (master -1, dir rd)`, 5 lines at
   uptime 2140 s.
   - These happened about 17:58, during a c9 boot that began about 17:36. That was **before** the aq1 round, which
     started at uptime 3266 s and skipped the install because c9 was already booted.
   - So aq1 did not cause them. Whatever ran on the board around 17:58 is unidentified: another session that booted
     c9, possibly the GStreamer JPEG work.
   - master -1: the driver could not attribute the fault (page-table fault path).
   - 0xfff00000 is the top of the 32-bit IOVA space, the first IOVA that dma-iommu hands out. This looks like a device
     reading a buffer after it was unmapped.
   - Next: find which session held the lock at about 17:58 (board-lock history) and reproduce it with that test.
5. **aq1 (FFmpeg AVS2 request queueing, depth 2 "hold-back"; agent a613, stopped):** logs/queue-aq1/round.txt,
   package ffmpeg-avs2-queue/.
   - cctv4k 10-bit: starved gaps went from 151-152 per run (unpatched and low_delay) to 1 (hold-back). Wall time
     5.62-5.72 s against 5.73-6.23 s.
   - md5 PASS for AVS2 8-bit and 10-bit (hold-back on) and for 8-bit low_delay. The 17 8-bit conformance streams
     decode with rc=0.
   - Not done: the patch has to go through the desktop agent's patches/ffmpeg and the shared OPi5 FFmpeg set. Check
     ffmpeg-avs2-queue/README for the state of that hand-over.

## For a fresh agent, from the runner summaries
- **01-t1f9:** pick (a) or (b) from the LCU locations and fix in the right layer (the cedrus_avs2 register programming
  or the uAPI fill in avs2dec). Make a fix branch from test-cumulative and package a re-run of the same job (pass =
  `differing 0`).
- **02-afbc:** if blocked on Mesa, put "deploy Mesa fork to board" on the work list. If it ran, write §10.2 (per-codec
  F/C/M table) and commit logs/runner-afbc.
- **03-soak3:** if all checks PASS, mark the soak row done in docs/status.md. Any `[FAIL` line or timeout is a
  regression to bisect between c7 and c9.
