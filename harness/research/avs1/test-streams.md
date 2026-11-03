# AVS1 / AVS+ test streams (2026-11-03)

No official AVS workgroup (avs.org.cn) conformance suite is publicly mirrored that I could find; fluster has no AVS1
suite. The usable public material is the FFmpeg FATE suite (with FATE reference CRCs) and the old FFmpeg samples
archive. All downloads are data only, each in its own directory under `kernel-check/dl-avs1/`, with `SHA256SUMS` and a
`README` (source URL, terms, date). Nothing downloaded was executed. Stream facts below come from our own scanner
`/tmp/avs1-scripts/avs1scan.py` (python3 -I; ES/PS/TS start-code scan + sequence/picture header parse).

## 1. Streams obtained

| dir | file | sha256 (first 16) | format | content | reference |
|---|---|---|---|---|---|
| `kernel-check/dl-avs1/fate-bunny/` | `bunny.mp4` (177752 B) | `4aef2ee60e0e1e51` | raw ES despite the name | JiZhun 0x20, L 0x40, **1280x720p**, 60 pictures (2 I, 16 P, 42 B; 3 B between P; display I0 P4 B1 B2 B3 ...), 1 slice/picture, no pseudo start codes | **FATE `cavs-bunny`** (FFmpeg `375e3df8fe5b`), 60 frames: `fate-ref-cavs-bunny.framecrc` |
| `kernel-check/dl-avs1/fate-avsplus-1080i-testcard/` | `avsplus-1080i-testcard.ts` (233684 B) | `d999a97e1e9a6dcb` | MPEG-TS | **AVS+ 0x48**, L 0x41, **1920x1080i**, 5 pictures I0 P2 B1 P4 B3, **all field coded** (2 slices = 2 fields each), **AEC**, 2 enhanced field B (pb_field_enhanced), **15 annex A pseudo start codes**, no WQ | **FATE `cavs-avsplus`** (`f80a436ffd92`), 5 frames: `fate-ref-cavs-avsplus.framecrc` |
| `kernel-check/dl-avs1/fate-cavs/` | `cavs.mpg` (2048000 B) | `e87983a123d63aea` | MPEG-PS | JiZhun 0x20, L 0x42, 720x576, old pre-final stream revision (no marker bit after time_code; our scanner finds no slice start codes in its demuxed ES: either these old pictures carry no slice start code or our PS demux is wrong; not checked further) | **FATE `cavs`**, 170 frames: `fate-ref-cavs.framecrc` (identical in FFmpeg 8.1 `a56a208b0722` and master) |
| `kernel-check/dl-avs1/ffsamples-avsfileformat/` | `AVSFileFormat.es` (589517 B) | `f4c4ba4e78e8976a` | raw ES | JiZhun 0x20, L 0x42, 320x240p, 105 pictures (7 I, 49 P, 49 B; one B between P), 1 slice/picture, 12 `00 00 02` patterns (pseudo start code candidates). Made with the AVS workgroup's AvsTranscoder 2.0 (2008 readme) | **none** |

Not downloaded: `https://samples.ffmpeg.org/AVS/stream01.avs` (150 MB MPEG-PS, JiZhun 0x20 L 0x42; no reference;
fetch only if a long-GOP 576-line test is wanted).

## 2. The FATE references

- Format: FFmpeg `framecrc` output: one line per output frame, `stream, dts, pts, duration, size, 0xADLER32`, where
  the checksum is **adler32 of the raw decoded frame**, `yuv420p`, planes Y, U, V packed, in **output (display)
  order**, cropped to the coded display size (622080 = 720·576·1.5, 1382400 = 1280·720·1.5, 3110400 = 1920·1080·1.5).
  The test decoder must print the same (adler32 is trivial to implement; own code).
- First lines: `cavs-bunny` 0xe9f1474e, 0x4d17cb21, 0x695ebe1a, ...; `cavs-avsplus` 0xbc59eeee, 0x490377c0,
  0xaca11851, 0x70251b61, 0x22be3dd4; `cavs` 0x2276bc78, 0xda1f698a, 0xb9907023, ...
