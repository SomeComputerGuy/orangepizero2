# H616 VE: 10-bit 4K throughput on the Orange Pi Zero2 (Cedrus), measured

Date: 2026-11-02/03. Board: Orange Pi Zero2 (H616, 1 GB DDR3-1440 x32), VE 600 MHz, VDD-SYS ≥ 0.89 V
(GPU devfreq min 504 MHz on the old image, 900 mV DT floor on the new image, integration a2371fdc1).
Plan followed: `harness/research/vdec-main10-web.md` §7. Earlier state: `harness/research/impl-vdec.md` §9.
Tags: **[M]** measured here, **[I]** inference, **[U]** unverified.

## 0. Answer

**4K60 10-bit decode is reachable on this board, with the VE's AFBC reconstruction.** [M]

| Stream (4K, 600 frames, ~40 Mbit/s) | Before (P010, linear hidden recon) | **P010, AFBC hidden recon (new patch)** | Native AFBC10 capture (`AS01`) |
|---|---|---|---|
| H.265 Main10 2160p60 | 23.9 fps | **60.3 fps** VE-bound, 57.3 FFmpeg pipeline, md5 PASS `e57bc497…` | **83.9 fps** VE-bound, 79.1 pipeline |
| VP9 Profile 2 2160p60 | 35.6 fps | **57.1 fps** VE-bound, 50.8 pipeline, md5 PASS `1e40c2b3…` | **84.2 fps** VE-bound, 73.6 pipeline |

- **The spec rows (H.265 MP10 4K@60, VP9 P2 4K@60) are met by the decoder with AFBC output** (84 fps, 40 % headroom), which is also
  the vendor's own 4K path on H616 and Jernej's measured LibreELEC number (63–84 fps). Showing it at 60 Hz needs DE33 AFBC scanout
  (not in our kernel; plan in `harness/research/vdec-perf/de33-afbc-plan.md`, §6 below).
- **For generic userspace (P010, e.g. GStreamer), a new series patch makes H.265 Main10 4K exactly 60 fps (VE-bound) and VP9 P2 57 fps**,
  bit-exact. [I] This is likely close to the maximum for P010 here: what is left over native AFBC is the 25 MB/frame linear P010 write.
- **Root cause of the old slowness [M]: motion-compensation reads from a linear reference surface**, not DRAM bandwidth and not the
  write side. The reference-read port (MBUS VE1 / IOMMU master 2) moves 3.2× the data of an AFBC reference and misses the
  IOMMU micro TLB half of the time, but disabling the IOMMU recovers only 34 → 40 fps for 8-bit linear (tiled: 78), so the
  access pattern dominates and the TLB adds ~15 % (§3 item 2). The research doc's TLB hypothesis is only partly right.

## 1. Method
- Decoder client: Jernej Škrabec's FFmpeg fork, branch `v4l2request-mpeg4`, commit `a56a208b07228c7a5085cead47b0552d41c6f2a9`
  (pinned with `git ls-remote` 2026-11-02; `git archive HEAD | sha256sum` = `2314da66c1ec5484c4209a98b0bc9184a66dc4049129962cdfc4bc6e4fadfe98`),
  plus a 7-line local change: env `V4L2REQUEST_PIXFMT=<fourcc>` forces the CAPTURE format (`vdec-perf/ffmpeg-pixfmt-override.diff`).
  The fork otherwise takes the driver's G_FMT default, which is P010 for 10-bit (the P010 entry precedes AFBC in `cedrus_formats[]`).
  Cross-built on the host, static, `--disable-autodetect --enable-libdrm --enable-libudev --enable-v4l2-request`, with a
  sysroot of the board's libdrm 2.4.134 / libudev 261 headers+libs and our kernel's uapi (`vdec-perf/build-ffmpeg.sh`, 2 min with ccache).
  Binary sha256 `9542639f6f049d9b58da237f0d2e0aa0e6e6b354194c7f8a2ac4e6b9fb16cf23`. Runs as
  `ffmpeg -hwaccel v4l2request -hwaccel_output_format drm_prime -i F -f null -`.
- Rate: `ve-busy-cmd.sh` (ftrace `cedrus_device_run`→`cedrus_irq`, = VE-bound fps) and wall time (= pipeline fps, file on SD, page-cached).
- Bit-exactness: `ffmpeg -hwaccel v4l2request -i F -pix_fmt p010le|nv12 -f md5 -` (frames downloaded from the capture buffer) against the
  host software-decode references in `kernel-check/vdec-streams/*.p010le.md5|*.nv12.md5` (same refs as impl-vdec §9).
  For the old P010 path this gives the known `e57bc497…`, so the method is sound.
