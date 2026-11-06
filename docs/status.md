# Orange Pi Zero2: hardware bring-up status

Date: 2026-11-06 (table + work list updated). Image on the board: Armbian-unofficial 26.11.0-trunk, Ubuntu 26.10 (stonking), Linux 7.3.1-edge-sunxi64,
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
| USB boot / netboot | PARTIAL | Netboot OK: SPI U-Boot PXE-boots the flasher (harness/reflash.sh). USB boot built (all host ports), needs a stick. |
| DRAM 1 GB | OK | |
| CPU DVFS 480–1512 MHz | OK | speed bin speed3; sustained 1512 MHz under 4-core stress. |
| Thermal | OK | CPU passive 85 °C (cpu0-3), hot 100, critical 110; GPU passive 85 °C via devfreq cooling. |
| cpuidle | OK | Native PSCI CPU_SUSPEND in TF-A + `cpu-sleep` idle state; 30-min soak PASS. |
| Suspend to RAM | OK | Native SYSTEM_SUSPEND: DRAM software self-refresh (STAT 0x223), 100/100 rtcwake cycles with cpuidle, 200 MB tmpfs hash intact. Power saving not measured (Meross MSS110 has no metering). |
| VDD-SYS (vdd-gpu-sys) | OK | Floor 900 mV: at 810 mV (GPU devfreq idle) 4K VE decode corrupted 6/13 runs; 0/6 at ≥ 890 mV. |
| Ethernet 1 GbE (RTL8211F) | PARTIAL | Jumbo frames up to MTU 2018 fixed (0e2765af5, in the image). Dead-RX boots fixed with `rgmii-rxid` (10/10 cold boots RX OK). **Open:** on the current debug kernels, bulk host→board TCP over end0 (scp, `ssh cat`) stalls at exactly 512 KiB while the same file passes over WiFi; 8000-byte pings lose ~33 % after ~1 h uptime. Small packets and ssh fine; RX/TX error counters 0, 6 TX drops. Neither retested on the image kernel. Forced 10/100 + iperf3 not tested. |
| WiFi UWE5622 (SDIO) | PARTIAL | Scan 2.4 + 5 GHz OK. 5 GHz SoftAP fixed (driver never passed the channel): hostapd ch36 → VHT80 MCS9, iperf3 128 Mbit/s host→board, 96.5 board→host; 2.4 GHz AP 31.5 / 41.4 Mbit/s; wpa_supplicant AP works on both bands. Regdomain from cfg80211 (all countries); image sets it with `OPIZ2_WIFI_REGDOM` (2c5dd06). Firmware always picks the widest 20/40/80 MHz block. STA association + iperf as station to test. |
| Bluetooth (UWE5622, UART) | PARTIAL | Blob-free: in-kernel vendor init + stock `btattach`. Board <-> host (BlueZ 5.87, 2026-11-05): discovery both ways, SSP pairing + bond, bond and BD address EA:97:B0:2B:A9:EE kept over a reboot, reconnect OK; L2CAP 4 MB host->board 190 kB/s, board->host 165 kB/s; RFCOMM 4 MB host->board 180 kB/s, 0 loss; LE advertising + LE scan both ways. **Open:** LE connection/GATT (host uses LL privacy; test with a phone). Blob kept as fallback (`vendor_init=0`). |
| USB host (3× EHCI/OHCI) | OK\* | Controllers up; no device plugged in yet. |
| USB-C | PARTIAL | Gadget mode untested (power-only cable). Host mode via overlay `sun50i-h616-usb-otg-host` (needs board powered from the header). |
| HDMI video | OK\* | Pipeline bound; no display yet. Blend-mode warnings fixed (0). |
| HDMI audio | OK\* | ALSA card present; needs a display. |
| Analog audio | OK\* (line-out) | DAC-only by hardware (no MIC). Needs expansion board. |
| GPU Mali-G31 (panfrost) | PARTIAL | devfreq 306–600 MHz. GLES 3.1 PASS; Vulkan 1.0 subset 0 regressions and OpenCL fixes PASS with the Mesa fork (jobs 46/50/52, fork not in the image yet). No AFBC on this GPU. GLES 3.2 / Vulkan 1.1 open. |
| Video decode (Cedrus) | PARTIAL | Bit-exact: MPEG-2, H.264, HEVC, VP8, VP9 P2, HEVC Main10. H.264 4K 42.0 fps (spec 4K30 OK); HEVC 8-bit 4K 81.8 fps, 6K 30.2 fps; HEVC Main10 4K 24.5 fps and VP9 P2 4K 35.6 fps via P010, vs. spec 4K60 (4K60 met via AFBC; AFBC output bit-exact vs. linear, job 54); Main10 6K OOM. Uses Jernej Skrabec's unposted H616 work. |
| AVS2 decode | PARTIAL | New cedrus uAPI + backend: 8-bit bit-exact on 17 streams, 4K Main10 58.5 fps; 10-bit only self-consistent; no FFmpeg path yet (harness avs2dec). |
| Video encode (H.264, JPEG) | PARTIAL | New cedrus stateless H.264 encoder (CAVLC, I+P) in the image; job 39 PASS on 7 sizes. JPEG encode not done. `harness/research/ve-encoder/`. |
| Crypto engine + TRNG | OK | `/dev/hwrng` = CE TRNG. U-Boot CE TRNG → KASLR seed built; board check of KASLR pending. |
| RTC / watchdog | OK | No backup battery; sunxi-wdt 16 s, systemd watchdog 15 s. |
| IR receiver | TODO | On the expansion board; overlay `orangepi-zero2-expansion`. |
| TV-out CVBS | OK\* | New sun8i_tve driver, build-tested; needs a TV. |
| PWM | OK\* (overlay) | Overlays for PH2/PH3 (header pins 8/10) apply cleanly; PWM3/PWM4 on PH0/PH1 now release UART0 (debug console) — fix on `fix/sunxi-h616-pwm-uart0-pins`. PI variants collide with RGMII on this board. |
| I2C / UART / SPI / GPIO headers | OK\* (overlay) | Overlays present; loopback tests to do. |
| LEDs, PMIC AXP305 | OK | No dummy regulators left for spi-nor / phy-io. |
| Print server (CUPS) | OK\* | CUPS 2.4.16, ipp-usb, HPLIP, drivers installed; no printer attached yet. |

