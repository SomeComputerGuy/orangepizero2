# vdec (cedrus H616) results and open items, 2026-11-05

Detail: harness/research/impl-vdec-main10-perf.md (§9.7 round 3, §9.8 round 4 + deferred ideas), impl-avs2.md (§8).
The board jobs are packaged in runner/ (vdec-job.sh + HANDOFF.md). Job files: harness/runner-queue/01-t1f9.md (done),
02-afbc.md (held), 03-soak3.md (done), 07-avs2-test1.md (t1fix, waiting for the merge of fix/sunxi-avs2-poc-base),
12-avs2-queue.md (avs2q, FFmpeg 0313).

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
   **Root cause found, fix on `fix/sunxi-avs2-poc-base` (fa73c3e5e, pushed to fork, to be merged); board check =
   job 07-avs2-test1 (runner t1fix).**
   - Not the right edge: frame 382's errors are in LCU columns 10-14 (x 349-450), frame 896's cover the whole picture.
   - Decode-order analysis (avs2dec `-p -v`, /tmp/t1a/pv.txt): the first wrong picture of each burst is
     B 382 (refs 384 I, 380), F 896 (refs 888, 886), F 1408 (refs 1400, 1398), B 1916 (refs 1920 I, 1912); all their
     references are bit-exact. Common factor: a picture whose POC & 0x1ff = **0x180** (384, 896, 1408, 1920) is the
     current picture (F) or reference 0 = the co-located picture (B). Pictures the vendor would program as 0x080
     (128, 640, 1152, 1664) and the hundreds of pictures with POC 256-511 whose bit 8 differs from the vendor's value
     are all fine; 0x180 as reference 1 (B 385-391, 1921-1927) or as the single reference of F 392/1928 is fine too.
     With the I picture as co-located picture B 380 is fine but B 382 and B 1916 are wrong: content-dependent (a mode
     that scales by the backward distance), so the engine is not purely modular in the order counts.
   - The driver wrote `poc & 0x1ff` of the unwrapped POC. The vendor library (Avs2ParsePictureHeaderInf, dis 0xbb24)
     writes the reference-software values: 8-bit coding_order + output_delay - reorder_delay, and lowers the stored
     counts of all frames by 256 at each coding_order wrap (`AVS2_FRAME_INFO.poc` is an s16; the RD code is
     `calc_picture_distance` in Amlogic's avs2_bufmgr.c). That equals POC - 256 x wraps, so the differences are the
     same but the values stay in about -23..290 and never hit 0x180.
   - Fix: `cedrus_avs2_poc_base()` derives that base from decode_order_index, picture_output_delay and
     picture_reorder_delay (fallback: `poc & ~0xff` if the fields are inconsistent) and subtracts it from every table
     entry (references, current picture, stored ref-POC lists, background substitution). Patch
     `media-cedrus-AVS2-program-the-vendor-s-picture-order-counts.patch` after the h616-vdec group; gcc syntax check
     with the kernel flags clean (-Wall -Wextra -Werror), checkpatch --strict clean. Simulated on test1's picture list:
     the table values become -10..256, no 0x180.
   - If 07-avs2-test1 still shows differing frames: the pattern then tells whether the value is a sentinel (count
     unchanged -> different cause) or the engine wants exactly the vendor's values (try base from the 8-bit DOI only).
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
   - Landed 2026-11-05 as patches/ffmpeg 0313 (README row, SHA256SUMS; the set stays byte-identical to OPi5's final
     plus 0313), ffmpeg deb REV 4 (build chained behind the running REV 3 build, log logs/media-debs-rev4.log). OPi5
     adoption note: harness/research/ffmpeg-shared/HANDOFF-avs2-queue.md (the coordinator passes it on). Board
     re-check = runner job 12-avs2-queue (vdec-job.sh avs2q: 17 8-bit md5s + cctv4k Main10 + starved-gap count).

## For a fresh agent, from the runner summaries
- **01-t1f9:** done (root cause and fix above). **07-avs2-test1 (t1fix):** pass = `[count] frames 2096 differing 0`,
  five `[<stream>] PASS` lines, 0 timeouts. On PASS: mark the test1 row done (docs/status.md), note it in
  impl-avs2.md §8.8. On FAIL: see the last bullet of open item 1.
- **02-afbc:** if blocked on Mesa, put "deploy Mesa fork to board" on the work list. If it ran, write §10.2 (per-codec
  F/C/M table) and commit logs/runner-afbc.
- **12-avs2-queue (avs2q):** pass = 18 `[md5 ...] PASS`, both holdback `gap starved n=` <= 3, 0 timeouts. On PASS: close
  the "AVS2 FFmpeg depth-2 queueing" work-list line in docs/status.md and tell the OPi5 session (HANDOFF-avs2-queue.md).
  On FAIL: an md5 FAIL = 0313 regression (compare files/<stream>.framemd5 with the aq1 lists in logs/queue-aq1/out);
  a gap count back at ~150 = the hold-back is not active (check the `[binary]` sha256 line first).
- **03-soak3:** if all checks PASS, mark the soak row done in docs/status.md. Any `[FAIL` line or timeout is a
  regression to bisect between c7 and c9.
