# Orange Pi Zero2 (Allwinner H616) Armbian build

A general-purpose Armbian build for the Orange Pi Zero2 (Allwinner H616, 1 GB RAM). The goal is that every feature of
the chip and the board works, and that every fix goes upstream. Until upstream has them, the fixes are carried here.

- Ubuntu 26.10 ("stonking") userspace
- Linux 7.3.x (Armbian `edge` branch plus our patch set; 7.3.4 as of 2026-11-13)
- U-Boot v2026.10, TF-A lts-v2.14.11 with native H616 suspend support
- Mesa 26.3.0 with our Mali-G31 fixes (panfrost, panvk, rusticl)
- FFmpeg, mpv and GStreamer rebuilt with hardware video decoding (V4L2 Request API)

This repository holds the build profile and the userspace patches. The kernel, U-Boot and TF-A patches live in our
Armbian fork, [SomeComputerGuy/build](https://github.com/SomeComputerGuy/build), branch `stonking-orangepizero2`.

## Variants

| `OPIZ2_VARIANT` | Image file | Contents |
|---|---|---|
| `minimal` (default) | `..._minimal.img.xz` | systemd-networkd, no recommended packages |
| `server` | `....img.xz` | Armbian's standard CLI set: NetworkManager, chrony, armbian-config, zsh |
| `desktop` | `..._xfce_desktop.img.xz` (with the default desktop) | server + XFCE desktop + FFmpeg and mpv with hardware decoding |

All three share the kernel, the firmware, the GPU stack (GLES, Vulkan, OpenCL), GStreamer with hardware decoding and
the hardware test tools (v4l-utils, vulkan-tools, clinfo, iperf3, i2c-tools and so on). FFmpeg and mpv are only in
the desktop variant.

The build profile is named `config-opiz2-printserver.conf` after its first use. Besides the board support it installs
a print and scan server in every variant: CUPS with the printer drivers of the Ubuntu archive, ipp-usb, SANE and
Avahi, with CUPS, ipp-usb and saned reachable from the local network. There is no build switch for it. To leave it
out, delete the function `post_family_config__opiz2_printserver_packages` from the profile; the related setup steps
are skipped when the packages are absent.

## Build

    git clone https://github.com/SomeComputerGuy/orangepizero2 && cd orangepizero2
    git clone -b stonking-orangepizero2 https://github.com/SomeComputerGuy/build armbian-build
    ./build-all.sh OPIZ2_WIFI_REGDOM=US                    # all three variants
    ./build.sh OPIZ2_VARIANT=server OPIZ2_WIFI_REGDOM=US   # one variant

Run as a normal user; the scripts ask for the sudo password once. `build.sh` first rebuilds the media and Mesa
packages (`scripts/build-media-debs.sh`: rootless, needs `mmdebstrap` and qemu-user binfmt on the host; unchanged
sources are skipped), then runs Armbian's `compile.sh`. For the desktop variant it also builds two Armbian packages
the desktop install needs and that are otherwise only on apt.armbian.com (`scripts/build-armbian-debs.sh`, same
requirements). Images land in `armbian-build/output/images/`.

Options (append to either command; Armbian's own `compile.sh` options also work):

| Option | Values | Default |
|---|---|---|
| `OPIZ2_VARIANT` | `minimal`, `server`, `desktop` (`build.sh` only; `build-all.sh` builds all three) | `minimal` |
| `OPIZ2_WIFI_REGDOM` | Two-letter country code, e.g. `US` (any case). Sets the WiFi regulatory domain at boot. A 5 GHz access point needs it. Any other value stops the build. | unset: world domain, then follows the access point |
| `OPIZ2_DESKTOP_DE` | Desktop environment of the desktop variant: `xfce`, `gnome` or another one armbian-config offers | `xfce` |
| `OPIZ2_ETH_MTU` | Ethernet MTU fixed at boot, 68 to 4070. Every host on the network segment must use the same MTU. | unset: 1500 |

Flash an image with any SD card writer, or with `sudo ./flash-sd.sh /dev/sdX`. It writes the newest image in
`armbian-build/output/images/` (whichever variant was built last), verifies it, and lists candidate devices when run
without one.

## Working here, not yet in mainline

Mainline status as of 2026-11-13 (Linux 7.4-rc2, U-Boot, TF-A, Mesa and FFmpeg development branches). Everything in
this section is in the current build and was verified on the board, either on an image or on a test kernel carrying
the same patch. "Sent" means submitted upstream and not merged yet.

Much of the video and display work builds on other people's patches that are not in mainline either: Jernej
Skrabec's H616 video engine, deinterlacer and display engine work, Paul Kocialkowski's H.264 stateless encode core,
Emmanuel Gil Peyrot's cedrus JPEG decoder, Jonas Karlman's FFmpeg V4L2 Request API series, and James Hilliard's
H616 UART series. Our patches sit on top of theirs.

### Hardware video decoding

Mainline gained basic H616 video engine support in the Linux 7.4 development cycle. This build adds:

- VP9 profile 0 and profile 2 (10-bit) up to 4K, including resolution changes inside a stream.
- H.265 Main10 up to 4K60, and H.265 up to 6144x3456 at 30 fps. 6K 10-bit plays at half size on this 1 GB board.
- 10-bit output as P010 or compressed AFBC, for H.265, VP9 and AVS2.
- AVS2 (8-bit and 10-bit, up to 4K) and AVS/AVS+, with new kernel interfaces for both.
- MPEG-4 Part 2, H.263 and Sorenson Spark up to 4080x2304; VC-1/WMV9; MPEG-1.
- H.264 4:0:0 (monochrome) streams.
- JPEG decoding in hardware.
- The DI300 deinterlacer.
- FFmpeg and mpv (desktop variant) and GStreamer (every variant) built to use these decoders, with software
  fallback for streams the hardware cannot decode.

Upstream status: the new decoder interfaces (AVS, AVS2, MPEG-1, MPEG-4, VC-1) and our fixes are not sent yet; they
depend on the unposted base work. One fix for the mainline VP8 decoder is sent (linux-media). The FFmpeg hardware
decoding support depends on FFmpeg PR 20847, which is still open; five fixes for it are posted there.

### Hardware video encoding

- H.264 encoder: baseline, main and high profile, CAVLC and CABAC, constant and variable bitrate, up to 4096x4096
  (4K at 36 fps measured).
- JPEG encoder (1080p at 123 fps measured).

Upstream status: not sent. Mainline has no encoder driver for this video engine, and the H.264 stateless encode
interface it uses is itself still under review.

### GPU (Mali-G31)

- Vulkan through panvk: the board reports Vulkan 1.3. Upstream Mesa does not enable panvk on this GPU generation by
  default because it is not conformant; the image enables it system-wide and carries fixes for the failures a full
  Vulkan conformance run found (4-wide subgroups, texel buffer and image layout fixes, crashes).
- OpenCL 3.0 through rusticl, with fixes for OpenCL programs that failed on this GPU (atomics on local memory,
  image and buffer copies, `sin()`/`cos()` with the distribution's libclc).
- Kernel: a GPU job that runs longer than the timeout is paused and resumed instead of the GPU being reset, and
  failed GPU memory mappings are cleaned up correctly.
- GPU frequency scaling (306 to 600 MHz) with thermal throttling, and a supply voltage floor that prevents
  corrupted 4K video decoding while the GPU idles.

Upstream status: the kernel GPU fixes are sent (dri-devel, v2), the device tree changes are sent (v3). The Mesa
fixes are not sent upstream; they are in [our Mesa fork](https://github.com/SomeComputerGuy/mesa).

### Display engine

H616 HDMI output is not in mainline yet; the build gets it from patches the Armbian kernel already carries. On top
of them this build adds the following, verified by capturing the composed picture on the board (no monitor has
been attached yet):

- A writeback connector that captures the display engine's output.
- Tear-free updates: plane and mixer registers are latched at vblank.
- Zero-copy scanout of the decoders' compressed AFBC output, and plane scaling.
- The pixel blend mode property on planes.

Upstream status: not sent; most of it waits for the H616 display support itself to be merged.

### Power management

- CPU idle states and suspend to RAM, implemented natively in TF-A (the H616 has no separate power controller
  firmware). 100 of 100 suspend/resume cycles passed with RTC wake-up.
- Thermal sensor alarm and shutdown interrupts.

Upstream status: the TF-A changes are in review (Gerrit 56325 and 56326). The thermal interrupts are not sent yet.

### Networking

- Gigabit Ethernet receive fix for this board (some boots had no working receive path).
- Jumbo frames up to MTU 4070, and a fix for the receive threshold setting of the Ethernet controller.
- A fix for the Ethernet PHY's 25 MHz clock.
- WiFi and Bluetooth (UWE5622): no mainline driver exists; the build uses the out-of-tree vendor driver with our
  fixes: 5 GHz access point mode, regulatory domain handling for all countries, and Bluetooth start-up without the
  closed vendor helper program.

Upstream status: Ethernet device tree fix sent (v3), jumbo frames sent (net-next, v2; a reworked v3 is queued),
clock fix sent and acked, waiting to be applied. The WiFi and Bluetooth fixes are in an open pull request against
the vendor driver repository (armbian/uwe5622#31).

### Boot and firmware

- U-Boot talks to the power controller over RSB in the SPL, and retries transient memory training failures.
- Kernel address space randomisation (KASLR) seeded from the hardware random number generator in U-Boot.

Upstream status: the RSB and memory training changes are sent to the U-Boot list and wait for review. The random
seed change is not sent to U-Boot yet.

### Crypto engine and other SoC blocks

- Crypto engine: AES-XTS, AES-CTR, AES-CTS, CBC-MAC, 3DES-CTR and HMAC-SHA1/SHA256 in hardware. The engine is slower
  than the CPU's own AES instructions, so the kernel uses these only when asked for by driver name.
- SPI flash dual read.
- The 56-bit high-speed timer and the two A/V sync counters.
- UART FIFO configuration for the H616 (James Hilliard's series, tested here).

Upstream status: AES-XTS sent (v2), SPI dual read sent. The rest is not sent yet. The UART series is posted by
its author.

## Work in progress and pending

None of this is in the build yet unless stated.

GPU
- OpenGL ES 3.2 (geometry and tessellation shaders): in progress. The shaders render on the board; the remaining
  conformance failures are being fixed and retested. The build exposes OpenGL ES 3.1.
- OpenCL 2.0 features (shared virtual memory, generic address space, pipes, device-side enqueue): implemented in a
  fork branch, being tested on the board. The kernel part is already in the build.
- Vulkan 1.3: the full conformance run on the board is in progress.

Video
- H.264 encoder: regions of interest, intra refresh and the 8x8 transform.
- AVS2 background and S pictures: waiting for test streams.
- GStreamer elements for MPEG-4, H.263, Sorenson Spark, AVS and AVS2: in the build. AVS and AVS2 are bit-exact on the
  board for most test streams; MPEG-4, H.263 and Sorenson Spark, and one 8-bit AVS2 stream, are being fixed and
  retested.
- GStreamer H.264 encoder element: it refused every input format with this single-planar encoder; fixed in the
  build, being tested on the board.
- G2D (2D graphics accelerator): the rotation unit works; the mixer does not respond yet.
- Protected video playback in browsers (Widevine): not started.

Display
- 10-bit, YUV 4:4:4/4:2:2/4:2:0 and HDR10/HLG HDMI output: the code is in the build and passes register and
  capture checks on the board; it has not been tested with a real display.
- More than one overlay layer per blend channel, HDMI 3D formats: not started.

Networking
- Jumbo frames up to the datasheet's 16 KB: transmit is fixed on a test kernel (the controller's DMA burst length;
  100,000 frames at MTU 16358 without a loss on the board, and 20,000 over a real link). A continuous stream of
  16 KB frames received from another host still stalls. A receive fix is written (the controller passes a large
  frame on as it arrives instead of after the whole frame, as Allwinner's own driver does) and is about to be
  tested on the board. Until both are proven the limit stays MTU 4070.
- Hardware checksums for frames larger than 1500 bytes: some sizes come out corrupted, so above MTU 1500 the kernel
  computes checksums in software. Not investigated yet.
- An Ethernet receive fix (a frame spread over several buffers was split when memory allocation failed): passed on
  the board, not yet in the image.
- Bluetooth LE connections: waiting for a test device. Wake-up from suspend by WiFi, Bluetooth or USB: not started.
- A mainline WiFi/Bluetooth driver for the UWE5622: long term.

Kernel and system
- Moved to the current Armbian main branch and Linux 7.3.4 on 2026-11-13; the build follows Armbian's newest `edge`
  kernel again. No image built from it yet.
- Crypto engine RSA and ECC; SPI 3-wire mode and frame sizes other than 8 bits.
- PWM capture, I2C DMA transfers, SPI and I2C target (slave) modes: in the build, not yet tested with a real
  signal or a second device.
- Out-of-memory handling on 1 GB: a process that runs out of memory can stall the board until the hardware watchdog
  resets it. Fix not started.
- A deeper idle state that powers off the whole CPU cluster: planned after the TF-A review.

Upstream
- The submissions listed under "Upstream status" below are waiting for review or for a maintainer to apply them.
- Everything marked "not sent" above goes upstream as its dependencies allow.

## Testing

All testing is done on one board, driven over serial, Ethernet and a switched power plug.

- The newest images were built on 2026-11-12. The minimal image passed the full image check (kernel, boot, device
  checks, GLES, Vulkan, OpenCL, hardware decoding, JPEG; display tests not run without a monitor); the server image
  was flashed and booted. The desktop image of that build had no desktop installed; the build is fixed and the
  desktop image is being rebuilt.
- The previous image (2026-11-09) passed the full image check: boot and device checks, GLES, Vulkan, OpenCL,
  hardware decoding, JPEG.
- Verified on the board over the course of the project: boot from SD card and from the SPI flash, network boot,
  CPU frequency scaling, thermal, CPU idle, suspend, Gigabit Ethernet (also 100 and 10 Mbit/s), WiFi client and
  access point on both bands, Bluetooth classic pairing and data transfer, the crypto engine and the random number
  generator, the watchdog.
- Mesa 26.3.0 was compared on the board against the previous 26.2.4 build: no regressions in the GLES, Vulkan and
  OpenCL conformance subsets.
- Video decoders are checked bit-exact against reference decoders where the standard defines exact output.

Not tested yet, mostly for lack of hardware on the test bench: HDMI with a real display (output, audio, CEC),
composite video output, USB devices and USB boot, the 13-pin expansion board (IR receiver, line-out, two USB
ports), header pin loopbacks (I2C, SPI, UART, PWM), Bluetooth LE connections, the desktop on a display, and
end-to-end printing.

## Upstream status

As of 2026-11-13. Nothing is merged in mainline Linux, U-Boot, TF-A or FFmpeg yet.

- Linux kernel, sent and waiting: Zero2 device tree fixes and GPU frequency scaling (v3), Ethernet jumbo frames
  (v2), an Ethernet driver error-path fix, panfrost long-running jobs (v2), crypto AES-XTS (v2), SPI dual read, I2C
  EEPROM-target autoload, cedrus VP8 fix, H616 clock fixes (acked). On hold at a maintainer's request until the H616
  display driver is merged: an IOMMU fault-report fix.
- TF-A: H616 CPU idle and suspend, Gerrit changes 56325 and 56326, in review.
- U-Boot: power controller access over RSB in the SPL, memory training retry, USB hub scan; waiting for review.
- FFmpeg: MPEG-4 software decoder and encoder fixes in pull requests 25898, 25903 and 25978; hardware decoding
  fixes posted on pull request 20847.
- Armbian: pull requests #11308, #11309, #11311 and #11315 are merged; #11310, #11312, #11313, #11314, #11316,
  #11317, #11320, #11321 and #11352 are open.
- Mesa and GStreamer: nothing sent.

## Repository contents

- `build.sh`, `build-all.sh`, `flash-sd.sh`: build one variant, build all variants, write an image to an SD card.
- `userpatches/`: the Armbian build profile (`config-opiz2-printserver.conf`), the image customisation script and
  a helper for the desktop variant.
- `patches/`: patches for the rebuilt packages: FFmpeg, mpv, GStreamer (plugins-bad and plugins-good) and Mesa.
  See `patches/ffmpeg/README.md` and `patches/mesa/README.md`.
- `scripts/build-media-debs.sh`: rebuilds those packages for arm64.
- `scripts/build-armbian-debs.sh`: builds the two Armbian packages the desktop variant needs.

## License

GPL-2.0-only. See `LICENSE`.
