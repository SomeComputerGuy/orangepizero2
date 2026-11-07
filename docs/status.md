# Orange Pi Zero2: hardware bring-up status

Date: 2026-11-07 (table + work list updated). Image on the board: Armbian-unofficial 26.11.0-trunk server, Ubuntu 26.10 (stonking), Linux 7.3.3-edge-sunxi64 (build-all.sh 2026-11-06, job 69),
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
| GPU Mali-G31 (panfrost) | PARTIAL | devfreq 306–600 MHz. GLES 3.1 PASS; Mesa fork (+opiz2.1) in every variant since 2026-11-07: Vulkan 1.0 (panvk, PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 set system-wide), OpenCL 3.0 (rusticl) PASS on the image (job 69). No AFBC on this GPU. Vulkan 1.1 under test (job 68); GLES 3.2 open. |
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
Test kernels: cumulative cN on test-cumulative (kernel-check/cumulative-kernels.txt); newest c48 (b82264f81).
Image branch stonking-orangepizero2 = e79177038 (9ba317178 = armbian/build main merged, kernel 7.3.3, + fix/build-warnings:
0 C/modpost/dtc warnings on a clean check build; pushed to fork). Desktop FFmpeg 0320 compose crop added (rev 5, 81d1c2a).
Mesa fork: github.com/SomeComputerGuy/mesa, branch panfrost-opencl-fixes (mesa-26.2.4 + 32 commits, 9d278fabfc2).

### A. Running
- Job 68 (Vulkan 1.1 full dEQP-VK) DONE 2026-11-07 21:xx: 64/64 parts, 3,247,552 cases: Pass 684,180, NotSupported
  2,562,827, Fail 526 (504 = glsl.texture_functions *offset* + texturequerylod), Crash 9 (parts 45/46/57; 8 js faults),
  QualityWarning 8, ResourceError 2; 8 INSTR_INVALID_ENC lines; vs system Mesa 1.0 main1in100: 1 regression, 482 fixed.
  --check FAIL 3 (d9), 7, 8, 9. Summaries: harness/runner-queue/68-vk11-main.chunk-{1,3}.summary.md.
