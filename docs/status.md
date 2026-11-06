# Orange Pi Zero2: hardware bring-up status

Date: 2026-11-02. Image on the board: Armbian-unofficial 26.11.0-trunk, Ubuntu 26.10 (stonking), Linux 7.3.1-edge-sunxi64,
U-Boot 2026.10, TF-A lts-v2.14.11 + H616 suspend patches (clean BL31 b88ccfba76a6). Acceptance list:
[spec-checklist.md](spec-checklist.md) (every row of the orangepi.org spec page). Details: `harness/research/impl-*.md`.

Legend: **OK** verified on the board · **OK\*** driver present, not functionally verified · **PARTIAL** works with a
known gap · **GAP** no driver anywhere.

## 1. Status

| Area | Status | Evidence / notes |
|---|---|---|
| Boot SPL → TF-A → U-Boot → kernel | OK | AXP305 over RSB in SPL: no "Failed to set core voltage", SPL→kernel 6.5 s (was 8.5 s). ENV_IS_NOWHERE. USB hosts scanned in parallel (1.5 s). |
| SD card | OK | SDHC 4-bit 50 MHz (3.3 V only, no UHS). `mmc0` alias = SD. |
| SPI NOR 2 MB | OK | U-Boot written + read-back verified; BROM boots "sunxi SPI"; fallback SD → USB → PXE → DHCP → prompt in ~11 s. |
| USB boot / netboot | TODO | Built (all host ports); needs a stick / TFTP server. |
| DRAM 1 GB | OK | |
| CPU DVFS 480–1512 MHz | OK | speed bin speed3; sustained 1512 MHz under 4-core stress. |
| Thermal | OK | CPU passive 85 °C (cpu0-3), hot 100, critical 110; GPU passive 85 °C via devfreq cooling. |
| cpuidle | OK | Native PSCI CPU_SUSPEND in TF-A + `cpu-sleep` idle state; 30-min soak PASS. |
| Suspend to RAM | OK | Native SYSTEM_SUSPEND: DRAM software self-refresh (STAT 0x223), 100/100 rtcwake cycles with cpuidle, 200 MB tmpfs hash intact. Power saving not measured (Meross MSS110 has no metering). |
| VDD-SYS (vdd-gpu-sys) | OK | Floor 900 mV: at 810 mV (GPU devfreq idle) 4K VE decode corrupted 6/13 runs; 0/6 at ≥ 890 mV. |
| Ethernet 1 GbE (RTL8211F) | PARTIAL | Dead-RX boots fixed with `rgmii-rxid` (10/10 cold boots RX OK). **Open:** on the current debug kernels, bulk host→board TCP over end0 (scp, `ssh cat`) stalls at exactly 512 KiB while the same file passes over WiFi; 8000-byte pings lose ~33 % after ~1 h uptime. Small packets and ssh fine; RX/TX error counters 0, 6 TX drops. Neither retested on the image kernel. Forced 10/100 + iperf3 not tested. |
| WiFi UWE5622 (SDIO) | PARTIAL | Scan 2.4 + 5 GHz OK. 5 GHz SoftAP fixed (driver never passed the channel): hostapd ch36 → VHT80 MCS9, iperf3 128 Mbit/s host→board, 96.5 board→host; 2.4 GHz AP 31.5 / 41.4 Mbit/s; wpa_supplicant AP works on both bands. Regdomain from cfg80211 (all countries); image sets it with `OPIZ2_WIFI_REGDOM` (2c5dd06). Firmware always picks the widest 20/40/80 MHz block. STA association + iperf as station to test. |
| Bluetooth (UWE5622, UART) | PARTIAL | Blob-free: in-kernel vendor init + stock `btattach`. Board <-> host (BlueZ 5.87, 2026-11-05): discovery both ways, SSP pairing + bond, bond and BD address EA:97:B0:2B:A9:EE kept over a reboot, reconnect OK; L2CAP 4 MB host->board 190 kB/s, board->host 165 kB/s; RFCOMM 4 MB host->board 180 kB/s, 0 loss; LE advertising + LE scan both ways. **Open:** LE connection/GATT (host uses LL privacy; test with a phone). Blob kept as fallback (`vendor_init=0`). |
| USB host (3× EHCI/OHCI) | OK\* | Controllers up; no device plugged in yet. |
| USB-C | PARTIAL | Gadget mode untested (power-only cable). Host mode via overlay `sun50i-h616-usb-otg-host` (needs board powered from the header). |
| HDMI video | OK\* | Pipeline bound; no display yet. Blend-mode warnings fixed (0). |
| HDMI audio | OK\* | ALSA card present; needs a display. |
| Analog audio | OK\* (line-out) | DAC-only by hardware (no MIC). Needs expansion board. |
| GPU Mali-G31 (panfrost) | PARTIAL | devfreq 306–600 MHz. GLES 3.2 / OpenCL 2.0 exposure not yet verified. |
| Video decode (Cedrus) | PARTIAL | Bit-exact: MPEG-2, H.264, HEVC, VP8, VP9 P2, HEVC Main10. H.264 4K 42.0 fps (spec 4K30 OK); HEVC 8-bit 4K 81.8 fps, 6K 30.2 fps; HEVC Main10 4K 24.5 fps and VP9 P2 4K 35.6 fps via P010, vs. spec 4K60 (AFBC 10-bit path unmeasured); Main10 6K OOM. Uses Jernej Skrabec's unposted H616 work. |
| AVS2 decode | PARTIAL | New cedrus uAPI + backend: 8-bit bit-exact on 17 streams, 4K Main10 58.5 fps; 10-bit only self-consistent; no FFmpeg path yet (harness avs2dec). |
| Video encode (H.264, JPEG) | GAP | No open driver; reverse-engineering effort (`harness/research/ve-encoder/`). |
| Crypto engine + TRNG | OK | `/dev/hwrng` = CE TRNG. U-Boot CE TRNG → KASLR seed built; board check of KASLR pending. |
| RTC / watchdog | OK | No backup battery; sunxi-wdt 16 s, systemd watchdog 15 s. |
| IR receiver | TODO | On the expansion board; overlay `orangepi-zero2-expansion`. |
| TV-out CVBS | OK\* | New sun8i_tve driver, build-tested; needs a TV. |
| PWM | OK\* (overlay) | Overlays for PH2/PH3 (header pins 8/10) apply cleanly; PWM3/PWM4 on PH0/PH1 now release UART0 (debug console) — fix on `fix/sunxi-h616-pwm-uart0-pins`. PI variants collide with RGMII on this board. |
| I2C / UART / SPI / GPIO headers | OK\* (overlay) | Overlays present; loopback tests to do. |
| LEDs, PMIC AXP305 | OK | No dummy regulators left for spi-nor / phy-io. |
| Print server (CUPS) | OK\* | CUPS 2.4.16, ipp-usb, HPLIP, drivers installed; no printer attached yet. |

