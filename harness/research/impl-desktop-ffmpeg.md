# Desktop image variant + v4l2-request FFmpeg (status.md item 6)

Status: 2026-11-05. Patch set final and shared with orangepi5; debs built (+opiz2.2 / mpv +opiz2.1) and board-tested on c3/c9; desktop image not built yet (compile.sh needs sudo, see §5).

## 1. Desktop variant

- `./build.sh OPIZ2_VARIANT=desktop` (and `./build-all.sh`: minimal, server, desktop). One config file:
  `userpatches/config-opiz2-printserver.conf`. Desktop = server (BUILD_MINIMAL=no, NetworkManager, chrony,
  armbian-config) + BUILD_DESKTOP=yes. Kernel, U-Boot, BSP, printer + scan stack, rusticl/libclc, SD-wear fstab,
  WiFi regdomain and TUNING_PROFILE=none are the same hooks as on the other variants.
- **DE: GNOME** (user decision 2026-11-05, same as Armbian's standard orangepizero2 desktop image: armbian/os
  `userpatches/targets-release-community-maintained.yaml`, target `gnome-desktop-stable-ubuntu`):
  `DESKTOP_ENVIRONMENT=gnome`, `DESKTOP_ENVIRONMENT_CONFIG_NAME=config_base`,
  `DESKTOP_APPGROUPS_SELECTED=browsers,chat,desktop_tools,editors,email,internet,languages,multimedia,office,programming,remote_desktop`.
  One switch: `OPIZ2_DESKTOP_DE=xfce` (any configng DE). The current framework (config-desktop.sh) maps a non-empty
  DESKTOP_APPGROUPS_SELECTED to `DESKTOP_TIER=full` (LibreOffice, GIMP, Inkscape, Audacity, VLC, ...);
  `DESKTOP_TIER=mid|minimal` on the command line overrides it.
- **stonking in armbian/configng:** the desktop YAML (`tools/modules/desktops/yaml/*.yaml`) lists no stonking release.
  The host-side DE list (`--list-json stonking arm64`) is only consulted when DESKTOP_ENVIRONMENT is empty, but the
  in-chroot install (`armbian-config --api module_desktops install`, rootfs-create.sh) uses the YAML packaged in
  armbian-config: for an unknown release it only warns and installs without the release block, and the `browser`
  token stays unresolved. Fix without touching the framework or cache/: hook `custom_apt_repo__opiz2_desktop_stonking_configng`
  (runs at rootfs-create after the armbian-config extension added the configng apt source, before the desktop
  install) installs armbian-config and runs `userpatches/desktop/configng-add-release.py <yaml> stonking resolute`
  (every mapping with a `resolute` key gets an identical `stonking` entry). With `SKIP_ARMBIAN_REPO=yes` it also drops
  apt.armbian.com-only packages (chromium, code, armbian-imager) and Ubuntu's snap-transitional .debs (firefox,
  thunderbird, chromium-browser) and uses epiphany-browser. Checked against the stonking arm64 Packages index: all 70
  packages of the resolved GNOME full tier exist (`kernel-check/dl-configng`).
  Upstream form (comments kept, no local deltas): `docs/prs/configng/0001-desktops-add-Ubuntu-26.10-stonking-as-a-copy-of-reso.patch`
  (held, docs/upstream-queue.md).
  The rootfs cache name does not include this hook: after changing it, delete `cache/rootfs/rootfs-arm64-stonking-gnome-desktop-*`.

## 2. FFmpeg / mpv packages