- Coding: Opus agent on item 16 (classify + fix job 68's failures in the fork, then queue runner job 70-vk11-fix).
- Board idle (LOW-CREDIT: the coding agent is the one agent).

### B. Image integration (DONE 2026-11-07: built by the user, board check job 69 PASS)
1. DONE: board-PASS kernel fixes (AFBC compose offset, writeback retry, cedrus JPEG drain + S_FMT with CAPTURE buffers
   left, DE33 tearing/writeback, panfrost map unwind) are in stonking-orangepizero2.
2. DONE: Armbian upstream merged (120 commits, merge base 2026-11-01): branch merge/upstream-2026-11-06 = 9ba317178
   (pushed to fork; the main checkout's stonking-orangepizero2 fast-forwarded to it). One conflict: uwe5622 ref, took
   upstream bd3da409fa33 (= our f88cd0d25ff6 + its Linux 7.4 build fix). Upstream also adds OVERLAY_PREFIX for
   sun50iw9, multi-prefix overlays in boot-sun50i-next.cmd, KERNEL_CVE_PATCHES (off by default). Kernel now 7.3.3.
   Build check (build-kernel.sh, KVER=7.3.3): 879 patches applied, 0 failed, build exit 0, 0 C warnings, dtbs exit 0,
   17 dtc warnings = all the pre-existing pine64-7inch-lcd / nanopi-r1s-h5 ones, 61 h616 overlays.
3. DONE: scripts/build-media-debs.sh builds ffmpeg, mpv, gst-plugins-bad1.0 (patches/gstreamer), gst-plugins-good1.0
   (patches/gst-plugins-good1.0 0101-0102, job 57) and mesa (patches/mesa = fork 0e274280595, 28 patches, fuzz 0),
   all by default, emulated arm64 (qemu-user) as before. The build stamp covers only the marked build recipe, so
   comment/source-list edits don't force rebuilds. build.sh runs it for every variant (unchanged sources are skipped).
   A Mesa cross build was tried (user request 2026-11-07) and is blocked by packaging: llvm-22-dev:arm64 ->
   llvm-22-tools:arm64 -> python3-yaml:arm64 conflicts with the native python3-yaml, so LLVM's -dev packages cannot
   be co-installed for a cross build. Attempt kept in harness/research/image-integration/mesa-cross-build-attempt.patch.
4. DONE: image config. /opt/opiz2-media repo in EVERY variant (post_repo_customize_image__opiz2_media): gst-bad/-good +
   Mesa everywhere, ffmpeg/mpv desktop only; only installed packages are replaced and checked (+ each source must have
   replaced at least one). PAN_I_WANT_A_BROKEN_VULKAN_DRIVER=1 in /etc/environment, /etc/environment.d and the
   system/user DefaultEnvironment. v4l2jpegdec stays MARGINAL (comment now gives the caps-routing reason, not "hangs").
   vulkan-tools/mesa-utils/kmscube/clinfo were already in every variant.
5. DONE: user built all three variants (./build-all.sh, kernel 7.3.3 #21); job 69-image-check PASS on the server image
   (2026-11-07): 15 PASS, vkcube/kmscube NOT-TESTED (no HDMI), the gst-libav check SKIP (MG1S enumerates). Its two FAILs
   were check bugs (systemd 261 has no DefaultEnvironment for `systemctl show`; checks now use show-environment;
   verify-board rerun 22/22 PASS). Summary: harness/runner-queue/done/69-image-check.summary.md. Checks were (reflash server image + checks
   0-17: kernel 7.3.3, verify-board, +opiz2 packages, gst elements/JPEG, gst-libav = job 24 check 1, Vulkan env,
   vulkaninfo 1.0.x, vkcube (NOT-TESTED without HDMI), dEQP-VK smoke + subgroups, GLES, OpenCL, dmesg, /root/cts
   restage), then job 68 resumes. Kernel scripts (install/restore-kernel.sh, vdec-fallback.sh, vk11-main.sh) no longer
   assume a 7.3.1 stock kernel. Still open after 69: the GNOME desktop with the variable set (GTK4 renderer choice) on
   a display; older runner packages in harness/research/*/runner still hardcode vmlinuz-7.3.1-edge-sunxi64 in their
   own restore() (only matters if one of them is rerun).
   Mesa fork on GitHub: github.com/SomeComputerGuy/mesa, branch panfrost-opencl-fixes (= mesa-26.2.4 + 32 commits, 9d278fabfc2;
   local remote "github" in mesa-work/mesa-cl). Debs are still built from patches/mesa.

### C. Coding queue (one fresh agent at a time, in order)
6. Ethernet: bulk host->board TCP stalls at exactly 512 KiB and 8000-byte pings lose ~33 % after ~1 h (seen on debug
   kernels); retest on the image kernel first. Jumbo fix 0e2765af5 (max_mtu 2018) is in the image.
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
16. Vulkan step 2 = Vulkan 1.1 on G31 (user go 2026-11-06): version gate + chunk-1 OOM and d9 fixes in fork 9d278fabfc2;
    full run = job 68 (section A). Then: compare with job 52 (1.0), fix the failures (part 15 texture-offset group first),
    fix the d9 --check condition. Step 3 later: scope 1.2+ features vs. G31 hardware.
17. Bluetooth LE connect + GATT (needs a phone; the host's LL privacy blocks a host test).
18. Media debs cross-build (user go 2026-11-07): port scripts/build-media-debs.sh to the persistent chroot
    (~/.local/bin/arm64-chroot), cross-build every media deb, verify each against the archive debs (symbols, files,
    drivers), qemu fallback on any diff (Mesa likely stays emulated: llvm-22-dev:arm64 python3-yaml conflict).
    Runs when the board is idle (LOW-CREDIT).
19. Small clean-ups: the dtc warning fixes for the sunxi-6.18 / 6.12 copies of the pine64-7inch-lcd overlay and
    nanopi-r1s-h5 patch; older runner packages in harness/research/*/runner hardcoding vmlinuz-7.3.1 in restore();
    desktop shared-apt-cache fix ed3655d52 is board-untested (shows at the next desktop rootfs-cache rebuild).

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
- Go for upstream items (docs/upstream-queue.md) and the Armbian PRs (docs/prs/README.md).

### Done 2026-11-07
- Job 69 image check PASS (all variants built, kernel 7.3.3, Mesa fork + gst-plugins-bad/-good +opiz2.1, panvk enabled).
- Job 67 kbase GLES 3.2 traces ALL PASS on c48 (traces feed item 15); job 63 panfrost map unwind PASS on c48 (in the image).
- Build warnings: fix/build-warnings merged (e79177038): xradio/rtl8189es fixes re-applied, pine64-7inch-lcd and
  nanopi-r1s-h5 dtc warnings fixed (250cc9976), ORAS "denied" = cache miss, desktop apt cache; check build = real build.
- Mesa fork published: github.com/SomeComputerGuy/mesa (user go 2026-11-07).

### Done 2026-11-06 (board PASS)
- Jobs 39 encoder (7/7 sizes), 40-42 DE33 writeback, 44 I2C target, 46 RGB overfetch + tdim, 50 GLES advanced blend
  (kernel soft-stop), 52 G31 subgroup/A8 INSTR_INVALID_ENC, 54 AFBC bit-exact (HEVC 4-line offset), 55 writeback retry,
  57 stateful JPEG + resolution change. Summaries: harness/runner-queue/done/.
