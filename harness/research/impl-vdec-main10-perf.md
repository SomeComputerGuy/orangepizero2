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

## 9. Queue depth and the real pipelines (2026-11-05)

Brief: docs/status.md §3 item 3 "VP9: queue depth". Find where the 10-bit 4K pipelines lose time (client queue depth, m2m
scheduling, cache maintenance/copies, VE clock) and fix it. Board: image 8546e5fc1 kernel `7.3.1-edge-sunxi64 #17`
(contains patch 30 + AVS2), VDD-SYS at the 900 mV DT floor (GPU idle). Tags as above.

### 9.1 Method: per-job timeline
`vdec-perf/ve-timeline.sh <cmd>` (new): ftrace function events, mono clock. For each job it gives `setup` (cedrus_device_run
→ codec trigger, CPU), `ve` (trigger → cedrus_irq), and the gap from cedrus_irq to the next device_run. A gap counts as
**ready** if the next request was already queued (v4l2_m2m_request_queue) at IRQ time; then it is kernel latency
(`wq` = IRQ → v4l2_m2m_device_run_work). Otherwise it counts as **starved**: the client had not queued it. "Pipeline" =
jobs / (first device_run … last IRQ), the steady state. Wall time also includes open/allocation (≈1–1.5 s for 4K P010:
8 × 42 MB buffers), so the old "pipeline fps" (wall) of §2.3 understated every client.
Rounds: `vdec-perf/board-queue-r1.sh`, `board-queue-r2.sh`, sessions `session.sh` (lock held only for the session); logs
`vdec-perf/logs/queue-r1/`, `queue-r2/`.

### 9.2 Where the time goes [M]
| 4K P010 run (600 MHz) | setup ms | VE ms | ready gap ms (n) | starved (n) | VE-only fps | pipeline fps | wall fps |
|---|---|---|---|---|---|---|---|
| FFmpeg VP9 P2, threads auto | 0.22 | 17.17 | 0.125 (645) | 2 | 58.2 | **57.8** | 51.3 |
| FFmpeg VP9 P2, `-threads 1` | 0.20 | 16.56 | 0.12 (48) | **600, 1.30 ms** | 60.4 | 54.7 | 49.3 |
| FFmpeg H.265 Main10, threads auto | 0.25 | 16.37 | 0.091 (595) | 4 | 61.1 | **60.6** | 56.3 |
| FFmpeg H.265 Main10, `-threads 1` | 0.17 | 16.28 | 0.08 (449) | 151, 0.58 ms | 61.4 | 59.1 | 56.7 |
| GStreamer H.265 Main10, `fakesink` | 0.20 | 16.24 | 0.153 (599) | 0 | 61.6 | **60.2** | 44.1 |
| GStreamer H.265 Main10, `fakevideosink` | 0.21 | 16.24 | 0.114 (599) | 0 | 61.6 | **60.4** | 57.8 |
| GStreamer VP9 P2, `fakevideosink` | 0.23 | 16.69 | 0.254 (647) | 0 | 59.9 | 58.2 | 54.0 |
| VP9 P2 → AFBC10 (FFmpeg) | 0.24 | 11.62 | 0.10 | 1 | 86.1 | 85.0 | 73.3 |
| avs2dec (old, 1 request in flight) AVS2 Main10 | 0.17 | 16.83 | – | **292, 1.21 ms** | 59.4 | 53.4 | 44.8 |
| avs2dec `-q` (2 in flight, new) | 0.24 | 16.95 | 0.130 (291) | 0 | 59.0 | 57.7 | 49.1 |

- **The queue is not the bottleneck.** With FFmpeg frame threads (default) and with GStreamer the next request is always queued
  before the IRQ. The m2m handover (IRQ → worker → device_run) costs 0.09–0.25 ms per picture, and setup is 0.2 ms. The VE is
  busy > 97 % of the steady state. The only real starvation: `-threads 1` (1.3 ms/picture for VP9, which has no reorder delay)
  and the old single-request avs2dec (fixed, §9.4 / impl-avs2.md §8).
- **GStreamer's 32.9 fps (§2.3) does not reproduce** on this image. During streaming the VE never starves (60.2 fps); the
  `fakesink` wall-time loss (44.1 vs 57.8 with `fakevideosink`) lies outside the decode span (startup/teardown, not
  investigated further). [M/U]
- **Pipeline = VE-bound.** So the 4K60 P010 rows depend only on the VE time per picture: H.265 Main10 at 61 fps passes,
  VP9 P2 at 58 fps does not.
- No cache maintenance shows up: vb2-dma-contig capture buffers are coherent (no sync on QBUF/DQBUF), and `-f null` with
  `drm_prime` copies nothing. [M by absence in the setup/gap numbers; I]

