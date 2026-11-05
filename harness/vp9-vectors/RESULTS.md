# cedrus VP9: the 64 failing conformance vectors (task state, 2026-11-05)

Task: docs/status.md item 9, "port OPi5's VP9 resize fix (0606/2228 + GStreamer 0010); cedrus VP9 still fails 64
vectors". Code agent, no board access. Kernel branch `fix/sunxi-cedrus-vp9-inter-resize` (armbian-build, pushed to
`fork`, commit f8be54bac, off test-cumulative aa6e29312 = c9). Runner job `harness/runner-queue/04-vp9-vectors.md`.

## 1. Which 64 vectors, and why (groups)

There has never been a fluster VP9 run on our board (impl-vdec.md §6 step 5: cloning fluster was refused then). The
"64" is Jernej's number from his FFmpeg run on the H616 ("241 of the 305 profile 0 vectors pass. The others change
the frame size in inter frames, which FFmpeg handles by reallocating the capture buffers and so loses the references,
or, in one case, use references of a different size, plus vp90-2-10-show-existing-frame"). Reconstructed from the
suite (fluster VP9-TEST-VECTORS.json, 305 vectors) and `ffprobe` frame-size/key-frame sequences of all 311 vectors
(`build/vp9-vectors/vec/`, fetched by `fetch-vectors.sh`; host ffprobe, pre-approved FFmpeg):