## 2. Armbian fork (github.com/SomeComputerGuy/build)

- `stonking-orangepizero2` (c36a2e787): integration; the current images come from it (board-PASS commits only).
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
it flashes whichever variant was built last. Desktop variant (`./build.sh OPIZ2_VARIANT=desktop`, GNOME): server + desktop + the v4l2-request FFmpeg; `./build-all.sh` builds all three. Minimal/server ship no ffmpeg (Ubuntu's 8.1.2 has no v4l2-request hwaccel).

## 3. Work list (rewritten 2026-11-06; old notes in [status-history.md](status-history.md))

Mode: LOW-CREDIT (one agent at a time, runner included). Per-task state: each task's RESULTS.md and memory file.
Test kernels: cumulative cN on test-cumulative (kernel-check/cumulative-kernels.txt); newest c43 (c65ef3449).
Image branch stonking-orangepizero2 = 452cdd53f (+ DE33 tearing/writeback 5 commits + panfrost map unwind on 90b5e7da2;
build-checked 878 patches, 0 failed, 0 warnings, pushed to fork 2026-11-06). Desktop FFmpeg 0320 compose crop added (rev 5, 81d1c2a).

### A. Running
- Nothing on the board. User's image build (90b5e7da2) running.
- DONE 2026-11-06: DE33 tearing + writeback, job 62 PASS on c47 (2dc70409e): 0 torn/wrong/stale captures in all runs, events
  held 100 %, 0 late/forced latches (base), every lost capture accounted by reason (kernel == client), VE+mem load real.
  Branch fix/sunxi-h616-de33-latch-event: 8af646391, 93b00281a (display), 3e0255e2f, 906968398, 825596b48 (writeback).
  -> in stonking 452cdd53f.
- DONE 2026-11-06: panfrost failed-map unwind a524d09da (fix/sunxi-panfrost-mmu-map-enomem): job 63 PASS on c48 (6 memcg-OOM
  rounds, OOM hit, 0 WARN/oops, GPU alive; GLES31/KHR/OpenCL 0 regressions, 2 drawelements cases OOM->Pass). -> in stonking 452cdd53f. State: harness/research/display-tearing/RESULTS.md.

### B. Image integration (after the user's current build_all; the main armbian-build checkout stays untouched until then)
1. Cherry-pick the board-PASS kernel fixes into stonking-orangepizero2 (-x, build-check):
   8b1f787fe H.265 AFBC compose offset (job 54) · 20e682fc2 writeback retry (job 55) · 950c46035 cedrus JPEG drain on
   DEC_CMD_STOP + fbba781aa S_FMT with CAPTURE buffers left (job 57; fixes every v4l2sl* resolution change since c10)
   DONE 2026-11-06 = 90b5e7da2 (in the running build). Tearing+writeback (job 62 PASS) = next build, see A.
2. gst-plugins-good1.0 patches 0101 (1:4:0:0 JPEG colorimetry) + 0102 (sysmem when the peer answers ANY) into
   scripts/build-media-debs.sh; keep the MARGINAL rank for v4l2jpegdec, fix its "hangs" comment in image-integration.patch.
3. DONE: FFmpeg compose crop = patches/ffmpeg/0320 (applies fuzz 0 on the image series), ffmpeg rev 5.
4. Rebuild images, then runner reflash (harness/REFLASH.md, server image) + verify-board.sh. Also closes job 24 check 1
   (gstreamer1.0-libav in every variant).
5. Vulkan step 1 (user go 2026-11-06: "get the Vulkan support running"): ship the Mesa fork (mesa-work/mesa-cl
   panfrost-opencl-fixes 0e274280595: RGB overfetch, G31 ballot/WMASK, A8 texel buffers; board PASS jobs 46/52) as the
   image's Mesa in all variants, and set PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 system-wide (panvk = Vulkan 1.0 on G31).
   Checks: vulkaninfo/vkcube on the board, GNOME desktop still renders (GTK4 renderer choice), GLES/OpenCL no regressions.
   Fork GitHub repo still to be created by the user (build from the local tree until then).

### C. Coding queue (one fresh agent at a time, in order)
6. Ethernet: bulk host->board TCP stalls at exactly 512 KiB and 8000-byte pings lose ~33 % after ~1 h (seen on debug
   kernels); retest on the image kernel first. Jumbo fix 0e2765af5 (max_mtu 2018) is in the image.
7. panfrost: WARN in panfrost_mmu_map under memcg OOM: WARN gone since da59f9208 (c39+); unwind fixes a524d09da in c48,
   runner job 63-panfrost-map-enomem queued (harness/research/panfrost-map-enomem/RESULTS.md).
8. Job 16 kbase trace step segfault (rc 139); harness ssh needs ServerAlive + timeout seen by the stall watchdog
   (kbase-traces.sh hung 1.5 h across a reboot).
9. JPEG greyscale decode: fold in the 11-03 probe result.
10. MPEG-4 ASP 3840x2160 decode acceptance test (datasheet-checklist).
11. Datasheet W-items W22, W26, W12, W24, W29 (docs/datasheet-checklist.md; harness/research/datasheet-w/RESULTS.md).
12. AVS2: AFBC offset unverified (no host encoder); 10-bit only self-consistent; FFmpeg hwaccel missing (harness avs2dec
    only); test1.avs2 md5 mismatch; also AVS/AVS+ and MPEG-1 hwaccels for the desktop FFmpeg.
13. OPi5 cross-check follow-ups (harness/research/opi5-crosscheck.md): port OPi5 fixes 1407, 0514, 1102, 1103, 2206,
    1913 (+ suspend test); deinterlacer to V4L2_CID_DEINTERLACING_MODE, DI300 private IDs to a reserved range;
    MPEG-4 VOL LOW_DELAY flag when the OPi5 draft is final; take OPi5 FFmpeg 0314 (copy only).
14. Upstream GStreamer bug: v4l2videodec swallows not-negotiated on the output thread (EOS with no frame).
15. GLES 3.2 in panfrost (fork branch panfrost-gs-tess; Arm blob traces, then GS/tess lowering, then KHR-GLES32).
16. Vulkan step 2 = Vulkan 1.1 on G31 (user go 2026-11-06; FIRST coding item after the tearing work): Mesa
    ba09d293e54 (version gate) in the fork, full vk-main at 1.1 (~14 h, resumable runner package), fix failures.
    2 create_device_global_priority cases still fail (as before). Step 3 later: scope 1.2+ features vs. G31 hardware.
17. Bluetooth LE connect + GATT (needs a phone; the host's LL privacy blocks a host test).
18. Optional Armbian PR: pre-existing dtc warnings in sun50i-a64-pine64-7inch-lcd.dtso and the nanopi-r1s-h5 rtl8153 patch.

### D. Deferred (performance; function first)
- Mesa fork ~10 % GLES slowdown. VP9 Profile 2 P010 4K at 59.0 fps (IOMMU micro-TLB; IOMMU stays on; 4K60 met via AFBC).

### E. Parked
- G2D (W25) until credits are back: H616 mixer registers dead (job 36), ROT works. Next: vendor-repo research agent;
  vendor drives the mixer -> fix ours, else ship ROT-only (no user decision). harness/research/g2d/

### F. Needs hardware from the user
- HDMI display (4K60, HDMI audio, CEC, AFBC 4K60 output), TV (CVBS), 13-pin expansion board (IR, line-out, 2 USB),
  USB stick (USB host + USB boot), USB-C data cable (gadget, FEL), HP M277dw (end-to-end print), metering plug
  (suspend power), jumpers for the W33 / header I2C-SPI-UART loopbacks; second board's console in serial.log.

### G. Waiting for the user
- Report when ./build-all.sh is done (then B). Create the Mesa fork GitHub repo.
- Go for upstream items (docs/upstream-queue.md) and the Armbian PRs (docs/prs/README.md).

### Done 2026-11-06 (board PASS)
- Jobs 39 encoder (7/7 sizes), 40-42 DE33 writeback, 44 I2C target, 46 RGB overfetch + tdim, 50 GLES advanced blend
  (kernel soft-stop), 52 G31 subgroup/A8 INSTR_INVALID_ENC, 54 AFBC bit-exact (HEVC 4-line offset), 55 writeback retry,
  57 stateful JPEG + resolution change. Summaries: harness/runner-queue/done/.
