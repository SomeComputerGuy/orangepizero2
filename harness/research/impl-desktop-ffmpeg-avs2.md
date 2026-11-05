# FFmpeg AVS2 decoding through the cedrus stateless uAPI (v4l2-request hwaccel)

**Status (2026-11-05): board-tested.** `ffmpeg -hwaccel v4l2request -i x.avs2` decodes AVS2 in hardware through the
new native `avs2` decoder + `avs2_v4l2request` hwaccel: **all 17 8-bit streams bit-exact** (12 PKU md5.txt + 5
xavs2/davs2 lists, every frame), the MPEG-TS path bit-exact, 4K Main10 P010 **292/292 frames equal to the avs2dec
self-consistency run at 53.5 fps** (whole-process rate, 4K 10-bit). No kernel change. mpv is not installed on the board
(not tested; it uses the same hwaccel through libavcodec).

- **Branch:** `opiz2/avs2` in `kernel-check/ffmpeg-deb/src` (worktree `kernel-check/ffmpeg-deb/wt-avs2`), 2 commits on
  top of `opiz2/series` (Kwiboo's PR 20847 series = the former `opiz2/v4l2request-n8.1.2` tree, same final tree):
  1. `avcodec: add a native AVS2 decoder for hardware acceleration` (`libavcodec/avs2_ps.[ch]`, `avs2dec.[ch]`,
     configure/Makefile/allcodecs.c)
  2. `avcodec: add V4L2 Request API AVS2 hwaccel` (`libavcodec/v4l2_request_avs2.c`, `v4l2-stateless-avs2.h`,
     configure/Makefile/hwaccels.h, the hw_configs hook in avs2dec.c)
- **Board build:** `harness/ffmpeg/dev-build.sh kernel-check/ffmpeg-deb/wt-avs2 kernel-check/ffmpeg-deb/build-avs2`
  (static aarch64, kuapi headers); binary copied to the board as `/root/ffavs2/ffmpeg` (nothing installed system-wide).
- **Reference behaviour:** `harness/avs2dec/avs2dec.c` (board bit-exact on 17 8-bit streams, impl-avs2.md §7); the
  FFmpeg decoder is a port of its parser and DPB logic.
- **Scripts:** `harness/ffmpeg/board-avs2-ffmpeg.sh` (board run), `harness/ffmpeg/cmp-avs2-ffmpeg.py` (host compare).

## 1. Design

FFmpeg has no native AVS2 decoder (only the libdavs2 wrapper; `AV_CODEC_ID_AVS2`, the `avs2` parser and the raw
demuxer exist). The precedent for a native decoder that only decodes through a hwaccel is `av1dec.c`; the new decoder
follows it.

**`libavcodec/avs2_ps.[ch]` – header syntax.** Pseudo-start-code removal (the two bits after `00 00 02`, bit-level),
sequence header (profile/level, size, precisions, low_delay, lcu_size, weighting quantization with the three modes,
tool flags, up to 32 reference configuration sets, picture_reorder_delay, cross-slice loop filter, bcbr for profiles
0x21/0x23), intra and inter picture headers (background G/GB/S flags, DOI, temporal_id, output delay (absent for GB),
RCS inline or by index, picture structure, qp, loop filter and chroma quant offsets, WQ data index 0/1/2 with the
parametric derivation, ALF with the alf_region_distance → 16-entry region→filter map). The WQ matrices are resolved per
picture into `AVS2PictureHeader.wqm` (flat 64 when off), as the uAPI wants them.

*WQ tables and licensing.* `harness/avs2dec/avs2_wq_tables.h` is Apache-2.0 data copied from Rockchip MPP and was not
pasted into FFmpeg (Apache-2.0 is not LGPL-2.1 compatible). `avs2_ps.c` carries the normative default parameter sets,
default 4x4/8x8 matrices and the four weighting_quant_model position maps as data typed from the values documented in
`harness/research/avs2/syntax.md` §7 (the standard's defaults; the same values are in the LGPL-2.1+ Moore Threads
FFmpeg patch, in davs2 and in libawavs2). The one disputed entry, default 8x8 [3][7], is 28 (davs2 = the AVS2 reference
software lineage, MPP, every Allwinner libawavs2 build) rather than the Amlogic/Moore-Threads 112; the comment in the
file says so. No stream we have uses WQ with the default matrices, so it is not board-verified either way.

**`libavcodec/avs2dec.[ch]` – decoder (`"avs2"`, `ff_avs2_decoder`).**
- `FF_CODEC_RECEIVE_FRAME_CB`: pulls packets with `ff_decode_get_packet()`, keeps an output FIFO so that bumping can
  release several pictures per packet and at EOF (flush), one `receive_frame()` call returning one picture.
- A packet (as cut by the `avs2` parser: everything up to the next sequence header or picture start code) holds at most
  one picture, optionally preceded by a sequence header / extensions / user data and followed by user data or the
  sequence end code. The decoder scans the start codes itself; slices are codes 0x00–0x8F.
- First sequence header: `ff_set_dimensions` (coded size aligned to 8), profile/level/framerate/SAR,
  sw pix_fmt yuv420p or yuv420p10 from sample_precision, then `ff_get_format()` with `{DRM_PRIME, sw}`; without a
  hwaccel it fails with `ENOSYS` ("No hardware accelerator for AVS2 decoding is available"), so there is no software
  fallback and no garbage output. A later sequence header that changes size/precision/profile returns the packet to the
  queue until the DPB has been drained (so that the hwaccel is never re-initialised under frames the application still
  has to receive), then re-runs get_format. 4:2:0 only; field coded sequences → `AVERROR_PATCHWELCOME`.
- DPB (`AVS2Frame[32]`, each an `AVFrame` + hwaccel private RefStruct): DOI unwrap (8-bit), POC
  (`doi + output_delay - reorder_delay`, or doi when low_delay; GB pictures reuse the previous output delay), reference
  lookup by DOI among referenced pictures in RCS order, S pictures → background in slot 0, P/F with
  background_reference → background in the last slot, marking by `delta_doi_of_removed_picture`, the |ΔPOC| ≥ 128 rule,
  `refered_by_others` (never for GB), background replacement, output bumping (smallest POC when it continues the output
  sequence, when more than reorder_delay + 1 pictures wait, immediately in low-delay, or on flush/sequence end), forced
  early output when the DPB is full. Pictures with missing references before the first intra picture (open GOP start,
  e.g. the CCTV capture) are skipped silently; later missing references are concealed with the latest referenced
  picture (warning).
- Exposes to the hwaccel: `seq`, `pic` (parsed header incl. resolved WQ and ALF), `cur` (frame + POC + its own ref POC
  list), `refs[]`/`num_refs`, and `pic_data/pic_size/data_offset` (the picture header and all slices with start codes,
  the offset of the first slice).
- Registered in `allcodecs.c` after `ff_libdavs2_decoder` with the same "hwaccel hooks only, so prefer external
  decoders" rule as `ff_av1_decoder`: a build with libdavs2 keeps using the software decoder by default; `-c:v avs2`
  selects the native one. `avs2_decoder_select="avs2_parser"` (needs `avs2.o` for the frame-rate table).

**`libavcodec/v4l2_request_avs2.c` – hwaccel (`"avs2_v4l2request"`, pix fmt DRM_PRIME).**
- `init`: SEQUENCE control from the parsed header passed to `ff_v4l2_request_init()` as the init control, so that the
  driver sets the bit depth before the CAPTURE format is negotiated (NV12 for Main, P010 for Main10) and can refuse the
  size/tools early. `frame_params`: `V4L2_PIX_FMT_AVS2_FRAME`, bit depth 6 + 2·sample_precision.
- `start_frame`: `ff_v4l2_request_start_frame()`, fills SEQUENCE, PICTURE (flags, POC, data_offset, up to 7
  `v4l2_avs2_ref_pic` with the capture timestamp via `ff_v4l2_request_get_capture_timestamp(ref->f)`, POC, the ref's own
  ref-POC list, type, BACKGROUND flag), WEIGHT_QUANT (final matrices), ALF (coefficients as coded, region map,
  enables), then appends the whole picture to the OUTPUT buffer. `end_frame`: `ff_v4l2_request_decode_frame()` with the
  4 controls. `decode_slice` is a no-op (the decoder never calls it).
- `v4l2-stateless-avs2.h`: private copy of the kernel uAPI patch (pixel format, the 4 control types/IDs, flags,
  structs), guarded by `#ifndef V4L2_CID_STATELESS_AVS2_SEQUENCE` like `v4l2-stateless-mpeg4.h`, listed in
  SKIPHEADERS. `avs2_v4l2request_hwaccel_deps="v4l2_request"` (no header probe needed).

Changes outside the new files: 3 lines in configure, 3 in libavcodec/Makefile, 1 in hwaccels.h, 2 in allcodecs.c, so
the stack rebases onto any v4l2-request base.

## 2. Board results

Board: Orange Pi Zero2, image kernel `7.3.1-edge-sunxi64 #17` (2026-10-30), 2026-11-05 09:13-10:00 UTC, lock
`avs2-ffmpeg`. Binary `/root/ffavs2/ffmpeg` (dev-build of `opiz2/avs2`), streams fetched from the host over HTTP
(`kernel-check/vdec-serve/avs2/`), decoded from `/dev/shm`. Command per stream (`harness/ffmpeg/board-avs2-ffmpeg.sh`):

```
ffmpeg -hwaccel v4l2request -i X.avs2 -fps_mode passthrough -pix_fmt yuv420p -f framemd5 -   # per frame
ffmpeg -hwaccel v4l2request -i X.avs2 -fps_mode passthrough -pix_fmt yuv420p -f md5 -        # whole stream
ffmpeg -benchmark -hwaccel v4l2request -hwaccel_output_format drm_prime -i X.avs2 -f null -  # rate (rtime)
```

Without `-hwaccel_output_format` the CLI downloads the DRM_PRIME frames itself (NV12 → yuv420p is a lossless plane
repack), so the md5 of the yuv420p rawvideo stream is directly comparable with the PKU `md5.txt` (I420, output order)
and the per-frame md5s with the avs2dec board run and the davs2 lists. Logs: `kernel-check/avs2-board/ffmpeg-8bit.log`,
`ffmpeg-out8/`, `ffmpeg-misc.log`, `ffmpeg-test1.log`.

### 2.1 8-bit streams: all 17 bit-exact (whole-stream md5 = md5.txt, every frame = avs2dec / davs2)

| stream | rc | frames | md5 vs md5.txt | per-frame md5 vs avs2dec (PKU) / davs2 (main-*) | fps (frames/rtime, DRM_PRIME, no download) |
|---|---|---|---|---|---|
| BasketballPass_416x240_50_ai | rc 0 | 100 | MATCH | MATCH 100/100 | 1282.1 |
| BasketballPass_416x240_50_ld | rc 0 | 100 | MATCH | MATCH 100/100 | 1265.8 |
| BasketballPass_416x240_50_ra | rc 0 | 100 | MATCH | MATCH 100/100 | 1449.3 |
| BQMall_832x480_60_ra | rc 0 | 150 | MATCH | MATCH 150/150 | 724.6 |
| BQSquare_416x240_60_ai | rc 0 | 100 | MATCH | MATCH 100/100 | 885.0 |
| BQSquare_416x240_60_ld | rc 0 | 100 | MATCH | MATCH 100/100 | 1219.5 |
| BQSquare_416x240_60_ra | rc 0 | 100 | MATCH | MATCH 100/100 | 1351.4 |
| ParkScene_1920x1080_24_ra | rc 0 | 200 | MATCH | MATCH 200/200 | 181.2 |
| PartyScene_832x480_50_ra | rc 0 | 200 | MATCH | MATCH 200/200 | 684.9 |
| RaceHorses_416x240_30_ai | rc 0 | 100 | MATCH | MATCH 100/100 | 1030.9 |
| RaceHorses_416x240_30_ld | rc 0 | 100 | MATCH | MATCH 100/100 | 1204.8 |
| RaceHorses_416x240_30_ra | rc 0 | 100 | MATCH | MATCH 100/100 | 1408.5 |
| main-1080p-ra | rc 0 | 30 | n/a | MATCH 30/30 | 154.6 |
| main-1080p-ldp | rc 0 | 30 | n/a | MATCH 30/30 | 198.7 |
| main-1080p-tid | rc 0 | 30 | n/a | MATCH 30/30 | 159.6 |
| main-1080p-lf | rc 0 | 30 | n/a | MATCH 30/30 | 158.7 |
| main-2160p-ra | rc 0 | 20 | n/a | MATCH 20/20 | 28.9 |

The fps column is frames / `rtime` of a whole `ffmpeg` run including start-up and the HTTP-free file read, so the
small streams (100-200 pictures of 416x240) only say "far above real time"; 1080p ParkScene (200 pictures) gives
181 fps against avs2dec's 198 fps VE-bound measurement, and main-2160p-ra has only 20 pictures (29 fps including
start-up). The 4K rate was measured on the 292-picture 10-bit stream, §2.3.