| group | vectors | what the stream does | cause of the FFmpeg failure | GStreamer (our fluster decoder) |
|---|---|---|---|---|
| A. inter-frame downsize | 24 x `vp90-2-21-resize_inter_*` (to 1/2 or 3/4 on frame 10, error resilient, no later key frame), `vp90-2-05-resize.ivf` (352x288 -> 282x173 -> 352x288), `vp90-2-18-resize.ivf` (310x230 -> 248x138 -> 310x230 -> 155x115) = **26** | size change on an inter frame, references of the old size are used with scaled motion compensation | FFmpeg reallocates the CAPTURE queue -> references gone | v4l2slvp9dec 1.28 drops every frame after the change until a key frame unless the driver has REMOVE_BUFS (cedrus: no) -> fail. **Fixed here** (kernel + GStreamer patch), to be confirmed on the board |
| B. inter-frame upsize | `vp90-2-22-svc_1280x720_3.ivf` (key 320x180, inter 640x360 and 1280x720, repeated) = **1** | frames larger than the CAPTURE buffers, references smaller | same reallocation issue; Jernej's "references of a different size" case | **Open**: needs `VIDIOC_REMOVE_BUFS` + S_FMT(CAPTURE) while streaming + per-buffer plane offsets in cedrus (the OPi5 rkvdec "patch 3" route). The driver now rejects such a frame with -EINVAL instead of overrunning the buffers |
| C. key-frame resize | 36 x `vp90-2-14-resize-*` (432x240 ... 3840x2160 and 4096x2304 on **key frames**, 10 or 3 frames each) = **36** | resolution changes only on key frames | FFmpeg hwaccel reinit at every key-frame size change (its problem, not the hardware's) | normal renegotiation (streamoff, S_FMT, new buffers) -> expected to pass; the 4096x2304 frames test the VP9 maximum size |
| D. show-existing-frame | `vp90-2-10-show-existing-frame.webm` = **1** | show_existing_frame of a frame FFmpeg's hwaccel reorders differently | FFmpeg output order artefact | duplicate_picture() -> expected to pass |

26 + 1 + 36 + 1 = 64. Groups the task brief mentioned that are **not** in the 64: odd/small sizes
(`vp90-2-02-size-08x08` ... `66x66`, `vp90-2-03-size-196..226`, `vp90-2-11-size-351x287`...: fixed-size streams,
pass with FFmpeg per Jernej; rkvdec fails 46 of the small ones, cedrus unknown until the board run), intra-only
(`vp90-2-16-intra-only.webm`: 7 intra-only frames, no key frame; passes with FFmpeg). Profile 1 (`vp91-2-04-yuv422/
yuv444`) is 4:2:2/4:4:4: the hardware is 4:2:0 only, the driver rejects the profile in s_ctrl (expected fail in
every run, like 12-bit and the vp93 vectors of VP9-TEST-VECTORS-HIGH).

## 2. What the OPi5 fix is, and what applies to cedrus

- OPi5 kernel 0606 (rkvdec vdpu381): accept frames whose 64-aligned size is <= the decoded format instead of
  rejecting them; take the reference luma size and MV offset from the format (all buffers have the format's layout).
- OPi5 kernel 2228: don't tell the hardware the previous segment map is valid after a reset (error resilient /
  resized / intra frames). **Does not apply**: cedrus_vp9.c zeroes the segment map in the probability buffer on key,
  intra-only, error-resilient and resized frames and on the first frame, so the hardware predicts segment 0 there.
- OPi5 GStreamer 0010: enable non-key-frame format changes unconditionally; a frame that fits in the CAPTURE buffers
  is decoded in place (no reallocation, only the output caps renegotiate), the GstVideoMeta describes the frame.
  **Taken** (harness/vp9-vectors/patches/0001), plus our 0002 (below).

cedrus differences found while porting (cedrus_vp9.c, Jernej's driver):
1. There was **no size check at all**: a frame of another size was written with the format's stride
   (`out = recon; out.width = ALIGN(cur_w,16)...; cedrus_dst_format_set`), a larger one overruns the buffers.
2. The hardware **derives the line stride of each reference from that reference's own width**, aligned to 64
   (`VE_DEC_VP9_SCALE1_STRIDE_ALIGN`, vendor bitfield `pri_luma_stride_align:3` in reg 0x1c, Jernej's commit
   message). So an in-place 640x360 frame in 1280-stride buffers would be read back as a reference with stride 640:
   the rkvdec rule "all buffers have the format's layout" cannot be implemented on the H616 (the 3-bit alignment
   field allows 8..1024 bytes, which cannot make ALIGN(640, A) == 1280 or ALIGN(960, A) == 1920).
3. Hence the cedrus rule: an in-place frame has the **stride of a frame of its own width** (ALIGN(w, 64); for P010
   output the P010 stride of its width; the low-2-bit plane right after its chroma rows) at the **plane offsets of the
   format**. Frames at the coded size keep exactly the previous register values (no behaviour change for every
   stream that does not resize). Whether the hardware honours the programmed primary stride for the write or derives
   it too is unknown; both give the same layout now.
4. Userspace has to learn that stride: `TRY_FMT(CAPTURE)` with the frame size now reports the layout of such a frame
   for VP9 (S_FMT and non-VP9 codecs keep deriving the size from the OUTPUT format). rkvdec's TRY_FMT already returns
   the format layout, which is what it writes, so one GStreamer rule covers both: GStreamer patch 0002 asks TRY_FMT
   on an in-place change and puts the strides into the GstVideoMeta (plane offsets unchanged).

Cross-check item for the coordinator / OPi5 session: the in-place layout contract. OPi5 0010 assumes "format stride";
our 0002 generalises it to "what TRY_FMT reports for the frame size", which is also true on their rkvdec kernel
(their TRY_FMT returns the format layout). Their GStreamer tree should take 0002 too so both boards run one plugin.

## 3. Changes

- Kernel (`wt-vp9-resize`, branch `fix/sunxi-cedrus-vp9-inter-resize`, f8be54bac): one patch
  `patches.media/h616-vdec/media-cedrus-decode-smaller-VP9-inter-frames-in-place.patch` appended to series.conf.
  cedrus_vp9.c (size check + -EINVAL for larger frames, frame stride for the primary output, 2-bit plane and P010),
  cedrus_hw.c/.h (`cedrus_dst_p010_output_set()` takes the picture layout; H.265/AVS2 pass the format as before),
  cedrus_video.c (TRY_FMT probe). Syntax-checked with the c9 tree's own gcc flags (`-Werror -fsyntax-only`, all 5
  files clean). Not built: cumul-build through the coordinator (next cN).
- GStreamer: `harness/vp9-vectors/patches/0001` (OPi5 0010 verbatim) + `0002-v4l2codecs-vp9-Take-the-strides-of-in-
  place-frames-from-TRY_FMT.patch` on gst-plugins-bad 1.28.6-1ubuntu1 (tree `build/vp9-vectors/src`, base = commit
  dd1d605 of build/gst-jpeg/src). Dev plugin built with `build-plugin.sh` (mmdebstrap unshare arm64, the gst-jpeg
  method) -> `build/vp9-vectors/out/libgstv4l2codecs.so`.
- Runner package: `run-job.sh` (host), `board-fluster.sh` (board), `check-results.py`, `make-bundle.sh`,
  `fetch-vectors.sh`, `HANDOFF.md`; job `harness/runner-queue/04-vp9-vectors.md`. Fluster 0.7.1 comes from OPi5's deb
  (`build/vp9-vectors/fluster-deb`, stdlib-only python), the vectors from storage.googleapis.com (md5-checked, 22 MB).

## 4. Expected board result (newest cN with f8be54bac + the dev plugin)

VP9-TEST-VECTORS: 302/305 (fails: vp91 x2 = profile 1, vp90-2-22-svc_1280x720_3 = group B). HIGH: 1/6
(vp92-2-20-10bit-yuv420; the rest are 12-bit or 4:2:2/4:4:0/4:4:4). Unknowns the run settles: the small sizes
(02-size 8..66 px, where rkvdec fails 46), 03-size, 11-size, 4096x2304 key frames (group C), intra-only.
If group A still fails with the fix: the remaining suspects are, in order, the hardware not honouring the programmed
primary stride for widths != format (then compare the first resized frame's md5 against libvpx with
GST_DEBUG=v4l2codecs*:6 to see which stride it used), and the GstVideoMeta strides not reaching videoconvert.

## 5. Open items (work list, not started)

- Group B (`svc_1280x720_3`): `q->supports_remove_bufs` for the CAPTURE queue, S_FMT(CAPTURE/OUTPUT) with a larger
  size while streaming for VP9, per-buffer plane offsets / 2-bit plane / P010 recon offset in `cedrus_buffer` (the
  references then live in buffers of different formats). One vector; also what real adaptive streams do (WebRTC VP9
  SVC/simulcast up-switch).
- P010 and AFBC capture with in-place resize are untested (no 10-bit resize vector exists; profile 2 vectors are
  fixed-size).
- Documentation of the TRY_FMT contract if this goes upstream (dev-stateless-decoder.rst), and agreement with the OPi5
  rkvdec side.