### 9.3 Knobs on the VE side [M]
MBUS master registers (0x047FA210 + 16·port) as programmed by U-Boot: port 4 (VE) cfg0 0x20000209 (BWL on, QoS HIGH, ACS 2,
8192 MB/s), port 25 (IOMMU page-table walks) 0x0064000F (BWL on, **100 MB/s**, QoS HIGHEST + priority). Port 26 (the second
VE port in the H6 table) is not programmed on H616 (0). Set with devmem.py, restored after each round.

| VE-only fps (pipeline) | VP9 P2 P010 | H.265 Main10 P010 | AVS2 Main10 P010 (avs2dec -q) |
|---|---|---|---|
| 600 MHz, U-Boot MBUS | 58.2 (57.8) | 61.1 (60.6) | 59.0–59.9 (57.7–58.7) |
| + port 25 BWL off | 58.7 (58.3) | 61.0 (59.6) | – |
| + port 4 priority + QoS HIGHEST | 57.4–58.0 | 62.9 (61.3) | 59.9–60.1 |
| **624 MHz** | **59.5 (59.0)** | **63.3 (61.8)** | **61.7 (60.0)** |
| 624 MHz + port 4 HIGHEST | 58.4 (57.9) | 65.3 (63.7) | 62.2 (60.9) |
| GStreamer at 624 MHz (VE-only / pipeline) | 61.0 / 59.4 | 64.0 / 62.7 | – |

- The IOMMU walk-port bandwidth limit is not limiting (no change).
- VE priority/QoS: +3 % for H.265, ~+1 % for AVS2, 0 or slightly negative for VP9. **Not proposed**: the VE at HIGHEST
  would compete with the DE33 scanout (port 16 HIGHEST) at 4K. Reported only.
- **624 MHz** (the vendor libVE policy rate for IP 0x33010; set here through PLL_VE N 24 → 25, reg 0x03001058, which
  cedrus programs only at probe): +3.6 % for H.265 and AVS2, only +2.2 % for VP9. VP9's P010 write is bound by memory/IOMMU
  latency (master-3 TLB hit rate 59 %, §3 item 4), not by the engine clock.
- Bit-exactness at 624 MHz + port 4 HIGHEST: VP9 P2 P010 `1e40c2b3…`, H.265 Main10 P010 `e57bc497…`, AVS2 8-bit 4K
  `3a3d5d7e…`, AVS2 10-bit P010 `be9985de…`: all PASS. Soak 15 min at 624 MHz + port 4 HIGHEST with VDD-SYS at its 900 mV
  floor (GPU idle, 59 → 64 °C): 9 md5 runs, 0 failures. [M] 15 min is a short soak; the 810 mV failure of §9.2 in impl-vdec
  shows the rail matters, so a longer soak on the cumulative kernel is listed as open.
- dmesg on the board showed a burst of `cedrus: frame processing timed out!` after round 2. None of my traced jobs took longer
  than 58 ms, and all md5s passed. They most likely come from another agent's session on the shared board. [I] Round 3 logs
  uptime and the timeout count at its start and end to settle it.

### 9.4 Changes
- Kernel, branch `feat/sunxi-h616-vdec-60fps` (fork, rebased on `test/cumulative` 67cef8768; handed to the coordinator for
  cumulative kernel c2):
  - `ba5caad1e` patch `media-cedrus-offer-10-bit-AFBC-capture-for-AVS2.patch` (impl-avs2.md §8).
  - `e6229e03c` patch `media-cedrus-run-the-H616-VE-at-624-MHz.patch`: H616 `mod_rate` 600 → 624 MHz.
  - Both patch files carry `Assisted-by: LLM`. Checks on base b9df5096b: STAGE=patch 813 applied / 0 failed, sources
    identical to the build tree, `W=1` cedrus clean, Image builds. No patch new in test/cumulative touches the two files.
- Test tools: `vdec-perf/ve-timeline.sh`, rounds and sessions as above; avs2dec request queue (impl-avs2.md §8).
- Not changed: FFmpeg/GStreamer (they already keep the VE fed), MBUS settings (U-Boot), the m2m core.

### 9.5 Result against the spec rows
| row | P010 (generic userspace), real pipeline | AFBC10 |
|---|---|---|
| H.265 Main10 4K@60 | **met**: FFmpeg 60.6 / GStreamer 60.4 at 600 MHz; 61.8 / 62.7 at 624 MHz | 83.9 fps |
| VP9 Profile 2 4K@60 | **not met**: 57.8 FFmpeg / 58.2 GStreamer at 600, 59.0 / 59.4 at 624 MHz (VE-only 59.5 / 61.0) | 85.0 fps pipeline |

