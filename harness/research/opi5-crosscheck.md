# OPi5 (RK3588S) <-> OPi Zero2 (H616) cross-check

Snapshot 2026-11-05 (docs/status.md item 4). Read-only on both trees. Nothing under `~/orangepi5`, its
memory or its GitHub repos was modified, and none of its scripts were run. Our code trees were not changed
either. Earlier, narrower survey (harness/build practices only): `opi5-carryover.md` (2026-11-01). Its
findings still hold and are not repeated here.

Sources read:
- Ours: armbian-build `stonking-orangepizero2` (8546e5fc1) against armbian/build base 27a7f7276; every
  `fix/* feat/* pr/*` branch (list below); sunxi-7.3 `series.conf` (811 patches); U-Boot
  `v2026.10-sunxi64`; TF-A `atf-sunxi64`; Mesa `mesa-work/mesa` (all three branches);
  `kernel-check/scratch-avs2/linux` (avs2..avs2-v5); FFmpeg drafts (`docs/upstream-queue.md`,
  `harness/research/legacy-dec/*.patch`); `harness/research/*.md` (notably ve-encoder/PLAN.md, impl-avs2,
  impl-di-jpeg-avs, impl-vdec).
- Theirs: `~/orangepi5/patches/{linux (479),ffmpeg,gstreamer,gst-plugins-good,mpv,u-boot,tf-a,upstream}`,
  `scripts/build-kernel.sh`, `scripts/build-media-debs.sh`, `work/_out/{TODO.md,hw-gap-analysis.md,
  upstream-send/,armbian/}`, `docs/stateless-encode-uapi-survey.md`, `src/linux` branches;
  github.com/SomeComputerGuy/{orangepi5-mainline (be26e39), linux, libva-v4l2_request (069af09)}.

Method (reproducible, scratch only, `$CLAUDE_JOB_DIR/tmp/xcheck/`, not committed):
1. Their image kernel tree rebuilt exactly as `build-kernel.sh` does: `--shared` clone of their
   `src/linux` (read-only use), temp index, `read-tree v7.3`, `git apply --cached` of all 479
   `patches/linux/*.patch` -> 479/479 apply.
2. Our sunxi-7.3 tree rebuilt with `kernel-check/build-kernel.sh STAGE=patch` from a `git archive` of
   `stonking-orangepizero2` -> 811 applied, 0 failed.
3. Cross-apply with `patch -p1 -F3`: our core-touching patches on their tree, their generic patches on ours.

## 0. Framing

- Different SoCs, different build systems (they: mmdebstrap + Ubuntu-config kernel on v7.3; we: Armbian on
  7.3.1). They still have **no Armbian work** (only the 2026-11-01 audit in `work/_out/armbian/`).
- Real overlap is small and almost all in **V4L2 core/uAPI** (both add stateless controls), **media
  userspace** (FFmpeg v4l2-request, GStreamer v4l2codecs, mpv, libva) and a handful of **generic kernel
  fixes** (PM, cpufreq, devfreq, USB OHCI, SPI, clk-divider, RTC).
- They are already reusing our work: their TODO item 9 (RUNNING, fable, branch `k15-avs2`) ports our AVS2
  uAPI to rkvdec VDPU381. That makes AVS2 a joint uAPI from now on.

---

## 1. What we can use from them

### 1.1 Kernel, generic (all apply cleanly on our sunxi-7.3 tree, 0 fuzz)

| Their patch (patches/linux) | What | Why it matters on H616 | Where it would go |
|---|---|---|---|
| 0514 PM/devfreq: resume at the frequency from before suspend | devfreq core | panfrost on H616 uses devfreq (our GPU OPP table, feat/sunxi-zero2-gpu-opp); we have PSCI SYSTEM_SUSPEND (feat/atf-h616-system-suspend) | patches.backports + series.conf, with our suspend test |
| 1102 cpufreq: defer the unlisted-frequency check on CPU online | cpufreq core | cpufreq-dt / sun50i-cpufreq-nvmem: CPUs come back from SYSTEM_SUSPEND at the TF-A/boot rate | same |
| 1103 usb: ohci-platform: power the root hub PHYs up before resume | USB host | H616 OHCI0-3 are ohci-platform with sun4i-usb-phy | same; test with a printer/scanner attached across suspend |
| 2206 spi: fix runtime PM imbalance on error | spi core | spi-sun6i uses runtime PM (SPI NOR, SPI1 header) | same |
| 1913 clk: divider: don't divide by zero when rounding above the parent to closest | clk core | sunxi-ng `ccu_div.c` calls `divider_determine_rate()`, and sunxi-ng uses ROUND_CLOSEST dividers; relevant to our video-PLL/TVE clock work | same |
| 1905 driver core: fw_devlink: don't report refused sync_state | driver core | log noise only | optional |
| 2227 media: uvcvideo: don't report resubmitting a poisoned URB | uvc | USB webcams on the desktop variant | optional |
| 1920 rtc: don't lose a minute-resolution alarm that rounds into the past | rtc core | sun6i RTC alarm has seconds resolution, so not our bug; harmless | optional |
| **1407 media: v4l2-ctrls: default HEVC SPS chroma format to 4:2:0** (Tharit Tangkijwanichakul, on lore) | v4l2 core | **cedrus has the same failure**: `cedrus.c:90` rejects `chroma_format_idc != 1`, so the zeroed default HEVC SPS fails v4l2-compliance TRY_EXT_CTRLS exactly as on rkvdec | rebase (textual conflict only, see §3.2) into patches.media; offer Tested-by on cedrus |