## 2. Armbian fork (github.com/SomeComputerGuy/build)

- `stonking-orangepizero2` (9eadcc0fe): integration on armbian/build 27a7f72; the current images come from it.
- `stonking-orangepizero2-rebased` (556b18714): the same topic branches rebased onto armbian/build main c2908d2,
  plus the OpenSSL-4 widening and the PWM/UART0 fix. Tree differs from the integration only by upstream changes
  and those two commits.
- `pr/<topic>`: 39 single-topic branches on c2908d2; `pr/group/*`: 7 grouped branches for PRs.
- PR drafts and the not-ready list: [docs/prs/README.md](prs/README.md). Nothing opened.
- Pre-PR report: `harness/research/pre-pr-cleanup.md`; EMAC1 vs. Linux 7.4: `harness/research/prprep-emac1.md`.

Board-level config lives in `userpatches/` (this repo).

### Image variants (one config: `userpatches/config-opiz2-printserver.conf`)

| Command | Image | Network | Extras |
|---|---|---|---|
| `./build.sh` | `..._minimal.img.xz` (BUILD_MINIMAL=yes) | systemd-networkd + timesyncd | none |
| `./build.sh OPIZ2_VARIANT=server` | `....img.xz` (standard Armbian CLI, BUILD_MINIMAL=no) | NetworkManager (netplan) + chrony | Armbian `packages.additional`, armbian-config (from github.armbian.com/configng), armbian-zsh, plymouth (no splash) |

