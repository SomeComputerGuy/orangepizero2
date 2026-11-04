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
| Bluetooth (UWE5622, UART) | PARTIAL | Blob-free: in-kernel vendor init + stock `btattach`; hci0 up, BR/EDR + LE scan OK. Pairing and LE 5.0 features to test. Blob kept as fallback (`vendor_init=0`). |
| USB host (3× EHCI/OHCI) | OK\* | Controllers up; no device plugged in yet. |
| USB-C | PARTIAL | Gadget mode untested (power-only cable). Host mode via overlay `sun50i-h616-usb-otg-host` (needs board powered from the header). |
| HDMI video | OK\* | Pipeline bound; no display yet. Blend-mode warnings fixed (0). |
| HDMI audio | OK\* | ALSA card present; needs a display. |
| Analog audio | OK\* (line-out) | DAC-only by hardware (no MIC). Needs expansion board. |
| GPU Mali-G31 (panfrost) | PARTIAL | devfreq 306–600 MHz. GLES 3.2 / OpenCL 2.0 exposure not yet verified. |
| Video decode (Cedrus) | PARTIAL | Bit-exact: MPEG-2, H.264, HEVC, VP8, VP9 P2, HEVC Main10. H.264 4K 42.0 fps (spec 4K30 OK); HEVC 8-bit 4K 81.8 fps, 6K 30.2 fps; HEVC Main10 4K 24.5 fps and VP9 P2 4K 35.6 fps via P010, vs. spec 4K60 (AFBC 10-bit path unmeasured); Main10 6K OOM. Uses Jernej Skrabec's unposted H616 work. |
| AVS2 decode | GAP | No uAPI, driver or userspace anywhere. Research/implementation in progress. |
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

## 3. Next

0. Hardware the user has to supply: HDMI display, 13-pin expansion board, USB stick, USB-C data cable, TV, printer,
   metering plug.
1. Rebuild the image from the rebased integration; retest Ethernet bulk TCP + large pings on the image kernel.
2. Full board matrix: WiFi STA 2.4/5/DFS + iperf3, BT pair, HDMI + audio + CEC, line-out, USB host + USB boot,
   USB-C gadget, IR, PWM/I2C/SPI overlays, KASLR, GPU GLES/OpenCL.
3. Decode: AFBC 10-bit 4K60; AVS2. Encoder: §1.
4. Open the Armbian PRs (user sends/approves).
5. **Queued for when tokens are back (added 2026-11-04 ~18:30, start ≈ 2026-11-05 03:30): OPi5 / RK3588S cross-check.**
   One agent (fable if available, else Opus), read-only on both trees. Sources: the other project at ~/orangepi5
   (read only, never modify it or its memory) and its GitHub repos. Compare every patch / branch we carry
   (armbian-build fork branches, sunxi-7.3 series, U-Boot/TF-A, userpatches, Mesa fork mesa-work/mesa, FFmpeg
   drafts in docs/upstream-queue.md) against theirs. Answer:
   - What can we use from them (patches/fixes that apply to H616, Mali-G31 panfrost, generic Armbian/Ubuntu
     stonking, build framework, kernel 7.3 core, V4L2 stateless/request API, FFmpeg/GStreamer, Mesa)?
   - What can they use from us?
   - Common code both sides changed (Armbian framework/lib, stonking release support, kernel core/media/drm,
     Mesa panfrost, FFmpeg v4l2-request, U-Boot common, TF-A): are the changes compatible, conflicting, or
     duplicated? Anything we would send upstream must not conflict with or contradict theirs.
   - Recommended actions: which patches to share/port, which to merge into one common version, upstream
     submission order, and owner (us / them / joint).
   Output: a report in harness/research/opi5-crosscheck.md, with feedback in both directions; no changes to
   either tree until the user approves.
