# AFBC bit-exact check through the DE33 + writeback (state file, task afbc-wb)

## Why this route
Job 51 (c38): the H616 Mali-G31 reports AFBC_FEATURES 0x10001 (no AFBC), so a GPU import of the cedrus AFBC capture is
NOT TESTABLE. The DE33 can scan out AFBC: the VI channel 0 FBD (sun50i_afbc.c, DE+0x105000; afbc_mask BIT(0) on H616)
takes YU08/YU10 with AFBC 16x16 SPARSE(+SPLIT) = the modifier cedrus exports (0x0800000000000061); proven on the board
in impl-de33-afbc.md round 3 (FBD_CTL 0xFF000015, 4K60 HEVC Main10/8-bit and VP9 P2 playback). The DE33 writeback
connector (jobs 40-42 PASS on c35, XR24/XR30/NV12 pixel-exact) captures the composed output. So no kernel change.

## Method (harness/afbc-wb/)
- afbc-wb.c (static FFmpeg as afbc-kms-play, libdrm): decode with V4L2REQUEST_PIXFMT=<fmt>, every frame shown 1:1 on the
  AFBC-capable VI plane (same plane, same 1024x768 source window, BT.709 limited, primary off, black background) at
  1024x768@60 (HDMI forced on, no sink), then two writeback captures (XR30; poison 0x5a/0xa5 before each, must be
  identical). Linear pass (NV12/P010) saves the captures to /dev/shm and checks every decoded frame against the source
  md5s; AFBC pass (AS12/AS01) compares each capture with the linear one. FBD_CTL read via /dev/mem per frame (enabled
  only in the AFBC pass). Client sha256 a0129b60ff8e704d538000c8a6698cf5dc069033b30aadcd765634ff88540a1f.
- Why not a full-frame identity: sun8i_vi_scaler_setup() programs a different 4:2:0 chroma phase for AFBC (h/v
  -0.125/-0.125, "the decompressor fixes luma at zero and chroma at -0.25") than for linear (0/-0.25). Luma (phase 0 in
  both) and CSC are identical, chroma interpolation is not, so pixels near a chroma edge may legitimately differ.
  Synthetic streams therefore have flat chroma inside 64x64 tiles (colours change every frame) and full-detail moving
  luma; pixels >= 10 px from a tile edge (beyond the 8-tap chroma filter reach) must be bit-identical
  (--tile 64 --band 10). Streams are coded LOSSLESS (x265 lossless, libvpx-vp9 -lossless 1), so the decoded frame equals
  the source (host-verified by mkstreams.sh; on the board via the srcmd5 check) and the tile interiors are truly flat.
  Full-frame mismatches and their distance-to-edge histogram are reported (expected only at distance < band).
- mkstreams.sh / mkstreams.py: 4 streams (syn-hevc8/-hevc10 .mkv, syn-vp9p0/-vp9p2 .webm), 1024x768, 24 frames, 60 fps,
  GOP 12 (HEVC 3 B-frames), 11-17 MB each, in kernel-check/vdec-serve/afbc-wb/ (not committed). Host check: software
  decode == source, srcmd5 == ffmpeg framemd5 nv12/p010le.
- Real 4K vdec streams (hevc-main10/-main, vp9-p2/-p0 2160p60): 1024x768 window at 1408,704, 12 frames, no mask,
  informational (shows how large the chroma-phase difference is on real content).
- Not covered: AVS2 (no host encoder; the AVS2 AFBC path goes through avs2dec-afbc, not FFmpeg). Same FBD/plane path.
- FFmpeg install tree was stale again (build Nov 5 13:22 vs install Nov 3): refreshed with make install (no recompile);
  build.sh now refuses to link against a stale install.

## Runner job
harness/runner-queue/53-afbc-wb.md -> runner/afbc-wb-job.sh j53, HANDOFF.md checks 0-6, verdict PASS / FAIL (AFBC
differs) / INCONCLUSIVE (linear reference wrong) / FAIL (kernel) / NOT TESTED. Logs: logs/runner-j53/.

## Job 53 result (c38) and root cause (2026-11-06)
- Verdict FAIL for syn-hevc8/-hevc10/-hevc8-xr24 (~360k of 371712 interior px wrong per frame), PASS for syn-vp9p0/p2.
  Summary: harness/runner-queue/done/53-afbc-wb.summary.md; logs/runner-j53/.
