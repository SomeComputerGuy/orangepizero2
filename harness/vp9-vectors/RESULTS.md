# cedrus VP9: the 64 failing conformance vectors (task state, 2026-11-05)

Task: docs/status.md item 9, "port OPi5's VP9 resize fix (0606/2228 + GStreamer 0010); cedrus VP9 still fails 64
vectors". Code agent, no board access. Kernel branch `fix/sunxi-cedrus-vp9-inter-resize` (armbian-build, pushed to
`fork`, commit f8be54bac, off test-cumulative aa6e29312 = c9; **merged as cumulative c10**, so c10..c14 contain it).
Runner jobs: `04-vp9-vectors` (done, harness bug, see §6) and the rerun `harness/runner-queue/10-vp9-vectors.md`.
Group B (inter-frame upsize, §7): kernel branch `fix/sunxi-cedrus-vp9-inter-upsize` (armbian-build **7897dec08**, off
test-cumulative 8140b4eeb = c16, pushed to `fork`, **not merged**: the coordinator merges), runner job
`harness/runner-queue/13-vp9-upsize.md` (DEV, blocks itself until the newest cumulative kernel contains 7897dec08).

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
| B. inter-frame upsize | `vp90-2-22-svc_1280x720_3.ivf` (one key frame 320x180, then inter frames 640x360, 1280x720, 320x180, 640x360, ... 60 frames, 20 per size) = **1** | frames larger than the CAPTURE buffers, references smaller (2x and 4x upscaling) | same reallocation issue; Jernej's "references of a different size" case | **Implemented** (7897dec08, §7): `VIDIOC_REMOVE_BUFS` + S_FMT while streaming + per-buffer layouts in cedrus; GStreamer 1.28 takes its REMOVE_BUFS path on its own. To be confirmed on the board (job 13) |
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

- Group B is implemented (§7) but unmeasured: job 13 after the coordinator merges 7897dec08 into test-cumulative.
- 10-bit resize (in place or upsize): `VE_DEC_VP9_FIRST_OUT_OFFSET` (low-2-bit plane offset) is one register,
  programmed for the current frame; whether the hardware derives it for references of another size as it derives
  their stride is unknown. P010 and AFBC capture with resize are untested (no 10-bit resize vector exists; profile 2
  vectors are fixed-size).
- Documentation of the TRY_FMT contract if this goes upstream (dev-stateless-decoder.rst: the REMOVE_BUFS resize
  sequence is not described there either; hantro and now cedrus implement it), and agreement with the OPi5 rkvdec
  side (rkvdec has no `vidioc_remove_bufs` and refuses S_FMT while busy, so svc_1280x720_3 fails there too).
- The 64-buffer CAPTURE limit covers three overlapping GStreamer buffer sets (14 each); a stream that grows four times
  within a few frames would hit it (CREATE_BUFS -ENOBUFS, decoder error, no overrun).

## 6. Board runs

### Job 04 (2026-11-05 20:17-20:31 UTC, kernel c13 = test-cumulative 626dff92e, #14; contains f8be54bac)

Reported FAIL with 0/305, but the decoder was fine; two package bugs (both fixed, 2026-11-05 21:00):
1. `check-results.py` only knew the emoji and the long words (`Success`...). fluster 0.7.1 with `-ne -so` writes the
   plain-text tokens `OK/KO/ER/TO/NS` into the summary, so every `OK` row counted as a failure ("ER" in the runner
   summary was the 5 expected HIGH errors plus 209 unparsed `OK`s). Now mapped (`TOKENS`).
2. The stall watchdog in `run-job.sh` watches the ssh stdout, but `board-fluster.sh` sent every fluster line to
   `out/<c>.log` only, so a chunk longer than 300 s was killed: c3 (97 vectors, the 36 key-frame resize ones take
   ~11 s each) died after 51 vectors, all Success. Now every fluster line is echoed to stdout with a timestamp
   (`python3 -u`, `tee`, `grep --line-buffered`), and c3 is split into c3 (05..14, 59 vectors, ~8 min) and c5
   (15..22 + vp91, 38 vectors).
   Also: CHECK 5 matched "iommu: **Default** domain type" via `iommu.*fault` (now `\bfault`); the fluster rc was the
   exit status of the pipe; `kernel.txt` did not record which cN ran.

Real numbers of job 04 (`logs/job04-c13/check-fixed-parser.txt`, re-read with the fixed parser):