Both share kernel, U-Boot, firmware, BSP and ccache; the server variant builds its own rootfs cache once
(`cache/rootfs/rootfs-arm64-stonking-cli_*`). Printer/hardware packages, rusticl, the libclc divert, SD-wear fstab,
WiFi regdomain, overlays and patches are identical. DHCP identity 01:<MAC> (harness static lease 10.56.0.107):
netplan `dhcp-identifier: mac` on networkd, `/etc/NetworkManager/conf.d/zz-30-opiz2-dhcp-identity.conf` on NM.
`TUNING_PROFILE=none` on both, so armbian-config does not replace the SD-wear settings on first boot.
Server-image notes: pick bash at first login (the harness's ssh commands assume it); before running hostapd or
wpa_supplicant by hand on wlan0, `nmcli device set wlan0 managed no`. `flash-sd.sh` takes the newest image, so
it flashes whichever variant was built last. Not in either image: ffmpeg (Ubuntu's 8.1.2 has no v4l2-request hwaccel).

## 3. Next (cleaned up 2026-11-04)

Done since the last list: image 8546e5fc1 rebuilt in both variants (minimal + server, 20 PASS each); board queue
finished: KASLR 3/3 distinct, 60 min thermal stress max 76 °C, TVE/IR overlay boots (Composite disconnected, rc0/rc1,
0 vblank errors), JPEG greyscale probe run; interlaced MPEG-4 refusals merged; TV-out clock pinned.

### A. Now (board only, low credits)
1. GPU conformance rerun on the server image (`harness/analysis/gpu/gpu-rerun.sh`, tag 8546e5fc1-server): running.
   Then commit the result summary.
2. Done 2026-11-05: GPU rerun (impl-gpu-spec.md 4b) and Bluetooth board <-> host (status table). Next on the board:
   flash the scan-enabled rebuild once the user has built it, then rerun verify-board.sh (new scan-stack check).

### B. When tokens are back, in this order
3. **Priority (user 2026-11-04: do these before the rest):**
   - OpenCL fixes in the Mesa fork (mesa-work/mesa); same compiler work that GLES 3.2 (item 8) needs.
   - VP9 / 4K60 (2026-11-05, cumulative kernel c2, VE at the vendor 624 MHz): H.265 Main10 P010 62.8 fps, AVS2
     10-bit P010 61.3 / AFBC 87.8 fps (AVS2 10-bit = davs2 on 291/292 frames; the last frame is damaged in the stream).
     **Deferred (performance, user 2026-11-05): VP9 Profile 2 P010 stays at 59.0 fps.** The cause is the IOMMU micro-TLB
     (96 pages per 64x64 superblock, more than 64 entries). The IOMMU stays on for every master. The 4K60 row is met via
     AFBC. Ideas are in impl-vdec-main10-perf.md §9.8. Open: test1.avs2 (854x480) md5 mismatch (timeouts fixed in
     c7), md5 of AFBC captures, the 60 min soak (soak3 on c9), FFmpeg AVS2 request queueing.
   - AVS2 uAPI v6 (doc-only, agreed with OPi5 rkvdec, 17/17 bit-exact there): merged in test-cumulative; held.
4. OPi5 / RK3588S cross-check. One agent (fable if available, else Opus), read-only on both trees: ~/orangepi5
   (never modify it or its memory) and its GitHub repos, against every patch / branch we carry (armbian-build fork
   branches, sunxi-7.3 series, U-Boot/TF-A, userpatches, Mesa fork, FFmpeg drafts in docs/upstream-queue.md).
   Answer: what we can use from them; what they can use from us; whether common code both sides changed (Armbian
   framework, stonking support, kernel core/media/drm, Mesa panfrost, FFmpeg v4l2-request, U-Boot, TF-A) is
   compatible, conflicting or duplicated (nothing we send upstream may contradict theirs); recommended actions
   (share/port, merge into one version, submission order, owner). Report: harness/research/opi5-crosscheck.md; no
   changes to either tree until the user approves.
5. Vulkan dEQP: setup FIXED 2026-11-05 (a399a9f; impl-gpu-spec.md 4c): deqp-vk was built from the GLES CTS tag; now
   vulkan-cts-1.4.6.2 + Mesa CI backports (harness/analysis/gpu/build-deqp-vk.sh). API 1.0: subset 3332 pass / 5 fail /
   0 crash, vk-main 1/100 6345 / 3 / 7. G31 subgroup INSTR_INVALID_ENC FIXED 2026-11-06 (job 52 ALL PASS on c38):
   G31 cannot execute WMASK -> Mesa fork ab1caa7378f (ballot from 4 CLPER_OLD reads) + b7a705442bd; OpenCL CL_A
   UNORM_INT8 1Dbuffer fault -> 0e274280595 (A8 texel buffers unsupported). subset REGRESSIONS 0, FIXED 16; 0 GPU faults.
   The 7 spirv_assembly frag "hangs" were the 500 ms watchdog (kernel soft-stop series, in image). Vulkan 1.1 needs:
   the fork fixes in the image, Mesa ba09d293e54 (version gate), PAN_I_WANT_A_BROKEN_VULKAN_DRIVER handling (user's call), full vk-main
   at 1.1 (~14 h). With the OpenCL compiler work (item 3).
6. Desktop image variant (user: "ffmpeg goes into the desktop one"): OPIZ2_VARIANT=desktop (BUILD_DESKTOP=yes) in the
   shared config + build-all.sh; ship the v4l2-request FFmpeg (Jernej/Kwiboo fork + our drafts in
   docs/upstream-queue.md) as a cached package; mpv/GStreamer on the hw decoder. Minimal/server stay without FFmpeg.
   Write v4l2-request hwaccels for our non-upstream cedrus uAPIs: AVS2 (impl-avs2.md; userspace owns the DPB, today
   only harness avs2dec), AVS/AVS+ (patches.media/h616-avs), MPEG-1 (draft in docs/upstream-queue.md); check against
   avs2dec/davs2 md5s on the board. Fix the stale AVS/AVS+ GAP row in docs/datasheet-checklist.md.
   Desktop: GNOME, same as standard Armbian for orangepizero2 (user 2026-11-05); record idle RAM + 4K playback.
7. User Manual review: one agent reads docs/vendor/H616_User_Manual_V1.0.pdf (831 pp; CCU, TVE, HDMI, Audio
   HUB/codec/OWA, EMAC, DMA, IOMMU, thermal, RTC, timers, TWI/UART/SPI/PWM/LRADC, Crypto/SID) and reviews the sunxi-7.3
   patches + DT, U-Boot (DRAM/CCU/PMIC), TF-A and docs/datasheet-checklist.md against it. Report wrong register use,
   missed features, wrong limits, new acceptance rows; fixes on fix/* branches, build-checked, not merged until the
   user approves. Report: harness/research/user-manual-review.md.
8. GLES 3.2 in panfrost (user go 2026-11-04; Arm legal cleared the blob licence). Mesa fork branch panfrost-gs-tess.
   Step 1: reference traces of Arm g24p0 (harness/research/arm-blob/dl/, git-ignored, never in an image); needs a
   board-only trial kernel with Arm kbase (/dev/mali0). Step 2: GS + tessellation via src/poly compute lowering in
   gallium panfrost (v7 JM). Step 3: KHR-GLES32 + dEQP-GLES31 GS/tess on the board, no GLES 3.1 regressions.
   After item 3's OpenCL fixes. Never upstream without asking.
9. Remaining smaller work:
   - Ethernet jumbo frames: board-test and merge fix/sunxi-h616-emac-jumbo (impl-emac-jumbo.md); the 11-03 soak lost
     all 8000-byte pings in 11 of 19 rounds.
   - JPEG greyscale decode (probe run 11-03; result to fold in).
   - Display tearing.
     Open (2026-11-06, from W23 job 41): 3 of 914 DE33 latch flushes serviced ~7 ms after vsync (de33_latch_line_max
     369-370, only in the -D flips runs; job 19 had 0 of 1800); IRQ-off source unknown (job 42 records
     /proc/interrupts + cpufreq trans). Also: sun4i_tcon_handler() sends the flip event before the latch flush
     (vblank_quirk), a us-wide race with a next commit (coalesced 0 so far). Details: impl-de33-writeback.md "Job 41".
   - panfrost: `WARN panfrost_mmu_map+0xcc` (panfrost_mmu.c:478) 5x when the 2 gles31 OOM cases hit the memcg limit;
     the map failure should return an error, not WARN. Kernel fix on a fix/* branch.
   - panfrost: KHR-GLES31 blend_equation_advanced mixedSequence fails 5/5 (coherent blend), with item 3.
   - Bluetooth LE connection + GATT, with a phone (host's LL privacy blocks a host test).
   - MPEG-4 ASP 3840x2160 decode acceptance test (datasheet-checklist).
   - Datasheet W-items in docs/datasheet-checklist.md (W1-W34: CONFIG_COMPAT, hstimer, CE PRNG, SPI dual/quad,
     deinterlacer, DE33 10-bit/HDR, I2S/SPDIF overlays, ...).
   - Video encoder H.264/JPEG (reverse engineering, last). Decided 2026-11-05: build it on Paul Kocialkowski's
     stateless H.264 encode uAPI (2026-05 [PATCH 00/14], as OPi5 does), not a stateful cedrus encoder; re-plan
     harness/research/ve-encoder/PLAN.md.
   - Cross-check follow-ups (harness/research/opi5-crosscheck.md; user decisions 2026-11-05): take OPi5 fixes 1407
     (rebased), 0514, 1102, 1103, 2206, 1913 into sunxi-7.3 and test with the suspend test; port their VP9 resize fix
     (0606/2228 + GStreamer patch; cedrus VP9 still fails 64 vectors). Deinterlacer: standard
     V4L2_CID_DEINTERLACING_MODE (decided) and move the DI300 private IDs into a reserved range. FFmpeg base: Kwiboo
     v4l2-request (PR 20847) + Jernej's work + our hwaccels, shared with OPi5 (decided). AVS2 v6 as one joint RFC with
     rkvdec. Findings sent to the OPi5 session 2026-11-05. Open: AI trailer form (coding-assistants.rst).

### Code queue (next fresh agent when a slot frees, in order)
- Board PASS (harness/runner-queue/done/): 07 AVS2 test1 (c15 POC fix, 2096/2096 frames), 13 VP9 upsize (c17, 52/52),
  17 IOMMU prefetch faults (c18: 0 new faults; stock scanout trigger did not fire, decode 214 faults on stock).
- Runner failures analysed 2026-11-06 (reruns queued as jobs 22-25; details in each task's RESULTS.md):
  - 11-gst-jpeg-recheck: both FAILs were wrong expectations (gst-inspect `Name` = plugin name; without the rank override the
    stateful v4l2jpegdec declines odd sizes on c11+ because the kernel's 16-pixel frame-size step lands in its caps, so
    v4l2sljpegdec decoded, rc=0). 8/8 cases PASS on c17. Rerun job 22 adds a 16-aligned `norank16` log for the stateful-hang item.
  - 12-avs2-queue: script bug (ffmpeg without -nostdin ate the stream list in the md5 loop); 10/10 streams that ran PASS,
    0 timeouts. Fixed, rerun job 23.
  - 12-gst-mpeg1: check 9 matched "default" (fixed, word match). Check 1 is REAL: the print-server image has no software
    MPEG-1/2 (or H.264/H.265) GStreamer decoder at all ("Missing element: MPEG-1 Video decoder"). Fix: gstreamer1.0-libav in
    every image variant (userpatches/config-opiz2-printserver.conf) -> **image rebuild + reflash needed**; until then the
    rerun (job 24) reports check 1 NOT-TESTABLE / VERDICT INCOMPLETE. MG1S hardware checks 2-8 passed on c19.
  - 19-datasheet-w: W6 and W31 were test bugs (fixed). W18 "no ahubdam card" is REAL and not the kernel version (c19 = c20
    Image): the overlay applied, the card's probe failed with -22 (stream-less DAM DAI refused by soc_new_pcm). Kernel fix
    `fix/sunxi-h616-ahub-dam-aux-card` 61fb5e0e2 (fork, **to merge into test-cumulative**); rerun job 25 blocks until merged.
- Merged, waiting for board: c19 panfrost oops fix (job 18; then release held 08/09/14/15), c21 DE33 vblank latch (job 19-display-tearing).
- Open coding: SPI/I2C target mode (W33, agent running), DE33 writeback connector (W23, agent running).
- DONE 2026-11-06: board-PASS fixes merged into stonking-orangepizero2 = 4effc93e0 (fork; 33 cherry-picks from test-cumulative c35, series.conf order = test-cumulative minus the excluded entries; build-kernel.sh: 863 patches, 0 failed, build exit 0, dtbs exit 0). Excluded: DE33 writeback 1b4c0f53b/6dbed6c18/300d79df7/30706dcc8 (job 40 pending), G2D 04964f921/3f6c487d3 (PARKED), trial-kbase 8951051f6/861d14ca3, vdec-untranslated 084fcccca+revert aa6e29312, empty c307dd053. Next: the user runs ./build-all.sh OPIZ2_WIFI_REGDOM=US and the runner reflashes via harness/REFLASH.md.
- DONE 2026-11-06: DE33 writeback (jobs 40-42 PASS on c35) added to stonking-orangepizero2 = 60401afbf (4 commits, build-checked: 866 patches, 0 failed); image branch = c35 minus G2D.
- DONE 2026-11-06: I2C target (job 44 PASS on c37: i2c aliases c6ce58c59 + slave-eeprom OF autoload b7b01b931) added to stonking-orangepizero2 = c36a2e787 (build-checked 868 patches, 0 failed); image branch = c37 minus G2D. Open: W33 loopback items need user jumpers.
- Kernel package versions: follow Armbian (26.11.0-trunk REVISION); the OPi5 "+board.N" scheme does not apply here (user 2026-11-06).
- Runner failures 2026-11-06 (next code agent, one at a time):
  - G2D PARKED (user 2026-11-06, until more credits): job 36 on c31 shows the mixer registers dead (ip 01010100: rtmx 0 vsu 0), ROT engine works. Next: one research agent over other vendor repos/BSPs on how they use the H616 G2D, if any vendor code drives the mixer on H616, fix our driver to match; otherwise ship what the HW can do (ROT rotate/flip) - no user decision needed. harness/research/g2d/RESULTS.md.
  - c27 jobs 28-32 (2026-11-06): 29-g2d STALLED (first conversion step, board unreachable ~2 min); 32-ve-encoder STALLED (first step after probe, board unreachable ~5 min); c27 boot WARN mc-device.c:619 media_device_register_entity from cedrus_probe+0x398 (encoder registration) -> code agent "m2m stalls" running.
  - 30-de33-writeback (c27): every flip+writeback atomic commit -EINVAL, nothing captured; xr30 dumb buffer -EINVAL.
  - 31-spi-i2c-target (c27): SPI set PASS (spidev1.0 present); I2C set: i2c3 does not probe with sit-i2c3-slave overlay (status okay, overlay applied, not deferred, no dmesg).
  - 28-panfrost-softstop2 (c27): kernel fix works (stress/vk/vklong/intops/reg PASS, no oops); tdim package bug (quick_2d not a test name); math-a/b Mesa multi-queue race; img3d timeout + "Unhandled Page fault in AS0 at VA 0xB2F8000", JOB_BUS_FAULT js=1.
  - 16-kbase-traces (c20): trace step rc 139 (segfault); probe PASS except dmesg; stalled 90 min in restore (ssh, see harness item).
  - 19-display-tearing (c24): seq_gaps 1 in four of six runs (stock d4/d12 too, so a test artefact is possible); 60 flips/s, rest PASS.
  - 20-spi-i2c-target (c24, no jumpers): no /dev/i2c-3, no 3-1064, no /dev/spidev1.0: overlays did not take effect (check overlay
    names/apply in the package vs. the dtbo names).
  - 21-de33-writeback (c24): BLOCKED "no Writeback-1 connector / de33_wb_* parameters", but c24 contains 6dbed6c18: the connector
    init (non-fatal) most likely failed at probe: real bug, read the job's dmesg.
- Harness: kbase-traces.sh ssh hung 1.5 h across a board reboot (23:52, no crash on serial); every runner package's ssh needs
  ServerAliveInterval/CountMax + a timeout, and the stall watchdog must fire on it (killed PID by hand 2026-11-06 01:16).
- Shared with OPi5 (2026-11-06): (1) MPEG-4 VOL LOW_DELAY flag (OPi5 drafts on k16-mpeg4): when final, cedrus refuses interlaced B-VOPs in try_ctrl and FFmpeg 0302 becomes per-device; (2) take OPi5 FFmpeg 0314 "mpegvideo_motion: mirror the 16x8 block of field qpel" (~/orangepi5/work/_out/media-debs/patches/ffmpeg/0314-*.patch, copy only).
- AFBC (job 51, 2026-11-06): the H616 Mali-G31 has NO AFBC (AFBC_FEATURES 0x10001), so a GPU import is NOT TESTABLE. Next route for a bit-exact AFBC check: scan out the cedrus AFBC capture on a DE33 plane and capture it with the writeback connector (jobs 40-42 PASS), compared with the linear decode.
- AFBC bit-exact DONE (job 54 PASS on c39, 2026-11-06): HEVC 8/10-bit + VP9 P0/P2 AFBC == linear (interior, 24/24 frames).
  HEVC VE writes AFBC 4 lines down (hw property, vendor nTopCrop=4) -> kernel 8b1f787fe fix/sunxi-cedrus-h265-afbc-compose
  (compose rect top=4) + FFmpeg hwcontext compose crop (harness/afbc-wb/ffmpeg-v4l2request-compose.diff).
  TODO: cherry-pick 8b1f787fe into stonking AFTER the user's current build; add the FFmpeg diff to the desktop FFmpeg
  package patches. Open: real-hevc8 linear-pass writeback -EIO (-5) on 2-3 of 12 frames (jobs 53+54); AVS2 AFBC offset
  unverified (no host encoder).
- Writeback -EIO under VE DRAM load: retry fix 20e682fc2 (fix/sunxi-h616-de33-wb-retry) in c40 (6d124e150): job 55 PASS
  (real-hevc8 x5: 2-5 OVERFLOW captures each, all retried, 0 lost, 0 wb_errors; syn regression PASS). TODO with 8b1f787fe:
  cherry-pick into stonking AFTER the user's build.
  New: c40 build shows 17 dtc warnings (A64/H5 board dts, c39 had 0) - find which cumulative change/tool caused them.
  Package built 2026-11-06: harness/afbc-wb (client + lossless flat-chroma-tile synthetic streams), runner job 53-afbc-wb (c38, no kernel change); pass = AFBC captures bit-identical to linear away from chroma-tile edges (the DE33 scaler uses another chroma phase for AFBC). State: harness/research/afbc-wb/RESULTS.md.
- Next items: stateful v4l2jpegdec hang (after job 11 gstdebug), remaining M/L datasheet items (W22 encoder SPEC, W26, W12, W24, W29, W25 G2D).

### C. Needs hardware from the user
10. HDMI display (HDMI 4K60, HDMI audio, CEC, AFBC 4K60 output), TV (CVBS), 13-pin expansion board (IR, line-out,
    2 extra USB ports), USB stick (USB host + USB boot), USB-C data cable (gadget mode, FEL), the HP M277dw (end-to-end
    print test), a metering plug (suspend power saving). WiFi 5 GHz DFS STA + header I2C/SPI/UART loopbacks can be
    done with what is here.

### D. Waiting for the user's go
11. Send the upstream items in docs/upstream-queue.md.
12. Open the Armbian PRs (docs/prs/README.md).