- Counters (`vdec-perf/perf-run.sh`, per 600-frame run):
  - VE top `0x20 dram_read_cntr` / `0x24 dram_write_cntr` (enable bit 31), read in the driver around every job (debug param
    `dbg_cnt`, sums in `dbg_rd/dbg_wr`). **Unit = 8 bytes** [M]: the P010-with-AFBC run writes exactly 3,110,400 units more
    per job than native AFBC = 24.88 MB = one 4K P010 picture. Select bits VE_MODE[9:8] left 0. `0x10/0x14` stayed 0.
    These counters do not see the VE1 (reference-read) port: they are identical for tiled and linear 8-bit.
  - MBUS PMU (0x047fa09c bit 0 enable; 0xa0+4n): n=0 CPU, 3 VE, 10 VE1, 11 IOMMU, 13 total. Unit not calibrated (relative only);
    the "total" counter reads 0 in most runs, so it is unreliable.
  - IOMMU PMU (0x030f0200 enable, 0x210 clear; access/hit 0x230+0x10·m, m 7/8 at 0x2d0/0x2e0; total latency 0x300+0x10·m).
    VE masters: 3 (`iommus = <&iommu 3>` first) and 2.
- Kernels: debug builds of `feat/sunxi-h616-vdec-spec` from `kernel-check/work-vdec/linux-7.3.1` with debug-only module params
  (`vdec-perf/debug-dbg3.diff`: `dbg_p010_tiled` 0 linear / 1 tiled 32x32 / 2 tiled 128x32 / 3 AFBC hidden recon, counters, `dbg_mode_or/clr`,
  `dbg_mod_rate`). #7 "dbg3" on the old image; #8 "dbg4" = series + the new patch + counters only, on the new image (integration a2371fdc1).

## 2. Raw results
### 2.1 Counters (dbg3, old image; dbg4 runs reproduce every number to <0.1 %)
Per frame (600-frame 4K runs). VE rd/wr = VE top counters × 8 B (master-3 port only). MBUS units uncalibrated (thousands per frame).
IOMMU columns: accesses per frame / micro-TLB hit rate / total latency ÷ accesses (cycles, unit undocumented).

| run | VE rd MB | VE wr MB | MBUS VE k | MBUS VE1 k | MBUS IOMMU k | IOMMU m2 (ref reads) | IOMMU m3 |
|---|---|---|---|---|---|---|---|
| H.265 8-bit tiled (79.7 fps) | 13.6 | 14.9 | 20.7 | 21.1 | 0.45 | 338k / 91.8 % / 7.1 | 563k / 96.8 % / 3.3 |
| H.265 8-bit linear (33.9) | 13.4 | 14.9 | 20.7 | **40.4** | **8.85** | **1276k / 55.8 % / 167.7** | 563k / 98.8 % / 3.5 |
| Main10 P010, linear recon (23.9) | 16.9 | 42.9 | 48.1 | **47.4** | **19.62** | **1501k / 50.5 % / 171.4** | 1049k / 42.3 % / 13.0 |
| Main10 P010, tiled32 recon (49.4) | 17.1 | 42.9 | 48.1 | 28.0 | 3.21 | 553k / 90.2 % / 23.4 | 1049k / 80.6 % / 6.8 |
| Main10 P010, tiled128 recon (47.3) | 19.3 | 42.9 | 48.1 | 32.3 | 3.17 | 517k / 90.0 % / 29.7 | 1049k / 80.7 % / 6.5 |
| Main10 P010, AFBC recon (60.3) | 9.9 | 29.9 | 38.0 | 14.8 | 0.97 | 148k / 89.4 % / 3.5 | 666k / 96.5 % / 4.3 |
| Main10 native AFBC (83.6) | 9.9 | **5.1** | 13.7 | 14.8 | 0.51 | 148k / 89.4 % / 3.5 | 278k / 96.1 % / 3.4 |
| VP9 P2 P010, AFBC recon (57.1) | 8.1 | 32.5 | 42.6 | 8.4 | 5.20 | 75k / 84.0 % / 4.1 | **703k / 59.0 % / 14.3** |
| VP9 P2 native AFBC (84.2) | 8.1 | 6.3 | 17.1 | 8.4 | 0.54 | 75k / 84.5 % / 3.9 | 295k / 95.5 % / 3.9 |
| VP9 P0 tiled (74.6) | 13.0 | 15.6 | 22.1 | 18.2 | 0.35 | 291k / 95.5 % / 16.2 | 555k / 97.5 % / 3.9 |