| group | success | total |
|---|---|---|
| quantizer (00) | 64 | 64 |
| sharpness (01) | 7 | 7 |
| size-02 (8..66 px) | 71 | 71 |
| size-03 (196..226 px) + deltaq + 352x288 | 65 | 65 |
| 02-size-lf-1920x1080 | 1 | 1 |
| c3 partial (`out/c3.log`, no summary): 05-resize, 06..13, 14-resize-10frames x14, 14-resize-fp-tiles x14 | 51 | 51 |
| HIGH: vp92 10-bit 4:2:0 | 1 | 1 |
| HIGH: 12-bit, vp93 4:2:2/4:4:4 (expected: caps negotiation fails, gst-launch exit 1 -> ER) | 0 | 5 |

So on c13: 208/208 of the summarised profile-0 vectors + 51/51 of c3's first half, incl. `vp90-2-05-resize.ivf`
(group A, inter-frame downsize: **the fix works on at least this vector**) and all 28 key-frame resize vectors reached
(group C, up to the 16-tile 4K-wide ones). dmesg clean (no timeouts, faults, Oops). The small sizes 8..66 px all pass
(rkvdec fails 46 of them). Not yet measured: the 24 `21-resize_inter_*`, 18-resize, 15..20, 22-svc, vp91 (chunk c5)
and 14-resize-fp-tiles 2-16 .. 8-4 (rest of c3).

Rerun: job `harness/runner-queue/10-vp9-vectors.md` on c14 (0324a5d4b), with the pre-flight (`pre` chunk: fluster on
vp90-2-00-quantizer-00.webm + a direct `gst-launch` with GST_DEBUG=2 into `out/pre.gst.txt`; not OK -> BLOCKED with
the reason, no chunks) and CHECK 0 (kernel >= c10 and pre-flight OK). Bundle rebuilt (`make-bundle.sh`,
board-fluster.sh changed; plugin unchanged).

## 7. Group B: inter-frame upsize (2026-11-05 22:00, code agent vp9-upsize, no board access)

Kernel branch `fix/sunxi-cedrus-vp9-inter-upsize` = armbian-build **7897dec08** (one patch
`patches.media/h616-vdec/media-cedrus-VP9-resize-the-CAPTURE-queue-while-streaming.patch` appended to series.conf,
worktree `wt-vp9-upsize`, pushed to `fork` only). Syntax-checked against the c16 tree with the kernel's own flags
(`-Werror -fsyntax-only`, all 14 cedrus .c files), checkpatch `--strict` clean, `patch --dry-run` applies on the c16
tree. Not built: cumul-build through the coordinator.

### Design (V4L2 stateless rules, what hantro/rkvdec/GStreamer do)

- dev-stateless-decoder.rst only describes the resolution change with STREAMOFF + REQBUFS(0), which frees the
  references. The alternative that upstream added for exactly this (VP9/AV1 inter-frame growth) is `VIDIOC_REMOVE_BUFS`
  (vidioc-remove-bufs.rst; `V4L2_BUF_CAP_SUPPORTS_REMOVE_BUFS` reported by REQBUFS/CREATE_BUFS when the driver sets
  `vidioc_remove_bufs`): buffers in DEQUEUED state can be removed one by one while streaming, and CREATE_BUFS adds
  buffers of the current format (vb2 reuses the free indices, `max_num_buffers`). The driver must then accept the new
  size while streaming: hantro (`hantro_set_fmt_out`) accepts S_FMT(OUTPUT) while streaming as long as the coded
  pixelformat stays, and S_FMT(CAPTURE) at any time for decoders. rkvdec (OPi5) has neither: no `vidioc_remove_bufs`,
  `-EBUSY` on S_FMT while busy, so the svc vector fails there too (their 0606 covers smaller frames only).
- GStreamer 1.28 v4l2codecs already implements the client side (`gst_v4l2_decoder_has_remove_bufs`): on an inter frame
  whose size changes, `new_picture()` calls `negotiate()` **without streaming off**: `reset_allocation()` (the free
  buffers of both allocators are REMOVE_BUFS'd at once, the outstanding ones - references in the DPB, frames
  downstream, requests in flight - when their GstMemory is released and the allocator is disposed), S_FMT(OUTPUT) with
  the new coded size, S_EXT_CTRLS(VP9_FRAME), ENUM_FMT/TRY_FMT probes, S_FMT(CAPTURE), then `decide_allocation()` ->
  CREATE_BUFS(OUTPUT) x (1 + render delay) and CREATE_BUFS(CAPTURE) x (8 + min + 4), each with G_FMT's sizeimage; no
  STREAMON (already streaming). Our 0001 (OPi5 0010) keeps that path for frames that do not fit and decodes smaller
  frames in place; 0002 is unaffected. **No GStreamer change is needed** for the upsize: the plugin only has to see the
  capability.