- **Trust:** FFmpeg's cavs decoder is not a conformance reference. For JiZhun progressive (`bunny`) it is long
  established and bit-exactness with the hardware is expected. The AVS+ AEC/field paths and the "direct mode by
  co-located distance" fix landed on 2026-11-02 and have exactly these FATE samples as their only tests; an H616
  mismatch there could be FFmpeg's bug. A second, independent reference is desirable (§4).
- `cavs.mpg` uses a pre-standard bitstream revision; the VE (designed to the final standard) may not decode it.
  Informative only (regmap B14).

## 3. Coverage

| feature | bunny | test card | AVSFileFormat | cavs.mpg |
|---|---|---|---|---|
| I / P / B frame pictures | yes | — | yes | yes |
| P with 2 references, B direct | yes | — | yes | yes |
| field-coded pictures, field references | — | yes | — | — |
| AEC (AVS+) | — | yes | — | — |
| pb_field_enhanced B | — | yes | — | — |
| annex A pseudo start codes in slice data | — | 15 | 12 candidates | — |
| weighting quant (AVS+) | — | — | — | — |
| slice weighted prediction | ? (not scanned) | ? | ? | ? |
| 1080 lines / 60 fps throughput | — | 5 pictures only | — | — |
| reference available | FATE | FATE | none | FATE |

Gaps: WQ, slice weighted prediction, a long 1080p60/1080i stream for the "1080p@60" spec row, multi-slice pictures.
For throughput, `bunny` looped and the test card repeated are the only options so far; a longer public AVS+ broadcast
capture (DTMB/ChinaCable) would help. A local AVS1 encoder (xavs, GPL) could make WQ-free JiZhun streams but not AVS+.

## 4. Approval request: reference decoder (not built, not downloaded)

**Why.** (a) `AVSFileFormat.es` has no reference. (b) The AVS+ test-card reference comes from a one-day-old decoder
path. (c) Per-frame md5s (not only adler32) make the board comparison easier to debug.

**Option A (recommended): FFmpeg master, host only.**
- Repo `https://github.com/FFmpeg/FFmpeg`, commit `375e3df8fe5bea475a80457628e26ebcdcb757f5` (2026-11-02, contains the
  AVS1-P16 series), LGPL-2.1-or-later (no `--enable-gpl`).
- Build (normal user, no sudo, no Docker, own empty build dir, nothing installed):
  ```
  git clone https://github.com/FFmpeg/FFmpeg kernel-check/avs1-ref/ffmpeg-src
  git -C kernel-check/avs1-ref/ffmpeg-src checkout 375e3df8fe5bea475a80457628e26ebcdcb757f5
  mkdir -p kernel-check/avs1-ref/build && cd kernel-check/avs1-ref/build
  ../ffmpeg-src/configure --disable-everything --disable-doc --disable-network --disable-autodetect \
      --enable-decoder=cavs --enable-parser=cavsvideo --enable-demuxer=cavsvideo,mpegps,mpegts \
      --enable-protocol=file --enable-muxer=framecrc,framemd5,rawvideo --enable-filter=null,format,scale \
      --enable-encoder=rawvideo --enable-bsf=extract_extradata
  make -j20 ffmpeg
  ```
- Use: `ffmpeg -i X -an -f framemd5 X.framemd5` and `-f framecrc` for every stream; check that the three FATE files are
  reproduced exactly (proves our build matches upstream); keep per-frame md5s as the board reference.
- Note: `kernel-check/ffmpeg-afbc/build/ffmpeg` exists but is an aarch64 build of 8.1 (`a56a208b0722`), before the AVS+
  series, so it cannot decode the test card and runs only on the board.

**Option B (independent reference, if one is wanted): the AVS workgroup reference software (RM52J / RM52J_R1 for
JiZhun, its Guangdian extension for AVS+).** I found no public, pinned repository for it; the 2008 readme points to
avs.org.cn downloads (registration). Would need a URL from you; not pursued.

## 5. Board plan (summary; see regmap §12)

1. `bunny` I picture → IRQ, picture visible (B1, B3). 2. Full `bunny` → framecrc equals FATE (B5-B7, B12).
3. Test card → framecrc equals FATE (B4, B8, B9, B13). 4. `AVSFileFormat.es` → equals Option A md5 (B4).
5. Throughput: `bunny` looped, and the test card repeated, at 1080 lines for the 60 fps row.