- Dump analysis (host, files/*/dump/f00{0,1}.{afbc,linear}.cap, converted to Y/Cb/Cr, shift search +-20 rows/+-8 cols):
  every HEVC AFBC capture (synthetic 8/10-bit, xr24, real-hevc10 4K window) is best matched by the linear capture
  moved DOWN by exactly 4 rows (Y mean |d| 0.37 vs 30 for the next shift); VP9 best at shift 0. With the 4-row shift
  the HEVC tile interiors are bit-identical (raw XR30 words, frames 0 and 1: 0 of 367488 interior px differ for
  syn-hevc8, syn-hevc10, syn-hevc8-xr24). AFBC rows 0-3 are a flat fill; the last 4 picture rows are cut off.
- So the AFBC data is correct; the H.265 decoder writes its AFBC surface 4 lines down (picture row 0 = surface row 4).
  Hardware property of the H.265 VE AFBC writer, not configurable: the vendor library (libcedarc androidq_64
  libawh265.so DWARF) inlines HevcInitAfbcInfo(pHevcDec, pRef, pAfbcHeader, nTopCrop=4, header_layout 1,
  yuv_transform 0, block_split 1, mb 16) and computes block_height = (height + 4 + 15) >> 4 (disasm 0x1a564); its
  display driver gets top_crop via the sunxi_metadata AFBC header and programs FBD_SRC_CROP. No VE register for it
  (the only bEnableAfbcFlag-dependent register write in HevcDecodeOneSlice is the frame-info chroma address). The
  Armbian/Jernej AFBC sizes already use "height + 4" for this. Mainline sun50i_afbc.c writes FBD_SRC_CROP = 0 and
  knows nothing about the codec, so LibreELEC presumably shows H.265 AFBC 4 lines low as well (not checked).
- Vendor libawvp9HwAL / libawavs2 also pass top_crop 4 (location lists DW_OP_lit4), but our VP9 is measured 0
  (H616 VP9 output differs from that library's target). AVS2 AFBC offset is UNVERIFIED (open item).

## Fix (c39)
- Kernel: armbian-build fix/sunxi-cedrus-h265-afbc-compose 8b1f787fe (worktree wt-afbc-hevc, off test-cumulative
  76bd27766): patches.media/h616-vdec/media-cedrus-report-the-H-265-AFBC-picture-offset-in-the-compose-rectangle.patch
  (end of series.conf): VIDIOC_G/S_SELECTION on CAPTURE, COMPOSE(_DEFAULT) = (0, top, w, h), COMPOSE_BOUNDS/PADDED =
  (0, 0, w, h + top), top = 4 for H.265 + AS12/AS01 capture, else 0 (S_SELECTION returns the fixed rectangle). No DRM
  change: the plane source rectangle (FBD_LAY_CROP) carries the offset. Merged into test-cumulative d67f25b42 = c39.
- FFmpeg (kernel-check/ffmpeg-afbc/src/ffmpeg, local, diff in harness/afbc-wb/ffmpeg-v4l2request-compose.diff):
  hwcontext_v4l2request queries G_SELECTION(COMPOSE) after the CAPTURE G_FMT; the hwaccel post_process makes the
  frame width/height + left/top and crop_left/crop_top += left/top (hwaccel crop: right/bottom applied, left/top kept
  for the consumer). Upstream-able idea for Jernej's v4l2request fork (not sent).
- afbc-wb.c: framebuffer = frame width x height (whole surface), plane source window at crop + frame crop_left/top;
  prints `RESULT frame N pic_offset X,Y fb WxH` (frame 0 and on change). Client sha256 in the job file.
- Package: runner/afbc-wb-job.sh j54 (requires 8b1f787fe in the kernel, extracts pic_offset, adds informational case
  real-vp9p0-y4 = window at 1408,708 to show a non-16-aligned FBD_LAY_CROP works); HANDOFF.md check 7 (pic_offset).

## State
- 2026-11-06: c39 built (test-cumulative d67f25b42, Image md5 b74f1af053066a48ab7ac8a5bae26005, 875 patches, 0 warnings); job 54 queued (harness/runner-queue/54-afbc-wb-rerun.md). Not run yet.
- Separate item (not fixed): real-hevc8 LINEAR pass (4K H.265 8-bit NV12) had writeback wb_error -5 on frames 2, 6, 8
  (wb_jobs 48 vs done 45, dmesg clean). Only that case; likely the writeback missing its frame under 4K NV12 VE+DE
  memory load. On the work list; rerun shows whether it repeats.
  2026-11-06: repeated in job 54 (frames 2, 6). Taken on as task wb-eio: harness/research/wb-eio/RESULTS.md (RT-WB
  OVERFLOW/TIMEOUT under the async 4K decode; kernel fix 20e682fc2 repeats the capture on the next frame, c40, job 55
  = afbc-wb-job.sh j55).
- Open: AVS2 AFBC picture offset (vendor says 4; avs2dec-afbc path, not covered by this job).

## Next (fresh agent, after done/54-afbc-wb-rerun.summary.md)
- PASS: AFBC capture of cedrus is bit-exact for HEVC 8/10 and VP9 P0/P2; update docs/status.md AFBC item, vdec
  RESULTS open item 2, memory project-vdec.md; real-* numbers go into the note.
- check 7 fails with `afbc pic_offset 0,0` on HEVC: the kernel lacks the selection (wrong kernel) or FFmpeg in the
  client is stale (check the client sha).
- pic_offset 0,4 but interior mismatches remain: compare dumps with the 4-row-shift script logic above (shift
  search); if a residual shift appears, the FBD applies LAY_CROP only in 16-line steps -> program the sub-superblock
  part via FBD_SRC_CROP in sun50i_afbc.c (real-vp9p0-y4 vs real-vp9p0 shows this independent of HEVC).
