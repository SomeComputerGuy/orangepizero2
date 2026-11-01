# Orange Pi Zero2 — hardware bring-up status

Date: 2026-11-01. Image: Armbian-unofficial 26.11.0-trunk, Ubuntu 26.10 (stonking), Linux 7.3.1-edge-sunxi64, U-Boot 2026.10, TF-A lts-v2.14.11. Board booted from SD, tested over serial (ttyUSB1/ttyOPIZ2) and the 10.56.0.0/24 test link.

Legend: **OK** verified on the board · **OK\*** driver present, not functionally verified · **PARTIAL** works with a known gap · **MISSING** no working driver.
Rule: every board feature the hardware has must work, whether or not the print-server install uses it.

## 1. Where we are

| Area | Status | Evidence / notes |
|---|---|---|
| Boot: SPL → TF-A → U-Boot → kernel | OK (new U-Boot, board-tested from SD) | SPL→kernel 6.5 s (was 8.5 s). "Failed to set core voltage" root cause: BL31 leaves the AXP305 in RSB mode, SPL only spoke I2C → on warm reboots the CPU stayed at 408 MHz through firmware. Fixed with RSB support in SPL. FAT env probe removed (ENV_IS_NOWHERE). All 6 USB host controllers scanned in parallel (1.5 s). |
| SD card (mmc0) | OK | SDHC, 4-bit, 50 MHz high-speed (3.3 V only on this board, so no UHS). |
| SPI NOR 2 MB (mtd0) | OK (board-tested) | U-Boot written with flashcp + read-back verify; with the SD bootloader invalid the BROM boots "sunxi SPI" and U-Boot boots Linux from SD. Fallback chain SD → USB → PXE → DHCP → prompt reached in ~11 s. USB boot (all ports incl. expansion header) and netboot: to test with a stick / TFTP server. |
| DRAM 1 GB | OK | |
| CPU DVFS 480–1512 MHz, speed bin | OK | `sun50i_cpufreq_nvmem: speed bin speed3`; sustained 1512 MHz under 4-core stress, no throttling. |
| Thermal (cpu/gpu/ve/ddr zones) | FIXED (pending image) | Vanilla trips 60/70 °C had no cooling maps → CPU never throttled, only 110 °C shutdown protected it. Now passive 85 °C mapped to cpu0-3, hot 100, critical 110. GPU cooling map follows (GPU OPP now merged). |
| cpuidle | MISSING | `current_driver: none`. H616 has no ARISC; TF-A reports `PSCI: Suspend is unavailable`; no `idle-states` in DT. Needs TF-A CPU_SUSPEND work. |
| Suspend (s2idle) | PARTIAL | `freeze` works: 11 s round trip with RTC wake, WiFi suspends/resumes, SSH alive. Shallow only (cores WFI); no deep sleep possible without TF-A support. systemd sleep disabled by Armbian default. |
| Ethernet 1 GbE (RTL8211F) | OK | 1000/full, checksum offload. Minor: `Too many address, switching to promiscuous` (small MAC filter) — upstream 7.4 dwmac-sun8i fixes to pull. |
| WiFi (UWE5622, SDIO) | OK | Acceptance bar (user): SSID scan. Sees 2.4 + 5 GHz networks; AP mode supported. Driver pin was 13 commits behind (memory corruption on unload, OOB key write, rfkill oops, TCP stall) → bumped; 5 GHz regulatory fix + service hardening in progress. |
| Bluetooth (UWE5622, UART) | PARTIAL | hci0 up, BR/EDR+LE scan finds devices. Depends on vendor `hciattach_opi` blob; `bt_wake` DT warning every boot. |
| USB host (3× EHCI/OHCI) | OK\* | Controllers up; nothing was plugged in yet. |
| USB-C | PARTIAL | Peripheral (gadget) mode is the default and required; untested so far (power-only cable). Host mode works only when the board is powered from the GPIO header 5 V pins and the device is attached with a cable/adapter that ignores CC (CC pins are tied to GND; VBUS then comes from the header supply) — delivered as a DT overlay (dr_mode host + EHCI0/OHCI0), test in that setup. |
| HDMI video (DE33/TCON/HDMI PHY) | OK\* | Pipeline bound, connector present; no display attached yet. 6× "pixel format with alpha ... blend mode not setup" warnings. |
| HDMI audio | OK\* | ALSA card present (vendor AHUB); untestable without display. |
| Analog audio codec | OK\* (line-out) | Playback-only by hardware: H616 codec is DAC-only (UM §8.4.1), Zero2 schematic has no MIC net, Orange Pi user guide: "does not support MIC Input". Line-out untested (needs expansion board). |
| GPU Mali-G31 (panfrost) | PARTIAL | Works; fixed 432 MHz, **no OPP table → no DVFS**. Fix in progress. |
| Video decode (Cedrus) | **OK** | MPEG-2/H.264/HEVC/VP8 all decode bit-exact; 1080p H.264 150 fps, 1080p HEVC 310 fps, 720p ~230–350 fps, IRQ-count-verified. Upstream H616 variant (adds IOMMU/SRAM) to pull in. |
| Video encode (VE H.264) | **MISSING** | No open driver exists anywhere; vendor blob only. Dedicated reverse-engineering effort started (see §3). |
| Crypto engine (sun8i-ce) + TRNG | OK | AES/DES3/SHA offload registered; `/dev/hwrng` = CE TRNG. |
| RTC | OK | Works; no backup battery on board (fake-hwclock + NTP). |
| Watchdog | OK | sunxi-wdt, 16 s max. systemd watchdog config added to build (15 s). |
| IR receiver | PARTIAL | Only HDMI-CEC rc device; the H616 IR block is not enabled in the Zero2 DTS (overlay exists). Need to confirm whether the Zero2 has an on-board receiver or only the header pin. |
| PWM | OK\* (overlay) | `pwm@300a000` disabled by default; overlays `sun50i-h616-pwm1..4-*` exist (vendor driver). A mainline-style driver (v10 series) is pending upstream. |
| I2C / UART / SPI on headers | OK\* (overlay) | Overlays present for i2c0–4, uart2–5, spidev, spi-nor only on spi0 by default. |
| GPIO | OK | Two gpiochips (32 + 288 lines). |
| LEDs | OK | green:power, red:status (heartbeat). |
| PMIC AXP305 | OK | All rails present; some supplies (`vcc-pl`, `phy-io`, spi-nor `vcc`) use dummy regulators — DT cleanups. |
| TV-out (CVBS) | OK\* (new driver, build-tested) | New sun8i_tve DRM driver + DE33 YUV output + TCON-TOP clock select; PAL/NTSC; enabled by overlay `orangepi-zero2-expansion` (also IR). Needs a TV on the header TV-OUT pin. |
| Deep sleep / cpuidle | MISSING | No ARISC/SCP on H616, so this needs TF-A PSCI CPU_SUSPEND/SYSTEM_SUSPEND work for H616. Required, not optional. |
| Print server (CUPS, drivers) | OK\* | CUPS 2.4.16, ipp-usb, HPLIP, all 20 printer-driver packages installed; printer not attached yet. |