### 2.2 Containers, failure paths

| test | result |
|---|---|
| MPEG-TS: `BQMall_832x480_60_ra.ts` (made on the host with `ffmpeg -c copy -f mpegts`, stream_type 0xD2), read by the board over HTTP | 150 frames, whole-stream MD5 `f81cf1cb…` = md5.txt (bit-exact through the TS demuxer + avs2 parser) |
| No hwaccel: `ffmpeg -i X.avs2 -f null -` | "No hardware accelerator for AVS2 decoding is available", no frames, no software decode |
| Truncated stream (`err-trunc.avs2`), 40 corrupted slice bytes (`err-corrupt.avs2`) | clean termination, no hang (4 cedrus "frame processing timed out" on the corrupted pictures); the next stream (BQSquare_ra) decodes bit-exact |
| MKV `test1_avs2.mkv` (xatabhk, 854x480 Main, LCU 32, Big Buck Bunny, 2096 pictures; sequence header in CodecPrivate and repeated in-band at every I picture) | demuxes and decodes, but **the VE fails on this stream**: cedrus "frame processing timed out" (2 s each) from picture ~174 on, every later picture times out, 31 frames in 150 s. **The reference `avs2dec` fails on the same elementary stream** (decode errors at doi 71/72, then timeouts, 0 frames in 150 s), so this is a cedrus/VE issue with the stream, not an FFmpeg one; the VE recovers when the process exits (the next stream decodes bit-exact). Differences from the 17 verified streams: width 854 (not a multiple of 8/16), 8-bit with LCU 32, many 25-60 byte B pictures. Kernel-side follow-up (`kernel-check/avs2-board/ffmpeg-test1.log`, ES at `kernel-check/vdec-serve/avs2/test1.avs2`). |
| `ffprobe` of the streams | works (sequence header parsed by the avs2 parser; the decoder is only used with `-hwaccel`) |

