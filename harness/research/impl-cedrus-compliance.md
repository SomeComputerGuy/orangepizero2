# cedrus v4l2-compliance, AVS2 timeouts, GStreamer JPEG rank, jumbo MTU (kernel-fixes, round 2)

Board tests on cumulative kernel c3 (0122ff6a7, `7.3.1 #3 Thu Nov 5 12:35`), 2026-11-05.
Raw output: `cedrus-compliance/c3-session.txt`, `cedrus-compliance/c3-board/`.

## 1. cedrus v4l2-compliance

Stock v4l2-compliance 1.32.0 on c3, /dev/video0: **49 tests, 43 ok, 6 FAIL**.

| fail | cause | fix |
|---|---|---|
| controls.cpp(939) try_ext_ctrls EINVAL | default VC-1 Sequence Layer (profile simple, no RES_RTM: cedrus_try_ctrl refuses) and AVS Sequence Header (size 0x0: validate_avs_sequence refuses). ctrltry: only these two of all controls fail G/TRY/S (MPEG-4 VOL, AVS2, H.263 ok; HEVC SPS fixed by 1407 already in c-kernels) | kernel: VC-1 default = simple + RES_RTM; AVS default = 176x144 |
| formats.cpp(317) duplicate AS01 | cedrus_enum_fmt() did not apply the depth/src_format filters cedrus_find_format() has, so AS01/AS12 come out once per HEVC/VP9/AVS2 entry (`v4l2-ctl --list-formats`: AS01 three times) | kernel: same filters in enum_fmt |
| formats.cpp(516) MG2S not reported x3 | follow-on of the duplicate (enumeration aborted) | same |
| codecs.cpp(161) DECODER_CMD | userspace: compliance does not know SVC1/MG4S/S263/SPKS/AVSF/AVS2 fourccs, and takes the AFBC capture formats (COMPRESSED flag) for codec formats, so no codec mask is set and stateful rules are used | v4l-utils patches 0001-0003 |

Kernel branch **fix/sunxi-cedrus-v4l2-compliance** (armbian-build worktree wt-cedrus-compliance,
commit 8a3eb99bc, off test-cumulative b8258b7f2, pushed to fork). STAGE=patch: 830 applied, 0 failed.
Not compiled or board-tested yet: it needs the next cumulative kernel.

v4l-utils (project repo patches/v4l-utils, on v4l-utils-1.32.0):
- 0001 detect the cedrus VC-1/MPEG-4/H.263/Spark/AVS stateless decoders
- 0002 detect AVS2 stateless decoders (own patch, for the joint AVS2 series)
- 0003 AFBC (AS12/AS01) is not a codec format; a stateless decoder that also takes JPEG stays stateless

Patched compliance (0001-0003, built on the board with g++) on c3: "Detected Stateless Decoder",
**49 / 44 ok / 5 FAIL**. DECODER_CMD passes; the 5 left are the three kernel items above.
Without 0003 the detection still failed (AFBC). /dev/video1 sun50i-di300: 49/49 ok.

Expected on a kernel with the branch: patched compliance 0 FAIL, stock compliance 1 FAIL (DECODER_CMD).

### Verified on c8 (084fcccca, contains 8a3eb99bc), 2026-11-05

Raw: `cedrus-compliance/c8-session.txt`, `cedrus-compliance/c-board/c8/` (script `session-compliance.sh`).
c6/c7 requested; install-kernel.sh maps to the newest tag, which was c8 by then.

| node | stock 1.32.0 | patched (0001-0003) |
|---|---|---|
| /dev/video0 cedrus | 49 / 48 ok / 1 FAIL (codecs.cpp(161) DECODER_CMD, userspace only) | **49 / 49 ok / 0 FAIL**, Detected Stateless Decoder |
| /dev/video1 sun50i-di300 | 49 / 49 / 0 | 49 / 49 / 0 |

ctrltry: 0 failing controls. Targets met. v4l2-compliance stays a test tool (not shipped in the image).

## 2. The 360 "frame processing timed out" lines

They come from the AVS2 FFmpeg agent's test1_avs2 runs (kernel-check/avs2-board/ffmpeg-test1.log:
278 after the reference avs2dec run, 360 after the ffmpeg run; impl-desktop-ffmpeg-avs2.md: test1_avs2,
854x480 Main LCU32, the VE times out from picture ~174; corrupted-stream tests add 4).

Reproduced on c3: `avs2dec -f test1.avs2` under `timeout 90`: rc 124, 0 frames out, **44 new timeouts**,
"picture doi 0/1/2: decode error". Control BQSquare_416x240_60_ra: rc 0, 100 frames, 0 timeouts.
No IOMMU fault. So it is a real stream-specific AVS2 VE failure (not c2-specific, not a
regression of the c-kernels): belongs to the AVS2 work.

## 3. GStreamer JPEG rank (image)

`userpatches/config-opiz2-printserver.conf` `image_specific_armbian_env_ready__opiz2_gst_jpeg_rank`:
GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL in /etc/environment and systemd system/user
DefaultEnvironment. `harness/verify-board.sh` check gst-jpeg-autoplug (decodebin must pick jpegdec).
Check logic board-tested (default -> v4l2jpegdec0, with env -> jpegdec0). Will FAIL until the image is rebuilt.

## 4. Jumbo MTU (image)

`OPIZ2_ETH_MTU` (unset = no change, so 1500 default kept). 68..2018. NetworkManager image: conf.d
match-device=type:ethernet ethernet.mtu; networkd image: netplan 30-opiz2-eth-mtu.yaml. NM path
board-tested (end0 came up at 2018, reverted to 1500). Removing the setting does not lower the MTU of
a link that is up: `ip link set end0 mtu 1500` or reboot. Host side must match (host MTU is a user item).

## 5. /root/bp, /root/mm.txt

Copied to harness/research/opi5-bp/board/.

## Open

- Rebuild image to verify the gst rank and MTU hooks end to end.
- AVS2 test1_avs2 VE timeouts: handed to the AVS2 owner.