- Kernel side, therefore (the patch):
  1. `.vidioc_remove_bufs = v4l2_m2m_ioctl_remove_bufs` (REQBUFS/CREATE_BUFS report the capability for every codec; the
     ioctl itself is codec-agnostic: it frees DEQUEUED buffers).
  2. `cedrus_s_fmt_vid_out()`: a new coded size of the same codec while the queues have buffers is accepted for VP9
     (`cedrus_resizes_while_busy()`): `src_fmt` is replaced, the CAPTURE format follows the size and **keeps its pixel
     format** (the generic path resets it to the first valid one); codec, queue flags unchanged.
     `cedrus_s_fmt_vid_cap()`: accepted while busy for VP9 if the pixel format stays. The other codecs keep the old
     rules, because they take the layout of their references from `ctx->dst_fmt`.
  3. Per-buffer layout: `cedrus_buf_prepare()` records the CAPTURE format in `struct cedrus_buffer.fmt` (a snapshot at
     QBUF/PREPARE_BUF time, outside the codec union). `cedrus_vp9_setup()` takes the layout of the **destination buffer**
     from that snapshot (so frames whose requests were queued before the S_FMT are still written in the layout
     userspace prepared them with and knows from its GstVideoMeta), checks the frame fits that buffer (else -EINVAL as
     before), and reads each reference through its own snapshot (`cedrus_vp9_frame_addr()`, new
     `cedrus_dst_frame_addr_in(fmt, buf, plane)` / `cedrus_dst_frame_fmt_of(fmt)` in cedrus.h; the P010 hidden-surface
     offset comes from the buffer's format too). The reference line stride is derived by the hardware from the
     reference's width (f8be54bac), so only the plane offsets had to become per-buffer. In-place (smaller) frames keep
     the f8be54bac rule: frame stride, buffer's plane offsets; TRY_FMT unchanged.
  4. `cedrus_dst_p010_output_set(ctx, buf, buf_fmt, pic)`: buffer layout and visible picture separately (H.265/AVS2 pass
     the format twice).
  5. `dst_vq->max_num_buffers = CEDRUS_MAX_CAPTURE_BUFFERS (64)`: the svc vector grows twice within three frames, so
     three GStreamer buffer sets (14 each, the 320x180 set is still referenced when the 1280x720 set is created) can
     coexist, more than the default 32 (CREATE_BUFS would fail with -ENOBUFS).
- The frame-size sequence of the vector (ffprobe): I 320x180, then P 640x360, P 1280x720, P 320x180, P 640x360, ...
  (60 frames, 20 per size). So after the two upsizes every later frame fits in the 1280x736 buffers and is decoded
  in place (f8be54bac path, GstVideoMeta strides from TRY_FMT), while referencing frames of all three sizes in buffers
  of two layouts. Scale factors: the hardware step field is 1/16 pel with 5 bits (equal size = 16, 2x larger ref = 32
  is the VP9 maximum), 2x/4x smaller references give 8/4; the vendor Vp9RefFramSize() encodes them the same way.

### Test package

`harness/vp9-vectors/run-upsize.sh` + `HANDOFF-upsize.md`, job `13-vp9-upsize.md` (DEV): refuses to touch the board
unless the newest cumulative kernel contains 7897dec08 (git merge-base in wt-cumulative; BLOCKED otherwise), then
run-job.sh with `OUT=logs/upsize JOB=upsize` and the new board-fluster.sh chunks u1 (svc_1280x720_3 + the 26
downsize vectors, 27) and u2 (25-vector profile-0 regression subset: one or two per feature group incl. 1920x1080,
8x8, intra-only, show-existing, two key-frame resize vectors, svc_1280x720_1). check-results.py got a job argument
(`full` | `upsize`), the full job's CHECK 4 now expects svc_1280x720_3 to pass on a kernel that contains 7897dec08
(same git test). Bundle rebuilt (board-fluster.sh changed; plugin unchanged). The u1/u2 selectors were verified
against the suite JSON (27/25) and the checker against synthetic OK/KO summaries (PASS; CHECK 2 FAIL on a KO).

Expected: CHECK 2 Success if the hardware upscales references 2x and 4x as the vendor library programs it. Failure
modes: ER with dmesg "VP9 frame 640x360 larger than its 320x192 CAPTURE buffer" = GStreamer did not take the
REMOVE_BUFS path (check `out/env.txt`: the dev plugin must be the one loaded, and `GST_DEBUG=v4l2codecs*:6` would show
"remove buffers"); ER with "VIDIOC_S_FMT failed: Device or resource busy" = the kernel refused the resize (wrong
kernel); KO (wrong md5) with 3/4 passing = scaling or layout of the upscaled references (compare the 640x360 frame 1
md5 against libvpx; the first suspect is the reference chroma offset of the 320x180 buffers, 320*192).