A note on the `avs2` probe: `avformat_find_stream_info()` opens a decoder without a hw device, so one
"No hardware accelerator for AVS2 decoding is available" line is printed per run (the AV1 native decoder behaves the
same way); it does not affect the decode.

### 2.3 10-bit (cctv4k-10bit, 3840x2160 Main10, 292 pictures, P010 capture)

The driver picks P010 for the 10-bit sequence (the hwaccel passes bit depth 10 in frame_params and the SEQUENCE control
at init). `ffmpeg -hwaccel v4l2request -i cctv4k-10bit.avs2 -fps_mode passthrough -pix_fmt yuv420p10le -f framemd5 -`
(P010 → yuv420p10le is a lossless repack, the same 16-bit LE layout avs2dec writes):

| check | result |
|---|---|
| per-frame md5 vs avs2dec P010 run (`kernel-check/avs2-board/out10/cctv4k-10bit.p010-a.txt`, impl-avs2.md §7.3) | **292/292 frames identical** (the 4 open-GOP B pictures before the first I are skipped by both) |
| rate, `-benchmark -hwaccel_output_format drm_prime -f null -` | rtime 5.456 s for 292 pictures = **53.5 fps** whole process (two runs, 5.4-5.5 s); avs2dec: 58.5 fps VE-bound, 40 fps pipeline |
| hwdownload path (framemd5 run, 4K P010 copy through the CPU) | 85 s for 292 frames (3.4 fps; the download, not the decode) |