Raw lines: `vdec-perf/logs/counters-run1.txt` (dbg3), `logs/round-a2-dbg4.txt` (dbg4).

### 2.2 P010 hidden-reconstruction layouts, H.265 Main10 4K (dbg3)
| hidden recon | VE-bound fps | pipeline fps | md5 |
|---|---|---|---|
| 0 linear NV12 + 2-bit (old) | 23.9 | 23.4 | PASS `e57bc497…` |
| 1 tiled 32x32 NV12 + 2-bit | 49.4 | 47.4 | PASS `e57bc497…` |
| 2 tiled 128x32 NV12 + 2-bit | 47.3 | 45.2 | not run (run aborted by the reflash) |
| 3 AFBC10 | 60.3 | 57.4 | PASS (dbg4 patch, §2.3) |
| native AFBC10 (no P010) | 83.6 | 78.2 | n/a (compressed) |

### 2.3 New-image round (dbg4: series + AFBC-recon patch)
Kernel #8 dbg4, new image, VDD-SYS 900 mV, VE 600 MHz. FFmpeg unless noted.

| run | VE-bound fps | pipeline fps | md5 |
|---|---|---|---|
| H.265 Main10 → P010 (AFBC recon) | **60.3** | 57.3 | **PASS** `e57bc497604122d3b234a029d22ed5d9` |
| H.265 Main10 → AFBC10 | 83.9 | 79.1 | n/a |
| VP9 P2 → P010 (AFBC recon) | **57.1** | 50.8 | **PASS** `1e40c2b3f795ec2a9358631292644c85` |
| VP9 P2 → AFBC10 | 84.2 | 73.6 | n/a |
| H.265 8-bit → NV12_32L32 / NV12 | 79.2 / 34.2 | 75.8 / 33.4 | NV12 **PASS** `3bbb2852…` |
| VP9 P0 → NV12_32L32 | 74.6 | 66.7 | NV12 **PASS** `9368ae9b…` |
| H.264 High 4K30 → NV12 | — | — | **PASS** `2f51f88f…` |
| GStreamer `v4l2slh265dec ! fakesink` Main10 (P010) | 61.0 | **32.9** | – |
| GStreamer `v4l2slvp9dec ! fakesink` P2 (P010) | 58.6 | 51.5 | – |

The AFBC-reconstruction P010 md5s prove more than the P010 copy: every P/B picture predicts from references that the VE read
back from AFBC, so a lossy or misaddressed AFBC loop would have broken the whole-stream md5. This is the only bit-exactness
evidence for the VE's AFBC path we have (native AFBC capture itself cannot be md5-checked without a decompressor). [M/I]