- Method (coordinator: reuse the orangepi5 build's): `scripts/build-media-debs.sh`, adapted from
  `~/orangepi5/scripts/build-media-debs.sh` (rootless `mmdebstrap --mode=unshare` + qemu-user, `apt-get source`,
  patches appended to debian/patches/series, `dpkg-buildpackage`, ccache copied in/out). Changes: ffmpeg + mpv only,
  version suffix `+opiz2.<rev>`, own ccache (`~/.cache/opiz2-media-ccache`, seeded once by copying the opi5 one),
  build stamp (version, rev, patch files, script) so an unchanged source is not rebuilt; output `out/debs-media`
  (flat apt repo). `build.sh` runs it first for the desktop variant.
- Packages: Ubuntu's own `ffmpeg 7:8.1.2-2ubuntu2` and `mpv 0.41.0-2ubuntu5` source packages, so every library,
  feature and ABI is the archive's (both flavours incl. -extra), plus `--enable-v4l2-request --enable-libudev`.
- Image: hook `post_repo_customize_image__opiz2_desktop_media` copies the repo to `/opt/opiz2-media`, adds it as a
  `file:` apt source, pins `*+opiz2*` at 1001 (`/etc/apt/preferences.d/opiz2-media.pref`), upgrades every installed
  package that has a +opiz2 build, installs mpv + ffmpeg, checks the versions, and sets `hwdec=v4l2request,auto-safe`
  in `/etc/mpv/mpv.conf` (Ubuntu ships `hwdec=vaapi`). minimal/server: no FFmpeg.
- GStreamer: hardware path is v4l2codecs (`gstreamer1.0-plugins-bad`, already in every variant); gst-libav has no
  hwaccel support and stays software.

### 2.1 FFmpeg patch series (`patches/ffmpeg`, README.md + SHA256SUMS there)

Base decision (user, 2026-11-05): Kwiboo's PR 20847 series is the base, one ordered set shared byte-identically with
orangepi5. `patches/ffmpeg` is a copy of `~/orangepi5/work/_out/ffmpeg-shared/patches` (35 patches + debian/0001 +
README.md, verified with its SHA256SUMS; git: `kernel-check/ffmpeg-deb/src` branch `opiz2/shared` = their `final`,
9dbb2de on n8.1.2):

| range | source |
|---|---|
| 0001-0011 | Kwiboo PR 20847 head 3ac4e07593 (newest revision; via Kwiboo v4l2-request-n8.1), opi5 `Link:` trailers |
| 0012-0013 | opi5 HEVC SPS RPS controls (no-op on cedrus); ffbuild race fix backport |
| 0101-0102 | Kwiboo n8.1: AFBC_16X16_SPLIT (Jernej), BROADCOM_SAND128 |
| 0201-0208 | Jernej v4l2request-mpeg4 a56a208: VC-1 fixes + VC-1/WMV3, MPEG-4 Part 2/H.263/Spark hwaccels |
| 0301-0308 | ours: MPEG-4 field-direct, ilace-B fallback, GMC1 rshift, MPEG-1, AVS1/AVS+, native AVS2 decoder + AVS2 |
| 0309-0311 | shared glue (opi5): D-pictures only to hwaccels with HWACCEL_CAP_MPEG1_D_PICTURES; FATE vc1test_smm0005 ref; fate-source headers |
| 0312 | ours, adopted by opi5: `#ifndef` fallbacks for V4L2_PIX_FMT_YUV420_{8,10}_AFBC_16X16_SPLIT ('AS12'/'AS01') |
| debian/0001 | --enable-v4l2-request --enable-libudev |

0312: 0101 builds its AFBC table entries only when linux/videodev2.h defines the fourccs; Ubuntu's linux-libc-dev does
not, so without 0312 the packaged build had no AFBC path (10-bit VP9/HEVC/AVS2 capture). FATE 5343/5343 with and
without it (opi5). All 35 apply with fuzz 0 in the deb build (dpkg-source). MPEG-1: unlike orangepi5 (stock hantro
ignores the MPEG-1 flag, they configure --disable-hwaccel=mpeg1_v4l2request) we keep the hwaccel: our image always
ships the cedrus kernel with the MPEG-1 uAPI.

## 3. New hwaccels

AVS2 (native hwaccel-only decoder + `avs2_v4l2request`), AVS/AVS+ (`cavs_v4l2request`), MPEG-1 (`mpeg1_v4l2request`):
see impl-desktop-ffmpeg-avs2.md and impl-desktop-ffmpeg-avs.md (sub-agent reports) and §4.

## 4. Board results

Board 2026-11-05 13:42-14:05, cumulative kernel **c3** (test-cumulative 0122ff6a7, `7.3.1 #3`, Image md5 aa76859d),
lock `desktop-ffmpeg`. Binary: static dev build of `opiz2/shared` (= the shared set incl. 0312;
`harness/ffmpeg/dev-build.sh`, md5 648a1716), driver `harness/ffmpeg/shared-rerun.sh`, outputs
`kernel-check/ffmpeg-deb/board/out-c3/`. HW decode via `-hwaccel v4l2request -hwaccel_output_format drm_prime` +
hwdownload (a software fallback fails the run), VE IRQ count per stream.

| codec | stream(s) | result |
|---|---|---|
| H.264 High 4K30 | h264-high-2160p30 | md5 300/300; 29.3 fps (300 f / 10.24 s, DRM_PRIME) |
| HEVC Main 4K60 | hevc-main-2160p60 | md5 600/600; 33.2 fps |
| VP9 P0 4K60 | vp9-p0-2160p60 | md5 600/600; 56.8 fps |
| VP8 1080p60 | vp8-1080p60 | md5 300/300 |
| H.264 1080i MBAFF | h264-high-1080i-mbaff | md5 300/300 |
| VC-1 AP | SA00040/50, SA10091, SA10143, SA20021, ilaced_twomv | md5 6/6 PASS |
| WMV3 MP | SMM0015 | md5 25/25 |
| WMV3 MP B-frames | SMM0005 | **24/24 = patched SW decoder and = FATE ref 0310** (17/24 only against stock Ubuntu FFmpeg, whose B-picture MV pull-back was wrong: impl-legacy-decode §3.1 is resolved, the hardware was right) |
| MPEG-1 | ccm1 | md5 129/129 bit-exact |
| MPEG-1 | MEI.stream16, MEI.stream16v2, tcela-16, tcela-19 | max 2/2/3/2 against envelope 2/2/3/2 |
| MPEG-1 D-pictures | tcela-18 (31 D) | **31/31 bit-exact** against m1-dpic.py, through stock 0304+0309 (31 VE IRQs) |
| MPEG-1 1080p30 | mpeg1-1080p30 | max 3, envelope 3 (60 frames) |
| MPEG-2 1080i | mpeg2-mphl-1080i30 | max 3, envelope 3 |
| MPEG-4 ASP qpel/B | mpeg4-asp-bf-qpel-1080p60 | max 4, envelope 4 |
| MPEG-4 SP / Spark / H.263 | 1080p60 / 1080p60 / 4CIF | max 3 / 3 / 3, envelope 3 / 3 / 3 |
| MPEG-4 ASP interlaced B | mpeg4-asp-ilace-1080i30 | software fallback by design (0302), 0 VE IRQs |
| AVS (bunny) / AVS+ 1080i | bunny.mp4, avsplus-1080i-testcard.ts | framecrc + framemd5 60/60 and 5/5 identical to FATE refs |
| AVS cavs.mpg | pre-final AVS revision | black (engine limitation, known: impl-desktop-ffmpeg-avs.md) |
| AVS2 8-bit | 12 PKU + 5 xavs2 streams | 17/17 bit-exact (whole-stream md5 where given + per frame); 1080p ParkScene 171 fps |
| AVS2 4K | main-2160p-ra / cctv4k-10bit (Main10) | 20/20 / 292/292 bit-exact; 29.8 / 56.0 fps |

GStreamer: v4l2codecs v4l2sl* decoders rank 257 (primary+1), so playbin uses the hardware already (earlier session).
Server image idle RAM: 967 MB total, 152 MB used.

### 4.1 Packaged debs (ffmpeg 7:8.1.2-2ubuntu2+opiz2.2, mpv 0.41.0-2ubuntu5+opiz2.1), kernel c9

Board 17:33-18:10, cumulative **c9** (test-cumulative aa6e29312, `7.3.1 #12`, installed with
harness/research/vdec-perf/install-kernel.sh, fallback armed and confirmed). The debs were installed the way the image
hook does it (file: repo + pin) and removed afterwards (`harness/ffmpeg/mpv-board-test.sh`, outputs
`kernel-check/ffmpeg-deb/board/out-c9-mpv/`, `out-c9-deb/`).

- Packaged libavcodec62 / libavcodec-extra62: all 14 v4l2request hwaccels (av1 avs2 cavs flv h263 h264 hevc mpeg1 mpeg2
  mpeg4 vc1 vp8 vp9 wmv3); libavutil60 contains the AFBC fourccs (0312 works with Ubuntu's linux-libc-dev).
- `/usr/bin/ffmpeg` from the deb: H.264 4K 300/300, HEVC 4K 600/600, VP9 4K 600/600, VP8 300/300, MBAFF 300/300,
  MPEG-1 ccm1 129/129, tcela-18 D-pictures 31/31 bit-exact, SMM0005 24/24 = FATE ref, AVS2 cctv4k-10bit 292/292 = c3 run.
- mpv `--hwdec=v4l2request --vo=gpu --gpu-context=drm`: zero-copy (`VO: [gpu] 3840x2160 drm_prime[nv12]`, one VE IRQ
  per frame) for H.264/HEVC/VP9 4K and MPEG-2 1080i; `auto-safe` picks v4l2request too (our mpv patch). No monitor is
  attached, so the HDMI connector was forced on (`/sys/class/drm/card0-HDMI-A-1/status`, 1024x768 fallback mode): the
  numbers are for 4K scaled down to 1024x768 on the Mali-G31 (panfrost, simple_ondemand 306-600 MHz):
  - default mpv profile: 300 4K frames in ~65 s untimed (4.6 fps), 4K30 timed: 226/300 dropped. The GPU scaler
    (default dscale), not the decoder (VE 29-57 fps), is the limit.
  - `--profile=fast`: 300 4K frames in 13.6 s (22 fps), 4K30 timed: 73/300 dropped.
  - GStreamer `v4l2slh264dec ! kmssink`: 4K30 file in 10.8 s with sync (real time, with QoS drops), 16.2 s without sync
    (18.5 fps); `! fakesink` 7.1 s (42 fps decode).
  So: hardware decode of 4K is real time; 4K *presentation* through the GPU is not, and needs a real 4K/1080p sink
  (EDID mode, DE33 plane scaling/overlay without GPU composition) to judge. mpv on the desktop: use profile=fast.
- Fixes found on the board and committed (72e041e): apt 3.3.3 ignores `Pin: version *+opiz2*` ("Did not understand pin
  type version", priority stays 500) -> `Pin: origin ""`; mpv's default `hwdec-codecs` leaves out mpeg2video (and every
  cedrus-only codec) -> image mpv.conf gets `hwdec-codecs=all`.
- Idle RAM: server image on c9 after the tests 193 MB used of 967 MB. GNOME idle RAM needs the desktop image (§5).

## 5. Open

- **Desktop image not built.** `./build.sh OPIZ2_VARIANT=desktop` needs compile.sh's sudo, which this agent does not
  have (`sudo -n` refuses). Debs are ready in `out/debs-media` (build.sh skips them via the stamp); expected output
  `armbian-build/output/images/Armbian-unofficial_*_Orangepizero2_stonking_edge_7.3.1_gnome_desktop.img`. Not flashed.
  After it: GNOME idle RAM and 4K playback in the session (mpv, Totem/GStreamer) on a real monitor.
- 4K presentation: GPU-scaled output is the bottleneck (§4.1); check DE33 plane scaling for zero-copy NV12 (kmssink /
  a Wayland compositor's direct scanout) with an EDID 1080p/4K sink.
- The packaged mpv (+opiz2.1) was built against the +opiz2.1 libraries (same ABI); no rebuild needed.
- AVS cavs.mpg (pre-final AVS) black, AVS2 test1_avs2.mkv VE timeouts: cedrus/engine, not FFmpeg (sub-reports).
- Upstream: all FFmpeg patches held (docs/upstream-queue.md rows 1-4, 7-9); MPEG-1 needs a discoverable kernel
  capability before an RFC (row 7). configng stonking PR held (row 6).
