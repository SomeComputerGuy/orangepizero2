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

## State
- 2026-11-06: package built and queued as job 53 (kernel c38 or newer, unchanged). Not run yet.

## Next (fresh agent, after done/53-afbc-wb.summary.md)
- PASS: AFBC capture of cedrus is bit-exact for HEVC 8/10 and VP9 P0/P2 (luma everywhere, chroma per tile); update
  docs/status.md AFBC item and the vdec RESULTS open item 2; real-* numbers go into the note.
- FAIL check 3 with mismatches everywhere and max_dev 1: likely an 8->10-bit expansion difference FBD vs linear fetch
  (not an AFBC data error); confirm with the dumps (files/<case>/dump/*.cap, packed XR30 1024x768, x bits cleared) by
  splitting the R/G/B differences; a real AFBC error shows as 16x16-block-shaped regions.
- FAIL check 3 only at distance < 10 in edge_dist_hist cannot happen (those pixels are outside the interior); if the
  histogram has mass at distance >= 10 inside tiles, compare per channel: chroma-only differences = phase/filter reach
  larger than assumed (raise --band and rerun), luma differences = real AFBC decode error.
- INCONCLUSIVE (src_md5 mismatch): cedrus lossless decode bug (HEVC transquant bypass / VP9 lossless) - separate item
  for the work list; the AFBC compare is still valid where captures matched.