### 9.6 Still open
- VP9 P2 P010 is ~1–2 % short of 60 even at 624 MHz. What remains is the VP9 engine's P010 write order (TLB misses, §3 item
  4), not the queue. Possible next steps: an IOMMU passthrough A/B for VP9 P010 with a larger CMA, and the VP9 secondary-output
  write registers in the vendor library. 4K60 VP9 display goes through AFBC anyway (DE33 AFBC scanout, §6, needs an HDMI 2.0
  sink we do not have).
- A longer soak at the 624 MHz default on a cumulative kernel (round 2's 900 s soak was at 624 set by devmem).

### 9.7 Round 3 on cumulative kernel c2 (2026-11-05) [M]
Kernel c2 = test-cumulative b8258b7f2 (Image md5 45a73129…), with `e6229e03c` + `ba5caad1e` + kbase. Installed with
the fallback armed, image DTB kept, board restored to image kernel #17 afterwards. Logs in `vdec-perf/logs/queue-r3/`.
- The kernel default is now 624 MHz: `pll-ve 0x28001900`, `clk 624000000` at boot, no devmem.
- Rates (VE-only / pipeline span, fps), FFmpeg at default threads, avs2dec depth 2:

| stream | 624 (c2 default) | 624 + port 4 QoS HIGHEST | 600 (PLL N=24) |
|---|---|---|---|
| H.265 Main10 P010 | 63.3 / 62.8 | 65.4 / 63.9 | 60.9 / 60.6 |
| VP9 P2 P010 | 59.3 / 59.0 | 58.8 / 58.6 | 58.8 / 58.6 |
| AVS2 10-bit P010 | 62.5 / 61.3 | 62.3 / 61.0 | 59.1 / 58.0 |
| AVS2 10-bit AFBC | 89.4 / 87.8 | 93.0 / 91.3 | 87.0 / 85.4 |

  The c2 numbers repeat round 2. Ready gaps are 0.08–0.12 ms and starved gaps 0–5 per run, so the queue is still not the
  limit. VP9 P2 P010 stays ~1 fps short at every setting.
- md5 regression at the default rate: VP9 P2 `1e40c2b3…`, H.265 Main10 `e57bc497…`, AVS2 8-bit 4K `3a3d5d7e…`, AVS2
  10-bit cctv4k P010 `be9985de…`, all PASS.
- v4l2-compliance: 43/49, the same 6 pre-existing failures as the baseline (impl-avs2.md §7.4).
- cedrus timeouts: 0 from boot (uptime 36 s) to the end (715 s). The round-2 timeout burst was not from these tests.

### 9.8 VP9 Profile 2 P010: the IOMMU micro-TLB is the limit (round 4, 2026-11-05) [M]
Cumulative kernel c5 (no cedrus change after c2), VE 624 MHz, FFmpeg default threads. Logs `vdec-perf/logs/queue-r4/`.
Streams: the reference 4K stream (4 tile columns) and two 120-frame re-encodes of its first frames (libvpx, 40 Mbit/s)
with 1 tile column (`tc0`) and 4 (`tc2`). IOMMU PMU per master: m2 = VE1 (reference reads), m3 = VE (writes).

| run (fps VE-only / pipeline) | IOMMU on | m3 micro-TLB hit, lat/access | `iommu.passthrough=1 cma=640M` |
|---|---|---|---|
| VP9 P2 4K reference, P010 | 59.2 / 56.8 | 58 %, 14 | **66.6 / 64.6** (md5 PASS) |
| VP9 tc0 (1 tile) P010 | 66.1 / 67.7 | 58 %, 11 | 72.6 / 73.8 (md5 PASS) |
| VP9 tc2 (4 tiles) P010 | 63.8 / 65.5 | 58 %, 14 | 71.5 / 72.8 |
| VP9 tc0 / tc2 AFBC | 101.7 / 101.5 | 94–95 %, 3 | 101.9 / 101.9 |
| H.265 Main10 P010 | 63.3 / 62.7 | 96 %, 4 | 63.5 / 62.7 |

- **Root cause:** the VP9 engine's P010 secondary write misses the 64-entry per-master micro-TLB on 42 % of its accesses.
  The H.265 engine's write of the same format hits 96 %. Without translation VP9 P010 gains 12.5 % (59.2 → 66.6) and
  passes 60 with margin. Without the P010 write (AFBC) and for H.265, passthrough changes nothing. [M]
- **Not the tile layout:** 1 and 4 tile columns give the same 58 % hit rate. The 1-tile clip is faster only because its
  content is easier. [M]
- **Write pattern [I]:** about 61 bytes per P010 write access, so the engine writes each line of a 64×64 superblock in
  64–128 byte pieces. One superblock touches 64 luma and 32 chroma lines, each on its own 4 KiB page at the 7680-byte
  stride, so 96 pages > 64 TLB entries, revisited by the next superblock. That is an LRU thrash.
- **IOMMU knobs, none helps [M]:** TLB prefetch for all masters (already 0x7f in the mainline driver), write buffer off for
  master 3, out-of-order off for masters 2/3: VP9 P010 stays 59.2–59.8, md5 PASS. The H616 IOMMU translates 4 KiB pages
  only (manual 3.12: `VA[31:12]` looked up in the micro TLB), so no larger mappings.
- **Vendor programming is the same as ours [M, static RE]:** T527 `libawvp9HwAL.so` (DWARF, H616 code path).
  - `Vp9AsicRun` FUNC_CTRL = 0x80000007 | 0x200 (secondary output), no `mcri_cache_en`.
  - `Vp9SetTopSecReg` sets only the format, chroma length and strides at 0xe8/0xec/0xcc; `luma_align_mode` /
    `chroma_align_mode` stay 0.
  - `VP9Set10BitReg` sets only the 2-bit stride.
  - The vendor path therefore has the same P010 limit; its 4K output is AFBC.
- **Untranslated mode: rejected (user decision, 2026-11-05).** The IOMMU stays on for every master: no passthrough, no
  per-master bypass, no opt-in. Before the decision a per-master bypass was built and tested on c8 (branch
  `feat/sunxi-h616-vdec-untranslated`, reverted from test-cumulative; c9 = c7's tree):
  - IOMMU_BYPASS_REG (0x30) has one bit per master. An overlay with an empty VE `iommus` left only masters 2 and 3
    untranslated.
  - VP9 P2 P010 reached 66.7 fps VE-only and 61.2-66.1 fps pipeline (FFmpeg threads 1 to auto), md5 PASS.
  - The 42 MB 4K 10-bit buffers then come from CMA at run time. They failed with -EBUSY (`cma: ... alloc failed,
    req-size: 10283 pages, ret: -16`) at cma=480M and cma=640M, which broke the AVS2 10-bit and H.265 md5 runs.
  - Logs: `vdec-perf/logs/queue-untr/`. The work stopped there.
- **IOMMU-on ideas for the micro-TLB miss rate (listed only; none built without asking):**
  - *Why the buffer layout alone cannot fix it [I].*
    - Every 4K P010 line is 7680 bytes, more than a 4 KiB page. So a 64×64 superblock touches one page per row: 64 luma
      plus 32 chroma = 96 pages, whatever the stride padding, plane placement or plane order.
    - A smaller stride can't go below 7680 bytes.
    - Interleaving luma and chroma lines would no longer be P010 (V4L2, DRM and panfrost import a two-plane layout).
    - It still gives 96 distinct pages per superblock.
  - *H.265 hits 96 % because its CTB is 32×32 [M].* The test stream's SPS has log2 min CB 4 and diff 1, so the CTB is
    32×32. Its superblock touches 32 + 16 = 48 pages, under the 64 entries. That explains the H.265/VP9 gap without any
    engine difference. VP9 superblocks are always 64×64.
  - *1. A narrower write unit in the VP9 SDRT writer [RE].* Look for a register mode that emits the secondary output in
    32-row halves or through a line buffer per superblock row. The candidates are the unknown bits of the SDRT block at
    H265+0x50..0x58 and of VP9_FUNC_CTRL. The vendor library sets none of them, so this means bit probing with md5
    checks.
  - *2. A tiled 10-bit secondary output [RE].* If 0xe8 bits 31:30 or the SDRT format field have a tiled 10-bit mode, a
    tile is contiguous, so a superblock touches a handful of pages. It is only useful if DE33 and panfrost can import that
    tiling.
  - *3. AFBC capture, plus a GPU conversion to linear P010 only where a linear surface is needed.* The AFBC capture writes
    at a 94-95 % hit rate. Display scans out AFBC directly.
  - *4. Measure the macro TLB / PTW cache behind the micro TLB.* The PMU has counters beyond the 7 masters. If the
    micro-TLB misses also miss there, a page-table or capture-buffer allocation order that keeps the 96 pages in one PTW
    cache line group could cut the miss latency (14 → ~4 cycles per access) even if the miss count stays.
- **Status of the spec row:** VP9 P2 4K@60 is met with AFBC capture (102 fps on tc0/tc2, 85 on the reference stream,
  §9.5). It is ~1 fps short with P010 behind the IOMMU (59.0 pipeline in round 3). The row counts as met through AFBC (coordinator decision, 2026-11-05): that is the 4K60 playback
  path, because DE33 scans out AFBC.
