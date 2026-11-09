# Orange Pi Zero2 (Allwinner H616) Armbian image

Armbian image for the Orange Pi Zero2: Ubuntu 26.10 ("stonking"), Linux 7.3.x (Armbian `edge`), U-Boot 2026.10,
CUPS print/scan server. Variants: minimal, server, desktop (GNOME).

## Build

    git clone https://github.com/SomeComputerGuy/orangepizero2 && cd orangepizero2
    git clone -b stonking-orangepizero2 https://github.com/SomeComputerGuy/build armbian-build
    ./build-all.sh OPIZ2_WIFI_REGDOM=US          # all three variants
    ./build.sh OPIZ2_VARIANT=server OPIZ2_WIFI_REGDOM=US   # one variant (minimal, server, desktop)

Run as a normal user (Armbian asks for sudo itself). Images land in `armbian-build/output/images/`.
Flash: `sudo ./flash-sd.sh /dev/sdX` (newest image; run without a device to list candidates).

## Contents

- `userpatches/` — Armbian build profile.
- `patches/` — FFmpeg, mpv, GStreamer and Mesa patches for the media packages.
- `scripts/build-media-debs.sh` — builds those packages; `build.sh` runs it.

License: GPL-2.0-only.

## Testing

Verified on the board (2026-11-09 image, kernel 7.3.3): boot, SD, SPI NOR, DVFS, thermal, suspend, Gigabit Ethernet, WiFi, Bluetooth,
GPU (GLES 3.1, Vulkan 1.1 full dEQP-VK with 0 regressions, OpenCL 3.0), hardware video decode
(MPEG-2, H.264, HEVC incl. Main10 4K60 and 6K30, VP8, VP9 incl. resolution changes, AVS2, JPEG) and H.264 encode. Not yet tested: HDMI output, USB devices, end-to-end printing.