## 2. Fixes made to the Armbian framework (fork: github.com/SomeComputerGuy/build)
Integration branch `stonking-orangepizero2`; one PR branch each:
- `feat/distro-ubuntu-stonking` — add Ubuntu 26.10.
- `fix/uboot-sunxi64-host-tools-openssl4` — U-Boot host tools vs OpenSSL 4 (needs widening to all `v2026.10*` dirs before PR).
- `fix/apt-utils-upstream-pkg-fallback` — base-files lookup falls back to the distro Packages index.
- `fix/rootfs-armbian-gpg-symlink-on-host` — uutils `ln -f` needs /dev/urandom (absent in early chroot).
- `fix/rootfs-dbus-launch-helper-guard` — path gone on 26.10.
- `fix/uwe5622-bump-driver-pin` — WiFi driver to armbian/uwe5622 master.

Board-level config lives in `userpatches/` (this repo): wait-online `--any`, systemd watchdog, `sprdwl_ng disable_powersave=1`, CUPS sharing, extra tools.

## 3. Work in progress (fable agents, isolated worktrees)
- **Kernel pull-ins** (`wt-kernel`): dwmac-sun8i upstream fixes; upstream Cedrus H616 variant + VE node; GPU OPP/DVFS; USB-C host overlay; IR decision; pending-upstream PWM v10 / UART FIFO v5 / AHUB v1 evaluation; s2idle + DPM-watchdog backports.
- **WiFi/BT** (`wt-wifi`): compile-check new pin; 5 GHz regulatory fix; service hardening; power-save policy; bt_wake DT; design note for blob-free Bluetooth.
- **Video encoder RE** (`harness/research/ve-encoder/`): prior art (linux-sunxi RE, jemk/cedrus h264enc, Bootlin encoder work, vendor cedar_ve GPL driver), blob acquisition + static analysis plan, clean-room V4L2 encoder plan. Acceptance bar: equal or better than the vendor blob (PSNR/SSIM at matched bitrate, fps, latency, features), root-cause any gap.

## 4. Remaining after that (ordered)
0. Hardware queue (user-supplied setups): USB-C host mode with board powered from header 5 V (single supply, on Test Plug 2); HDMI display; 13-pin expansion board; USB-C data cable; printer.
1. Rebuild image with all pull-ins; flash; run `harness/verify-board.sh` (to write) + full test matrix (WiFi STA 2.4/5/DFS + iperf3, BT pair, HDMI + HDMI audio + CEC with a display, line-out, USB host devices, USB-C gadget, IR, PWM/I2C/SPI overlays, SPI-NOR boot, soak).
2. U-Boot: AXP305 CPU-rail (SPL voltage warning); silence FAT env probe.
3. cpuidle / suspend: TF-A H616 CPU_SUSPEND (idle states) — real project; decide scope.
4. Analog mic capture: port from vendor sun50iw9-codec (no mainline source).
5. TV-out CVBS: vendor-only; lowest priority.
6. Encoder: execute §3 plan (PoC → V4L2 M2M driver → GStreamer/ffmpeg → upstream).
7. Thermal trip review; DT dummy-regulator cleanups; DRM blend-mode warnings.
8. Printer: attach, verify driverless + HPLIP paths, LAN sharing; document.
9. Armbian PRs for §2 (user sends/approves).