PM backports `4785d5faa935` (s2idle begin/end) and `33392343c74e` (DPM watchdog) are already in both trees,
byte-identical (§3.1).

### 1.2 Kernel, ideas to port (not patches)

- **VP9 inter-frame resolution change**: their `0606 rkvdec vdpu381 vp9: allow frames smaller than the
  capture format` + `2228 ... don't predict segment IDs ...` + GStreamer `0010 v4l2codecs: vp9: decode
  inter frame resolution changes in place` took fluster VP9 from 232 to 256/305 and made every
  `resize_inter_*` vector bit-exact. Jernej's note on cedrus VP9 (impl-vdec.md) says the remaining profile 0
  failures (64 of 305) are "resolution changes inside inter frames". Port the kernel idea to
  `cedrus_vp9.c` (accept inter frames smaller than the CAPTURE format, decode at top-left with the
  format's stride, check the segmentation map handling) and take their gst 0010.
- Timeout/recovery test method for decoders (KASAN kernel, 3178 forced recoveries, 600 reopen cycles,
  `topics/rkvdec-reset/notes/RESULTS.md`): apply to cedrus and DI300 (DI300 has a job watchdog now).
- Their IOMMU fault-storm handling (2234-2238, rockchip-iommu) vs our sun50i-iommu rate-limit + sibling
  reset: same problem, different drivers; no code to share, keep the log/rate-limit style consistent.

### 1.3 Media userspace (directly usable for the desktop variant, status item 6)

| Theirs | Use for us |
|---|---|
| `scripts/build-media-debs.sh`: rootless (`mmdebstrap --mode=unshare` + qemu binfmt, no sudo), ccache-seeded, Ubuntu source packages + `patches/<src>/*.patch` appended to `debian/patches/series`, version `+opi5.N`, flat apt repo + apt pin | Exactly our constraints (no sudo, no Docker, caching rule #1). Copy the approach into our repo (not run from theirs), suffix `+opiz2.N`. Note `kernel-check/ffmpeg-deb/` (2026-11-05) already unpacks the same `ffmpeg_8.1.2-2ubuntu2`. |
| `patches/ffmpeg/0001-0011` (Kwiboo's v4l2-request series = code.ffmpeg.org PR 20847), `0012` HEVC SPS ST/LT RPS (theirs; probes the controls, no-op on cedrus), `0013` ffbuild fix, `debian/0001` (`--enable-v4l2-request --enable-libudev`) | Base for our FFmpeg deb (see §3.5 for the base question). |
| `patches/gstreamer/0001,0002` (v4l2codecs caps per registered device / restrict sink caps), `0009` (h264/h265 decoder release pending output), `0010` (VP9 resize) | Our fluster runs use `GStreamer-*-V4L2SL-Gst1.0`; these change our numbers. kmssink 0003-0008 are generic too. |
| `patches/gst-plugins-good/0006` (v4l2transform colorimetry), `0008` (v4l2object: no colorimetry probe for compressed formats), `0010` (bufferpool error buffer) | 0006 for DI300 through v4l2convert/v4l2transform; 0008 for cedrus JPEG through v4l2jpegdec (our JPEG path is not request-based). |
| `patches/mpv/0001-0003` (v4l2request hwdec + drmprime interop + auto-probe) | mpv on cedrus. |
| github.com/SomeComputerGuy/libva-v4l2_request `opi5/main` (megi's 1.2 + 14 of their commits + debian packaging with `panfrost_drv_video.so` link) | VA-API for browsers on the desktop variant. megi's driver started on cedrus; their HEVC SPS-RPS path is per-device ("support decoders that need the SPS RPS tables"), "advertise 10-bit profiles only when frames can be handed out" matters for our P010/AFBC10. Needs a cedrus run before shipping. |
| `patches/firefox/0001` (Bug 2080696, allow V4L2 stateless decoders), `patches/chromium/0001` | Browser hw decode, desktop only. |

### 1.4 Video encode direction (important)

Our `harness/research/ve-encoder/PLAN.md` §1.4 (2026-11-01) concludes "stateless encoder uAPI not merged;
a **stateful** M2M encoder with in-kernel RC is the mergeable route today" and plans Phase B as a stateful
cedrus encoder. Their survey (`~/orangepi5/docs/stateless-encode-uapi-survey.md`) found what our plan
missed: **Paul Kocialkowski's 2026-05-22 `[PATCH 00/14] media: Add V4L2 H.264 stateless encode and VC8000E
support`** (non-RFC v1, v2 in progress 2026-09-24), kernel-driven hybrid: generic
`v4l2-h264-enc{,-rbsp,-rc}.c` in v4l2-core (headers, CBR/CQ/direct-QP rate control, DPB in the kernel).
That is precisely the "hybrid" our plan says maintainers want, it already exists, a second implementation
is reported (Trimarchi, PX30 Hantro H1), and Paul is a Cedrus co-maintainer. They carry it as
`patches/linux/0801-0809` and build rkvenc/hantro H.264 encode on it; their own HEVC stateless encode
uAPI is `0811-0817`.

Action: re-plan the cedrus H.264 encoder (Phase B) on Paul's uAPI + helpers instead of a stateful
driver. 0801-0809 apply on our tree with 0 fuzz. A stateful cedrus encoder sent to linux-media while
the same user sends rkvenc on Paul's stateless uAPI would argue against ourselves.

### 1.5 Other

- U-Boot / TF-A: nothing to take (rk3588-only: dwc_ahci PHY lookup, A76 clocks, PHP CRU gate).
- Mesa: they carry **no Mesa patches** (stock Ubuntu 26.10 Mesa with panthor); nothing to take.
- Process: their `upstream-send/` per-series directories with `TESTMAP.md`/`SERIES.md` are a good model
  for our `docs/upstream-queue.md` once it grows past the FFmpeg items.

---

## 2. What they can use from us

| Ours | For them | Notes |
|---|---|---|
| **Legacy stateless decode uAPIs**: MPEG-4 Part 2 / H.263 / Sorenson Spark (cb3826aa4), VC-1 + VC-1 profile/level (cb3826aa4), MPEG-1 via MPEG-2 flags (7828d5a1f), AVS/AVS+ (d5f4c3d35), **AVS2** (3a7feba0e, 62c28d143 = scratch `avs2-v5` d0aa5a388) | Their hw-gap-analysis.md row D15 says "MPEG-1/MPEG-4 pt2/H.263/VC-1/AVS2: no V4L2 stateless uAPI for these codecs ... XL". These uAPIs now exist; all apply on their full image tree (§3.2). RK3588 VDPU121 (Hantro G1 class) does MPEG-4/H.263; rkvdec does AVS2; MPP has AVS+ HALs. | A second driver per uAPI is what linux-media needs before any of these can go upstream. |
| AVS2 harness: `harness/avs2dec`, 17 reference streams + md5s, `harness/research/avs2/` (syntax.md, test-streams.md) | Already in their AVS2 brief | **Their brief points at `avs2-v4` (af199b447); current is `avs2-v5` (d0aa5a388)**, which changes the default AVS2 sequence control from 0x0 to 176x144 (v4 fails its own validation in v4l2-compliance TRY_EXT_CTRLS). v4->v5 is only that hunk in `v4l2-ctrls-core.c`; struct layout is unchanged. The ALF "byte 168" fix in 62c28d143 is cedrus backend only. Tell them (via the user) to use v5 / Armbian 62c28d143. |
| Legacy-decode tooling (`harness/research/legacy-dec/`: xviddec, vm_dec arbitration, field-MV dumps, bitsweep) and the FFmpeg software-decoder bug drafts (MPEG-4 field-direct MV scaling, frame-threading `p_field_mv_table`, GMC1 AMV rshift) | Any MPEG-4 backend they write is compared against FFmpeg's software decoder, which these drafts show is wrong on interlaced/GMC streams | Not upstream yet (held, docs/upstream-queue.md). |
| DI300 deinterlace control convention (standard `V4L2_CID_DEINTERLACING_MODE` with a driver menu) | IEP2 uses private controls instead (§3.3) | Align before either RFC. |
| AFBC V4L2 formats `V4L2_PIX_FMT_YUV420_{8,10}_AFBC_16X16_SPLIT` ('AS12'/'AS01', Jernej, Armbian 7d830e0fd) + FFmpeg hwcontext AFBC mapping (Jernej's fork) + cedrus AFBC/AFBC10 output | Their MPP-parity agent (TODO 8) lists "AFBC output" for rkvdec | If rkvdec AFBC output is added, reuse these fourccs (they apply on their tree, 1-line offset), not new ones. |
| OpenSSL 4 U-Boot host tools: framework fix `uboot_host_openssl_engine_workaround` (4a8b8ef19): `HOSTCFLAGS=-DOPENSSL_ENGINE_STUBS` after a link probe, their `--disable TOOLS_KWBIMAGE --disable TOOLS_LIBCRYPTO` as fallback | Their `build-uboot.sh` drops TOOLS_LIBCRYPTO (no FIT signing in mkimage) | Optional for them: the stubs keep FIT signing. |
| Armbian Ubuntu 26.10 "stonking" support (pr/group/ubuntu-stonking) + framework fixes (base-files json fallback, uutils `ln` host-side, dbus-broker guard) | Prerequisite if they ever contribute rockchip64 work to Armbian (opi5-armbian-contrib memory) | Ours to send (PR #1 in docs/prs/README.md). |
| U-Boot `usb-hub-yield-during-port-debounce.patch` (common/usb_hub.c, ecc40100d) | Faster USB scan if they boot from USB | Optional. |
| Mesa `15bd751e896 poly: make the work-group scan independent of the subgroup size` (panfrost-gs-tess) | libpoly is shared by asahi and the panvk/csf GS work (!44118, v10+, i.e. their Mali-G610). The old code assumed 32-wide subgroups and 32 subgroups per workgroup; Valhall subgroups are 16 wide | Likely matters once !44118 lands; untested on v10. Mesa AI policy applies: `Generated-by: LLM`, never upstream without the user. |

Nothing else of ours applies to RK3588: cedrus, DE33/AFBC scanout, TVE, DI300 itself, sun50i-iommu,
dwmac-sun8i, uwe5622, sunxi DRAM/CE-RNG/RSB U-Boot work, and the H616 TF-A PSCI suspend are SoC-specific.
`drv-net-stmmac-norm-desc-...` touches stmmac core `norm_desc.c`, but RK3588's GMAC uses dwmac4
descriptors, so no effect for them.

---

## 3. Common code both sides changed

Verdict key: **identical** / **compatible** (no semantic conflict, maybe textual) / **divergent** (both
valid but would contradict each other upstream) / **conflict**.

### 3.1 Kernel PM core: identical

| File | Ours | Theirs | Verdict |
|---|---|---|---|
| kernel/power/suspend.c | `patches.armbian/pm-suspend-do-not-call-suspend-ops-begin-end-for-s2idle.patch`, commit 84639c3f4 (branch fix/sunxi-pm-s2idle-dpm-backports 3d287e071) | `patches/linux/2201-PM-suspend-Do-not-call-suspend_ops-begin-end-for-s2i.patch` (orangepi5-mainline 8256266) | identical diff, same upstream SHA 4785d5faa935 (7.4) |
| drivers/base/power/main.c | `patches.armbian/pm-sleep-add-dpm-watchdog-to-all-phases.patch`, 84639c3f4 | `2202-PM-sleep-Add-DPM-watchdog-...` (8256266) | identical diff, upstream 33392343c74e |

Both are backports, nobody sends them. Drop both when 7.3.y stable carries them. If both projects end up in
Armbian, propose them once as a family-neutral backport rather than twice (sunxi-7.3 and rockchip64-7.3).

### 3.2 V4L2 uAPI / v4l2-core: compatible (no ID collisions, textual conflicts only)

Files both sides change: `include/uapi/linux/v4l2-controls.h`, `include/uapi/linux/videodev2.h`,
`include/media/v4l2-ctrls.h`, `drivers/media/v4l2-core/v4l2-ctrls-{core,defs}.c`,
`Documentation/userspace-api/media/v4l/{ext-ctrls-codec-stateless,pixfmt-compressed,vidioc-g-ext-ctrls,
vidioc-queryctrl}.rst`, `videodev2.h.rst.exceptions`.

- Ours: VC-1 + profile/level, MPEG-4/H.263/Spark (cb3826aa4); AVS2 (3a7feba0e, 62c28d143); MPEG-1 flags
  (7828d5a1f); AVS (d5f4c3d35); AFBC fourccs (Armbian 7d830e0fd).
- Theirs: `0802` H.264 stateless encode uAPI (Paul Kocialkowski), `0812` HEVC stateless encode uAPI (ours,
  Arun), `0911` Rockchip IEP controls, `1407` HEVC SPS default (Tharit), all in orangepi5-mainline fa2eabe /
  8256266.

Number allocation (checked against v7.3):

| Space | v7.3 upstream | Ours | Theirs |
|---|---|---|---|
| `V4L2_CID_CODEC_STATELESS_BASE +` | H.264 0-7, FWHT 100, VP8 200, VP9 300-301, HEVC 400-409, AV1 500-505 | VC-1 600-604, MPEG-4 700-704, H.263 800-801, AVS2 900-903, AVS 1000-1002 | H.264 enc 8, HEVC enc 410-411 |
| `V4L2_CTRL_TYPE_*` | 0x200-0x205, 0x220, 0x240, 0x250-252, 0x260-261, 0x270-276, 0x280-283 | 0x290-294, 0x2a0-2a3, 0x2b0-2b1, 0x2c0-2c3, 0x2d0-2d2 | 0x206, 0x277-0x278 |
| `V4L2_CID_CODEC_BASE +` | up to 657 | VC-1 profile/level 658-659 | none |
| `V4L2_CID_USER_BASE +` driver ranges | last is MALI_C55 0x1230 | DI300 0x1100-0x1105, **private, defined in the driver .c, no reserved range in v4l2-controls.h** | IEP 0x1260 (reserved in uapi header) |
| fourccs | | AVSF, AVS2, SVC1, MG4S, S263, SPKS, AS12/AS01 | none new |

No collisions. Apply results:
- Our 9 uAPI patches on their full image tree (v7.3 + 479): all apply, fuzz 1 on VC-1/MPEG-4/AVS2/AVS
  (offsets 16-19 lines). They can stack our AVS2 uAPI on k15 without edits.
- Their 0801-0817 + 0911 on our tree: all apply except `0812` and `1407`, which hit context-only rejects
  in `std_init_compound()` declarations (both sides add `struct ... *p_...;` lines and `case` blocks in
  the same place). Hand-merge, no semantic conflict.
- Their `0107/0108/2001/2010` v4l2-mem2mem (multi-job, detach; 0107/0108 from the posted rkvdec multi-core
  series): apply on ours. `v4l2_m2m_get_curr_priv()` keeps its single-job meaning, so cedrus, sun8i-di,
  sun8i-rotate and DI300 are unaffected. Running our cedrus/DI300 regression with them applied is a cheap
  Tested-by for that series.

Upstream rule for both: whichever stateless uAPI lands first, the other rebases. Keep the numbers above.
When DI300 goes upstream it needs a reserved `V4L2_CID_USER_SUNXI_DI300_BASE`. Take the next free slot in
linux-next at send time, coordinated with IEP's 0x1260. 0x1100 must not be sent as-is.
Done 2026-11-05 (`fix/sunxi-h616-di300-std-controls`): IEP2 dropped its private controls and its 0x1260 range, and
DI300 now has `V4L2_CID_USER_SUNXI_DI300_BASE` = `V4L2_CID_USER_BASE + 0x1260` (16 controls, uAPI header
`linux/sunxi-di300.h`; 0x1240/0x1250 are DCMIPP/IT6625 in newer kernels). Recheck linux-next before sending.

### 3.3 Deinterlacer controls: divergent

| | Ours: DI300, 0fec35361 (`patches.media/h616-di/media-sunxi-sun50i-di300-add-weave-bob-frame-rate-an.patch`) | Theirs: IEP2, `0911-media-uapi-add-Rockchip-IEP-deinterlacer-controls.patch` (fa2eabe) |
|---|---|---|
| Mode | standard `V4L2_CID_DEINTERLACING_MODE`, driver menu (Weave, Bob, "Motion Adaptive, Field Rate", "Motion Adaptive, Frame Rate", ...) | private `V4L2_CID_ROCKCHIP_IEP_DEINT_MODE` menu (BOB, MOTION_ADAPTIVE) in a new uapi header `rockchip-iep.h` |
| Field vs frame rate | folded into the mode menu items | separate boolean `V4L2_CID_ROCKCHIP_IEP_FIELD_RATE` |
| Second-field timestamp | half a frame interval after the first | half a frame period after the first (same) |

Two RFCs from the same submitter to linux-media with opposite conventions for the same concept invite a
"pick one" review on both. Recommendation: one convention. Use the standard `V4L2_CID_DEINTERLACING_MODE`
for the algorithm (it exists and is what maintainers will point to), plus one shared field-rate control:
either both keep a private boolean with identical semantics, or a jointly proposed standard
`V4L2_CID_DEINTERLACING_FIELD_RATE`. That means splitting our menu into mode + rate, or them moving to
the standard mode control. Joint decision. Ours is the bigger change, so propose it to them.

### 3.4 DRM core: compatible, needs their test

`drivers/gpu/drm/drm_gem_framebuffer_helper.c`: ours `patches.drm/de33-afbc/0244-drm-gem-Validate-AFBC-
framebuffer-size-with-its-spar.patch` (Jernej Skrabec, unposted; our commit 1f852632b). For AFBC modifiers
it replaces the linear min-size check with the AFBC sparse-layout size **in the shared helper**, so it also
runs for rockchip VOP2 framebuffers (panthor AFBC scanout, 16x16|SPARSE|YTR per their FIXLIST). It applies
cleanly on their tree. They touch no file in this helper (their DRM core changes are the Collabora HDMI 2.1
series, `drm_connector`/`drm_bridge`/`drm_hdmi_*`, plus `0265` and `1219`; our sun8i dw-hdmi and TVE use
none of the renamed APIs). Before Jernej posts 0244, an RK3588 run (GNOME/Weston on panthor, AFBC modes,
NV12 AFBC if rkvdec AFBC appears) is the best evidence it does not reject valid buffers. Owner: them
(test), us (report to Jernej).

### 3.5 FFmpeg v4l2-request: divergent bases

| | Ours | Theirs |
|---|---|---|
| Base | Jernej's fork `github.com/jernejsk/FFmpeg` branch `v4l2request-mpeg4` a56a208b (has MPEG-4 + AFBC hwcontext); LibreELEC 9.0.2 patch set noted as an alternative | Ubuntu `ffmpeg 7:8.1.2-2ubuntu2` + Kwiboo's series = code.ffmpeg.org PR 20847 (`patches/ffmpeg/0001-0011`) |
| Our drafts | MPEG-1 hwaccel (`legacy-dec/ffmpeg-mpeg1-v4l2request.patch`, modifies `v4l2_request_mpeg2.c`), MPEG-4 interlaced-B fallback (`v4l2_request_mpeg4.c`, fork-only), software fixes in `mpeg4video*.c` | `0012` HEVC SPS ST/LT RPS (probes controls, harmless on cedrus), `0013` build fix, debian enable patch |

Not a conflict (different files except `v4l2_request_mpeg2.c`), but two FFmpeg stacks for the same user
would double the work. Recommendation: one common base for both desktop images, their Ubuntu 8.1.2 + PR
20847 (what upstream FFmpeg is reviewing). On top: Jernej's AFBC hwcontext patch and his MPEG-4/VC-1
hwaccels, rebased onto PR 20847, then our MPEG-1/AVS/AVS2 hwaccels and their 0012. Our
`mpeg4-ilace-b-fallback` draft targets `v4l2_request_mpeg4.c`, which exists only in Jernej's fork. Keep it
addressed to Jernej, as docs/upstream-queue.md #3 already says. The software-decoder fixes (#1, #2, #4)
go to upstream FFmpeg and do not depend on either base.

### 3.6 GStreamer: theirs only

We carry no GStreamer patches, so there is nothing to conflict. Our fluster results depend on their
v4l2codecs 0001/0002/0009/0010 once we take them (§1.3).

### 3.7 U-Boot common: compatible, no shared files

- OpenSSL 4 host tools: ours framework-wide in `lib/functions/compilation/uboot.sh` (4a8b8ef19; the old
  per-tree stubs patch was dropped in 85f2d821a) vs theirs `scripts/config --disable TOOLS_KWBIMAGE
  --disable TOOLS_LIBCRYPTO` in `~/orangepi5/scripts/build-uboot.sh`. Ours contains theirs as the
  fallback. Neither sends an OpenSSL fix to U-Boot (Heinrich's `-DOPENSSL_ENGINE_STUBS` patch drew
  objections, per our uboot.sh comment). Compatible.
- Ours in U-Boot common code: `common/usb_hub.c` (usb-hub-yield-during-port-debounce, ecc40100d),
  `common/spl/*` (spl-fit-buffer-and-settle-delay, Armbian). Theirs: `drivers/ata/{ahci,dwc_ahci}.c`,
  `drivers/pci/pcie_dw_rockchip.c`, naneng-combphy. No file in common. Same tag v2026.10 on both sides.

### 3.8 TF-A: no overlap

Ours `plat/allwinner/**` on lts-v2.14.11 (2 patches); theirs `plat/rockchip/rk3588/drivers/pmu/pmu.c` on
v2.15.0. Different trees and versions, no shared file. Both go to TF-A Gerrit separately.

### 3.9 Mesa panfrost: no overlap today

Their Mesa is stock. Ours: one commit in `src/poly/geometry.h` (15bd751e896, panfrost-gs-tess); `main` is
pristine; `panfrost-opencl-fixes` (mesa-cl) is stock 26.2.4 with no commits of ours yet. The only future
overlap point is libpoly, shared with panvk/csf (!44118) on their G610 (§2). Any later gallium panfrost
change of ours (GS/TS lowering on v7 JM) is shared code with panthor/v10 in `src/gallium/drivers/panfrost`
and `src/panfrost`. Our image ships it only behind the "no regressions" rule
(feedback-mesa-fork). A v10 run on their board would be the regression check for code that is not
`PAN_ARCH`-guarded.

### 3.10 AI attribution in patches that go upstream: inconsistent on both sides

- Their kernel patches (194 files) and our kernel patches (e.g. AVS/AVS2 uAPI) carry
  `Assisted-by: Claude:claude-opus-5-5`.
- v7.3's `Documentation/process/coding-assistants.rst` specifies `Assisted-by: LLM [TOOL1] [TOOL2]`. It
  also forbids AI-added Signed-off-by: the human adds his own.
- Our Armbian PR rule (docs/prs/README.md) is `Assisted-by: Claude`; Mesa is `Generated-by: LLM`.

Before anything goes to a kernel list, both projects should rewrite the trailer to whatever the target
tree's `coding-assistants.rst` says at send time, the same way on both sides. Joint patches (AVS2, any
shared generic fix) must not carry two styles. User decision; flagged because both sides currently violate
the 7.3 text.

---

## 4. Recommended actions

### 4.1 Share / port

| # | Action | Owner | Notes |
|---|---|---|---|
| A1 | Tell the opi5 AVS2 agent to build on **avs2-v5** (d0aa5a388 = Armbian 62c28d143), not v4 af199b447 | user -> them | Avoids starting rkvdec on a uAPI that fails v4l2-compliance |
| A2 | Port to sunxi-7.3 as backports: 1407 (rebased), 0514, 1102, 1103, 2206, 1913; optional 1905, 2227, 1920 | us | 0514/1102/1103 together with the SYSTEM_SUSPEND board test; 1407 with a cedrus v4l2-compliance run |
| A3 | Re-plan the cedrus H.264 encoder on Paul Kocialkowski's 2026 stateless uAPI + `v4l2-h264-enc*` helpers (their 0801-0809), drop the stateful Phase B | us | Update ve-encoder/PLAN.md §1.4/§4.2 first; user to confirm |
| A4 | Cedrus VP9 inter-frame resize: port the 0606/2228 idea + take gst 0010; rerun fluster VP9 | us | Target the 64 failing profile 0 vectors |
| A5 | Desktop variant media stack: copy the build-media-debs.sh method, take their FFmpeg 0001-0013 + debian, gst-plugins-bad 0001-0010, gst-plugins-good 0006/0008/0010, mpv 0001-0003, libva-v4l2_request `opi5/main` | us (reuse) | Each package gets a cedrus run before it ships; versions `+opiz2.N` |
| A6 | Offer our legacy uAPIs (MPEG-4/H.263/Spark, VC-1, MPEG-1, AVS/AVS+) + legacy-dec tooling for RK3588 VDPU121/rkvdec backends (their D15) | them (decide) | A second driver is what makes these uAPIs upstreamable |
| A7 | Run 0244 (drm-gem AFBC size) on RK3588 with panthor AFBC scanout | them | Result goes to Jernej with ours |
| A8 | Run cedrus + DI300 regressions with their mem2mem 0107/0108/2001/2010 applied | us | Tested-by for the rkvdec multi-core series |
| A9 | Optional for them: switch build-uboot.sh to `HOSTCFLAGS=-DOPENSSL_ENGINE_STUBS` (keeps FIT signing) | them | |

### 4.2 Merge into one common version

| Item | Common version | Owner |
|---|---|---|
| AVS2 uAPI | One series (v6) after the rkvdec backend exists; any field rkvdec needs (10-bit, ALF, WQ layout) folds into the uAPI, not a second header. Cedrus + rkvdec as two users in the same RFC | joint (uAPI ours, rkvdec theirs) |
| Deinterlacer controls | Standard `V4L2_CID_DEINTERLACING_MODE` + one field-rate control with identical semantics; DI300 gets a reserved CID range next to IEP's | joint |
| FFmpeg v4l2-request | Their base (Ubuntu 8.1.2 + PR 20847) + Jernej AFBC/MPEG-4/VC-1 rebased + our MPEG-1/AVS/AVS2 + their 0012, one patch dir | joint (base theirs, codec add-ons ours) |
| GStreamer/mpv/libva patches | Theirs, used unchanged by both | them |
| PM backports | Already identical; one Armbian backport PR if both families need it | us (Armbian PR #5 exists) |
| AI trailer | One form per target tree, applied identically | user decision |

### 4.3 Upstream submission order (only after the user says go; nothing here is sent by an agent)

1. **Generic fixes they already prepared** (`upstream-send/`: rtc-minute-alarm, cpufreq-unlisted-freq,
   devfreq-resume-freq, ohci-platform-resume, fw-devlink-sync-state, and the spi/clk-divider/uvc patches):
   they send; we reply with H616 `Tested-by` after A2. A second SoC strengthens each one.
2. **1407** (already on lore by its author): we reply `Tested-by` for cedrus.
3. **Paul's H.264 stateless encode v2**: theirs (rkvenc/hantro) are the follow-ups. Our cedrus encoder
   comes later, on the same uAPI.
4. **Their HEVC stateless encode uAPI RFC** (0811-0817): theirs. It does not touch our ranges.
5. **Legacy stateless decode uAPIs**: AVS2 first as a joint RFC with two drivers (cedrus + rkvdec). Then
   MPEG-4/H.263 if they produce a Hantro backend, otherwise ours alone as RFC (cedrus is staging, so expect
   "second user?" questions). VC-1, AVS and MPEG-1 last. All rebase over whichever encode uAPI lands
   first (context conflicts only).
6. **Deinterlacers**: after §3.3 is agreed, DI300 (ours) and IEP2 (theirs) as separate driver RFCs that
   cite each other.
7. **Jernej's DE33/AFBC series incl. 0244 and the AFBC V4L2 fourccs**: Jernej's to send (docs/prs/README.md:
   no advance ask, his authorship kept). We give him the H616 results and their RK3588 0244 result (A7).
8. **FFmpeg**: our software-decoder fixes to ffmpeg-devel (upstream-queue #1/#2/#4, base-independent).
   v4l2-request hwaccel additions go after PR 20847 merges, rebased on it (MPEG-1 on the upstream mpeg2
   hwaccel; MPEG-4 fallback to Jernej).
9. **U-Boot / TF-A**: independent, any order (no shared files).
10. **Mesa**: nothing from either side without the user's explicit ask (poly fix included).

### 4.4 Owner summary

- **Us**: A2, A3, A4, A5, A8; Armbian PRs as planned (stonking first); DI300 CID range; tell Jernej about A7.
- **Them**: A1 (via the user), A6 (decide), A7, A9; send their prepared generic fixes; GStreamer/mpv/libva upkeep.
- **Joint**: AVS2 uAPI v6, deinterlacer control convention, one FFmpeg patch set, AI trailer form.

---

## 5. Report footer

- What changed: this file only. No code, branch or board change on either side; no upstream contact.
- Branches + commits referenced: ours `stonking-orangepizero2` 8546e5fc1 (base 27a7f7276), overlap commits
  84639c3f4, cb3826aa4, 3a7feba0e, 62c28d143, 7828d5a1f, d5f4c3d35, 0fec35361, 1f852632b, 4a8b8ef19,
  ecc40100d, Armbian 7d830e0fd; scratch `avs2-v4` af199b447 / `avs2-v5` d0aa5a388; Mesa 15bd751e896.
  Theirs `orangepi5-mainline` be26e39 (patches added in fa2eabe, 5a387ec, 423237b, 8256266, 88fb1e5),
  kernel branch `k15-v4` bb1a61971 / `k15-avs2`, libva-v4l2_request 069af09.
- Board results: none (host-side only, as briefed).
- Open: user decisions on A3 (encoder direction), §3.3 (deinterlacer convention), §3.10 (trailer form),
  §3.5 (common FFmpeg base); relaying A1 to the opi5 session; the apply checks are textual. No cross-built
  kernel with both uAPI sets stacked yet (one `STAGE=patch` + `make drivers/media/v4l2-core/` run would
  settle it).
