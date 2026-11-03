# Orange Pi Zero2 — official spec acceptance checklist
Source: http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/details/Orange-Pi-Zero-2.html (fetched 2026-11-02; HTTPS refuses, use HTTP).
Every row must work and be board-verified against the stated number. Status: OK = verified; TODO = not yet verified; WIP = work in progress; GAP = no driver yet.

| Spec item | Status | Notes |
|---|---|---|
| CPU H616 quad A53 | OK | DVFS 480–1512 MHz; cpuidle + suspend-to-RAM (DRAM self-refresh) PASS incl. 100-cycle soak; clean firmware verified; merge pending |
| GPU Mali G31 MP2, OpenGL ES 1.0/2.0/3.2 | PARTIAL | image 2026-11-02: Mesa 26.2.4 exposes GLES 3.1, renderer reports MC1 (spec MP2); devfreq 306–600 MHz OK; GLES 1.0: not shipped by user decision 2026-11-03 (follow Ubuntu, which builds Mesa with -Dgles1=disabled since Debian 17.0.0 "Drop libgles1"; Mesa's ES1 path exists but is not compiled); GLES 3.2: Mesa GS/TS work in progress (route A); MP2: silicon has one core (SHADER_PRESENT=0x1), close pending user decision. Details harness/research/impl-gpu-spec.md |
| GPU OpenCL 2.0 | PARTIAL | rusticl: OpenCL 3.0, OpenCL C 1.2, 1 CU; 2.0 optional-feature coverage + conformance subset pending (GPU agent) |
| Decode H.265 Main10@L5.1 4K@60 / 6K@30 | PARTIAL | 8-bit 4K 81.8 fps, 6K 30.2 fps bit-exact; Main10 4K: AFBC10 83.9 fps, P010 60.3 fps bit-exact (patch 30, merged cf62ac65a, not yet in image); 60 Hz display needs DE33 AFBC scanout (Stage A in progress); Main10 6K OOM |
| Decode VP9 Profile 2 4K@60 | PARTIAL | runs on the VE (no G2 on H616); AFBC10 84.2 fps; P010 57.1 fps bit-exact (<60); display needs DE33 AFBC scanout |
| Decode AVS2 JiZhun 10-bit 4K@60 | WIP | clean-room uAPI + cedrus_avs2 + test decoder written, merged cf62ac65a; first board tests running; no 10-bit reference decoder exists (verification method: user decision pending); WQ/background pictures untested (no streams) |
| Decode H.264 BP/MP/HP@L4.2 4K@30 | OK (pending image) | 42.0 fps tiled, bit-exact 300/300 |
| Encode H.264 BP/MP/HP 4K@25 / 1080p@60 | GAP | encoder effort (last), harness/research/ve-encoder/SPEC.md |
| Encode JPEG snapshot 1080p@60 | GAP | encoder effort (last) |
| DDR3 1 GB | OK | |
| TF card | OK | |
| 2 MB SPI flash | OK | U-Boot boot from SPI verified |
| Ethernet 10/100/1000 | PARTIAL | 1000 OK: image kernel iperf3 ~870–910 Mbit/s both ways, 27-min soak clean, no 512 KiB stall; RX-dead fixed (rgmii-rxid); forced 10/100 + long soak deferred to the end |
| WiFi 802.11 a/b/g/n/ac (859 chip) | PARTIAL | a/g/n/ac STA + 2.4/5 GHz AP (VHT80 125 Mbit/s) verified, 3 driver fixes in image; 11b-only not forceable (firmware); VHT80 STA + DFS need user's 80 MHz AP |
| BT 5.0 | PARTIAL | hci0 up without the vendor blob (in-kernel init + btattach), scan OK; LE 5.0 features + pairing to test |
| Micro HDMI 2.0a 4K@60 | TODO | needs display; also HDMI audio + CEC |
| TV CVBS PAL/NTSC (13-pin board) | TODO | new sun8i_tve driver built; needs TV |
| Audio: HDMI | TODO | needs display |
| Audio: 3.5 mm via 13-pin board | TODO | line-out; no MIC by hardware (spec says "no MIC") |
| Power Type-C 5V3A | OK | |
| 3× USB 2.0 host (2 via 13-pin board) | TODO | on-board port + both expansion ports, incl. USB boot |
| 26-pin header I2C/SPI/UART/GPIO | TODO | overlays present; loopback tests |
| 13-pin header: 2× USB, IR, TV-out, audio, 3 GPIO | TODO | |
| Debug UART | OK | |
| Power + status LEDs | OK | |
| IR receiver (13-pin board) | TODO | overlay orangepi-zero2-expansion |

## Vendor findings to apply (from harness/research/orangepi-build-mining.md, 2026-11-02)
- HDMI 4K@60: vendor 594 MHz PHY uses OPMODE_PLLCFG 0x1A7C (ours 0x1a40) + PHY reg 0x17=0x8006; try if 4K@60 fails.
- HDMI audio: mixer `I2S1OUT Switch` on, `I2S1 Src Select = APBIF_TXDIF0`; expect first-open glitch (vendor primes with a wav).
- USB: vendor `sun50i-h616-usb0-host.dts` overlay; vendor 6.1 DTS enables ehci1-3/ohci1-3 for 13-pin ports — verify ours.
- IR: Orange Pi remote NEC addr 0xfe01 → `ir-keytable -p nec -t`, scancodes 0xfe01xx.
- BT: GPL hciattach_sprd.c source in orangepi-build → build to replace closed hciattach_opi blob.
- GPU: no vendor Mali-G31 userspace; stay panfrost + rusticl. Vendor OPPs 306–600 MHz @ 950 mV as fallback.
- Line-out: vendor lineout_vol 0x1a.
- Encoder: T527 glibc libvencoder/libvenc_h264/libvenc_jpeg (DWARF) = A/B oracle candidate.
- VP9: likely Cedar VE (libawvp9HwAL), not Hantro G2 — routed to vdec agent.