GStreamer's H.265 pipeline stays at 33 fps although the VE needs only 16.4 ms per picture: the VE is idle half of the time. Not
investigated (it is a userspace issue: buffer pool depth / CPU copy in GStreamer 1.28.6; FFmpeg's pipeline reaches 57). [U]

## 3. Analysis
1. **Linear surfaces cost on the reference-read side, not the write side.** VE write bytes are identical for tiled and linear
   8-bit (14.9 MB/frame) and so are the VE-port MBUS counts. What changes is the VE1 port, which carries the motion-compensation
   reads: 1.9× the MBUS traffic for linear, 3.8× the IOMMU accesses, TLB hit rate 92 → 56 %, latency/access 7 → 168. [M]
2. **The IOMMU is a minor part of it.** With `iommu.passthrough=1 cma=320M` (identity domain: IOMMU disabled, buffers
   physically contiguous from CMA) 8-bit linear H.265 goes only from 33.9 to **39.6 fps** (tiled 78.2), H.264 linear 28.6 → 29.3
   (tiled 41.4). The VE1 traffic doubling is the same with and without the IOMMU (24.2 M vs 12.7 M units). So the linear
   MC fetch pattern itself (over-fetch, DRAM row misses) is the main cost; TLB misses add ~15 %. The research doc's TLB
   hypothesis (§2 there) is **only partly confirmed**. [M]
   (The P010 passthrough A/B could not run: 8 × 42 MB contiguous buffers failed from a fragmented 320 MB CMA,
   "dma alloc of size 42119168 failed".)
3. **P010 = linear recon + secondary P010 write; the recon was the expensive part.** Tiled hidden recon doubles the rate
   (23.9 → 49.4), AFBC recon gives 60.3. AFBC halves the reference reads again (VE1 14.8 k vs 28.0 k) and the VE port
   writes only 5.1 MB of compressed recon. What remains over native AFBC (83.6) is the 24.9 MB P010 write itself
   (29.9 − 5.1 MB written; 4.7 ms/frame).
4. **VP9 P010 is limited by the secondary write.** Its master-3 (write) TLB hit rate is 59 % (H.265: 96 %): the VP9 engine emits the
   P010 copy in an order that misses the TLB. Not fixable from the driver as far as known. [M/I]
5. **DRAM bandwidth is not the limit.** Native AFBC10 at 84 fps moves ~15 MB/frame through the VE port (≈1.25 GB/s) against
   5.76 GB/s theoretical; P010 at 60 fps ≈ 2.4 GB/s. [I from counters; unit of MBUS counters not calibrated]

## 4. Side knobs
- `VE_MODE` bit 20 `rec_wr_mode` (2 MiB write mode): no effect (60.3 → 60.3 P010, 83.9 → 83.9 AFBC). [M]
- VE clock 624 MHz: not tried (the extra 4 % is not needed for AFBC; not soaked for P010).
- IOMMU bypass (identity domain via `iommu.passthrough=1`, `cma=320M`; mainline `sun50i_iommu_identity_attach()` disables the IOMMU):
  results in §3 item 2. Native AFBC10 under passthrough: 83.7 fps (no change). Log `vdec-perf/logs/round-b-passthrough.txt`.
- One VE hang was seen: on the new image, the very first native-AFBC run right after a P010 run under `perf-run.sh` hit
  `sun50i-iommu: Page fault for 0xf690e000 (master -1, dir rd)` and then "frame processing timed out" for every job until reboot.
  At that point the IOMMU PMU registers were being written with a byte-wise Python /dev/mem helper (the image has no busybox).
  After switching the helper to 32-bit word stores, the same sequence ran clean 3 times plus the full round (20 runs). Cause not
  established; treat it as possibly a real AFBC/IOMMU issue until it is seen again or ruled out. [U]

## 5. Series change
New commit on `feat/sunxi-h616-vdec-spec` (wt-vdec), pushed to `fork`: `5a078800a` "sunxi-7.3: cedrus: P010 output reconstructs into AFBC
(4K Main10 24 -> 60 fps)", adding patch 30 `patches.media/h616-vdec/media-cedrus-reconstruct-10-bit-pictures-into-AFBC-for-P010-output.patch`
after patch 29 in series.conf.

- What it does: for P010 capture, `cedrus_dst_frame_fmt()` now describes the hidden surface as `YUV420_10_AFBC_16X16_SPLIT`
  (4 KiB aligned after the P010 picture, sized with the AFBC formula, no 2-bit plane); `cedrus_recon_is_afbc()` turns on the
  VE_MODE AFBC bits and zero chroma addresses for H.265 frame info and VP9; `VE_PRIMARY_OUT_FMT` gets only the secondary-EXT
  NV12 field; VP9 writes its 10-bit config with only the P010 bit. Native AFBC and 8-bit paths are untouched (md5-checked above).
- Memory: a 4K P010 capture buffer grows from 40.4 MB to 42.1 MB (24.9 P010 + 17.2 AFBC). 6K Main10 P010 stays out of reach on 1 GB.
- Checks: `STAGE=patch` 742 applied / 0 failed (`kernel-check/run-vdec-patch5.log`), patched cedrus sources byte-identical to the
  scratch git tree; `make W=1 drivers/staging/media/sunxi/cedrus/` 0 warnings; incremental ccache Image build OK
  (Image md5 `7408d1d5cd77312bf6dfa74a572082ad`, no debug params). Board results in §2.3 come from the same code plus the
  counter-only debug params (`scratch-vdec/dbg4-src/`).
- Not changed: patch 27's format order. P010 is still the G_FMT default for 10-bit H.265, so generic clients get the fast P010;
  AFBC must be requested explicitly (the cedrus_video.c comment saying "10-bit AFBC stays ahead of P010" does not describe the
  order the array actually has; P010 comes first). Left as is.

## 6. DE33 AFBC scanout (plan only, not ported)
Native AFBC10 decodes at 84 fps (H.265 and VP9), so the 4K60 spec rows need only scanout. Plan:
`harness/research/vdec-perf/de33-afbc-plan.md` (written by a sub-agent from the 82 LibreELEC patches 0200–0285/0700/0702 fetched
read-only into `vdec-perf/le-de33/`, sha256 in its `SHA256SUMS`; checked against our tree by dry-run on a /tmp copy). Summary:
- LE 0200–0213 are already ours (Armbian patches.drm/0032–0045). 0214–0250 and 0283–0285 are missing.
- H616 VI planes currently expose **no YUV at all** (`sun50i_planes.c` `scaler_mask = 0`), so the VI scaler chain (LE 0214–0220, 0231)
  is a hard prerequisite.
- LE 0247/0248 (AFBC decompressor, AFBC on VI planes) are written against LE's register-shadow/RCQ API (0223–0230); the plan
  rewrites them onto our regmap base (~25 writes) rather than porting the rework.
- Zero-copy import needs the DE behind the IOMMU (`iommus = <&iommu 0>` on the planes node from LE 0702, mixer hunk of 0240).
- Stage A (≈14 patches, 6 hand-merges, 3–5 days) proves AFBC10 4K60 scanout over today's 8-bit RGB 594 MHz HDMI.
  Stage B, 10-bit HDMI, needs 0256–0285 (~22 patches, 4–7 days): RGB 10-bit 4K60 does not fit dw-hdmi's 594 MHz; 4:2:0 10-bit
  (371 MHz) and 4:2:2 12-bit container (594 MHz) do.
- Verification needs a 4K60 HDMI 2.0 sink on the board (none attached today) and a small KMS client logging page-flip sequence
  and timestamps.
Not ported, as instructed.

## 7. Files
- `harness/research/vdec-perf/`: `build-ffmpeg.sh`, `ffmpeg-pixfmt-override.diff`, `ship.sh` (HTTP in 400 KiB pieces, needed on
  the old image where end0 stalled at 512 KiB), `install-kernel.sh`, `ve-busy-cmd.sh`, `perf-run.sh`, `devmem.py`, `board-round-a.sh`,
  `board-round-b.sh`, `debug-dbg3.diff` (debug params incl. `dbg_p010_tiled` modes), `afbc-recon-clean.diff`, `commit-msg-afbc-recon.txt`,
  `de33-afbc-plan.md`, `le-de33/`, `logs/` (`counters-run1.txt`, `md5-modes-run1.txt`, `round-a2-dbg4.txt`, `round-b-passthrough.txt`).
- FFmpeg: source `kernel-check/ffmpeg-afbc/src/ffmpeg` (a56a208 + override), build `kernel-check/ffmpeg-afbc/build/`, sysroot `kernel-check/ffmpeg-afbc/sysroot/`.
- Kernels: `kernel-check/vdec-serve/Image.dbg3|dbg4` + `modules-dbg3|dbg4.tgz`; sources `kernel-check/scratch-vdec/dbg3-src`, `dbg4-src`;
  clean patch commit in `kernel-check/scratch-vdec/linux` (HEAD). `kernel-check/work-vdec/linux-7.3.1` now holds the clean series sources.
- Board: restored to the image kernel 7.3.1-edge-sunxi64 #8 with the original cmdline; `/root/vp`, `/root/vdec-streams` left in place.

## 8. Not verified / open
- Native AFBC10 output is not md5-verified directly (no AFBC decompressor); the evidence is the AFBC-reference loop inside the
  bit-exact P010 runs (§2.3) and Jernej's LibreELEC use. Display of AFBC (DE33) is not implemented.
- 60.3 fps for H.265 P010 is VE-bound with ~0 % margin; the FFmpeg pipeline reaches 57.3, GStreamer 32.9. P010 4K60 is therefore
  "decoder meets it, delivery does not quite" for both clients. VP9 P2 P010 is 57.1 VE-bound: **not** 60.
- VE 624 MHz (vendor policy) not tried; it might push P010 just over 60 but needs a voltage soak first.
- Stream content: testsrc2 + noise at ~40 Mbit/s (impl-vdec §9), a hard case for AFBC compression; real video should compress
  better, so AFBC numbers are likely conservative. [I]
- MBUS PMU counter units are not calibrated; the VE top counters see only the master-3 port.
- Single unexplained VE hang + IOMMU fault (§4).
- The P010 IOMMU-passthrough A/B did not run (CMA fragmentation).
- Tiled128 hidden recon md5 not run (the run was aborted for the reflash; the 15 s result in `md5-modes-run1.txt` is invalid).
