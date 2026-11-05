# FFmpeg patch series (Ubuntu ffmpeg 7:8.1.2-2ubuntu2 = FFmpeg n8.1.2)

Applied in file-name order by scripts/build-media-debs.sh (appended to debian/patches/series). One ordered series,
shared with the orangepi5 project (user decision 2026-11-05: Kwiboo's series is the base).

| range | source |
|---|---|
| 0001-0011 | Jonas Karlman (Kwiboo), V4L2 Request API hwaccels, FFmpeg PR 20847 (github.com/Kwiboo/FFmpeg v4l2-request-n8.1). Identical to orangepi5 patches/ffmpeg/0001-0011 |
| 0012-0013 | orangepi5 project: HEVC SPS RPS controls (ours, for rkvdec), ffbuild race fix (upstream backport). Identical to orangepi5 0012-0013 |
| 0101-0102 | Kwiboo v4l2-request-n8.1 branch: AFBC_16X16_SPLIT and BROADCOM_SAND128 capture formats |
| 0201-0208 | Jernej Skrabec, github.com/jernejsk/FFmpeg v4l2request-mpeg4 (a56a208): VC-1 fixes + VC-1/WMV3 hwaccel, MPEG-4 Part 2/H.263/Sorenson Spark hwaccel (non-upstream cedrus uAPIs, local headers) |
| 0301- | ours (Orange Pi Zero2): MPEG-4 field-direct fix, interlaced-B software fallback, GMC1 rshift, MPEG-1 hwaccel, AVS/AVS+ and AVS2 hwaccels |
| debian/ | packaging: --enable-v4l2-request --enable-libudev (from orangepi5) |

Git source of the series: kernel-check/ffmpeg-deb/src (not committed), branch `opiz2/series` on tag n8.1.2.
Re-export after changing the branch: `git format-patch --zero-commit --no-signature` per range with
`--start-number 1 / 101 / 201 / 301`.