10-bit stays "self-consistent, not reference-verified" (impl-avs2.md §5b/§7.3); this run adds that the FFmpeg path
reproduces avs2dec's output exactly on kernel #17.

## 3. Open items

1. **`test1_avs2.mkv` (854x480, LCU 32) hangs the VE** with both decoders (§2.2): kernel-side (cedrus AVS2) debugging
   needed: width not a multiple of 8/16, LCU 32 at 8 bits, or the tiny B pictures. Bisect by re-encoding Big Buck Bunny
   with xavs2 at 854x480 / 856x480 with LCU 32 and 64 (`harness/avs2dec/make-refs.sh` has the encoder set-up).
2. **Probe noise:** `avformat_find_stream_info()` opens the decoder without a hw device, so one "No hardware accelerator
   for AVS2 decoding is available" line is printed per run (same as the native AV1 decoder). Could be silenced by
   returning `AVERROR(ENOSYS)` quietly on the first attempt, at the cost of a less clear message for real failures.
3. **Builds with libdavs2:** the native decoder is registered after libdavs2, so such a build picks the software decoder
   unless `-c:v avs2` is given (also how the AV1 decoders behave). Documented, not changed.
4. **Not covered by any stream (as for avs2dec):** weighting quantization (the wq-* streams decode to the same pictures
   with and without WQ), background G/GB/S pictures, field coding, DOI/POC wrap beyond 511, widths 129-192. The default
   WQ 8x8 entry [3][7] = 28 (davs2/MPP/libawavs2) vs 112 (Amlogic/Moore Threads) remains unresolved against the spec.
5. **Timestamps for raw `.avs2` input:** the raw demuxer stamps packets in decode order; the decoder outputs in POC order
   with the packet's pts, so `-fps_mode passthrough` is needed for frame-exact output from raw ES (containers with real
   pts, TS/MKV, are fine). The `avs2` parser does not compute output_picture_number; adding it (or has_b_frames based
   reordering) is a follow-up.
6. **Rebase:** the stack is on `opiz2/series` (Kwiboo PR 20847 series); only 9 lines touch existing files. The desktop
   agent exports the two commits as patches 03xx in `patches/ffmpeg`.
7. mpv: not on the board image; `mpv --hwdec=v4l2request-copy` (or drm) should work through the same hwaccel; untested.
