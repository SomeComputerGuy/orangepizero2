# Orange Pi Zero2 — official spec acceptance checklist
Source: http://www.orangepi.org/html/hardWare/computerAndMicrocontrollers/details/Orange-Pi-Zero-2.html (fetched 2026-11-02; HTTPS refuses, use HTTP).
Every row must work and be board-verified against the stated number. Status: OK = verified; TODO = not yet verified; WIP = work in progress; GAP = no driver yet.

| Spec item | Status | Notes |
|---|---|---|
| CPU H616 quad A53 | OK | DVFS 480–1512 MHz; cpuidle + suspend-to-RAM (DRAM self-refresh) PASS incl. 100-cycle soak; clean firmware verified; merge pending |
| GPU Mali G31 MP2, OpenGL ES 1.0/2.0/3.2 | TODO | panfrost + devfreq OK; verify GLES version exposed by Mesa (glmark2-es2 / es2_info / eglinfo); 3.2 must be reached |
| GPU OpenCL 2.0 | TODO | Mesa rusticl on panfrost; clinfo + a conformance subset |
| Decode H.265 Main10@L5.1 4K@60 / 6K@30 | WIP | Cedrus 8-bit 1080p OK; 10-bit + 4K: vdec agent |
| Decode VP9 Profile 2 4K@60 | GAP/WIP | vdec agent (Hantro G2-like block?) |
| Decode AVS2 JiZhun 10-bit 4K@60 | GAP/WIP | vdec agent |
| Decode H.264 BP/MP/HP@L4.2 4K@30 | WIP | 1080p 150 fps OK; 4K throughput to verify |
| Encode H.264 BP/MP/HP 4K@25 / 1080p@60 | GAP | encoder effort (last), harness/research/ve-encoder/SPEC.md |
| Encode JPEG snapshot 1080p@60 | GAP | encoder effort (last) |
| DDR3 1 GB | OK | |
| TF card | OK | |
| 2 MB SPI flash | OK | U-Boot boot from SPI verified |
| Ethernet 10/100/1000 | PARTIAL | 1000 OK; RX-dead boots root-caused (RGMII RX delay) + DT fix rgmii-rxid pending image; then ≥10 cold boots + forced 10/100 tests |
| WiFi 802.11 a/b/g/n/ac (859 chip) | PARTIAL | scan 2.4+5 GHz OK; STA association + ac rates + iperf to test |
| BT 5.0 | PARTIAL | hci0 up, scan OK; LE 5.0 features + pairing to test |
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
