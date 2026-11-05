# OPi5 backports into sunxi-7.3 (tasks 1) and JPEG greyscale result (task 3)

Date 2026-11-05. Agent: kernel-fixes. Brief: docs/status.md section 3 item 9, opi5-crosscheck.md §1.1 / A2.

## 1. What changed

Branch `fix/sunxi-opi5-backports` (worktree `wt-opi5-backports`), off `stonking-orangepizero2` b9df5096b, one commit
**d775e2c64** "sunxi-7.3: backport six generic fixes from the Orange Pi 5 project", pushed to `fork`. Already merged
into `test/cumulative` by the coordinator (cumulative kernel c1).

Patch files (new section at the end of `series.conf`, OPi5 numbers kept in the names; original From/author/date kept;
an `Origin:` note below `---` says where each came from):

| OPi5 # | File | Author | linux-next | Notes |
|---|---|---|---|---|
| 0514 | patches.backports/opi5-0514-PM-devfreq-resume-at-the-frequency-from-before-suspend.patch | Arun Iyengar | not in next-20261104 | unchanged |
| 1102 | patches.backports/opi5-1102-cpufreq-defer-the-unlisted-frequency-check-on-cpu-online.patch | Arun Iyengar | not in next | `Assisted-by: LLM` added (missing in the OPi5 copy) |
| 1103 | patches.backports/opi5-1103-usb-ohci-platform-power-the-root-hub-phys-up-before-resume.patch | Arun Iyengar | not in next | unchanged |
| 2206 | patches.backports/opi5-2206-spi-fix-runtime-pm-imbalance-on-error.patch | Sebastian Reichel (Collabora c7cfa432c13d) | not in next | unchanged, no AI tag (not ours) |
| 1913 | patches.backports/opi5-1913-clk-divider-dont-divide-by-zero-when-rounding-above-the-parent.patch | Arun Iyengar | not in next | unchanged |
| 1407 | patches.media/opi5-1407-media-v4l2-ctrls-default-HEVC-SPS-chroma-format-to-4-2-0.patch | Tharit Tangkijwanichakul | **in linux-next** (next-20261030 has the identical hunk) | rebased: context only (our VC-1/MPEG-4/H.263/AVS2/AVS lines in std_init_compound()); `[ Arun: ... ]` note; drop when the kernel moves past it |

linux-next check: subject grep over a fresh linux-next (next-20261104, commits since 2026-08-20) found none of
0514/1102/1103/2206/1913, and `git diff v7.3 next-20261030` of the six files shows no equivalent change in those
functions. The 1407 hunk is in next, but the commit id could not be resolved (shallow history; git.kernel.org and lore
return 403 to the fetch tool, a deeper fetch timed out). Same content, so the backport is the upstream change.

Build check: `kernel-check/build-kernel.sh` STAGE=all on the branch: **817 applied, 0 failed, build exit 0, 0 C
warnings** (log kernel-check/run-opi5bp-all.log). Trial kernel `bp1` (Image/modules in kernel-check/vdec-serve).
Note: bp1 was built in a private tree (work-opi5bp) before the cumulative-kernel rule (AGENT-RULES 454649e); further
tests belong on c1+.

## 2. Board results (2026-11-05)

Image kernel 7.3.1-edge-sunxi64 #17 = "before"; trial `bp1` (7.3.1, same series + the six patches) = "after", installed
with the vdec one-shot fallback armed and confirmed, then the image kernel restored. Board scripts:
harness/research/opi5-bp/bp-board.sh (state snapshot, rtcwake cycle loop). Raw results are on the board in /root/bp/
(img-pre, img-cyc, img-cyc2, img-post, tr-pre, tr-cyc, tr-post); copying them back failed when the board lock moved on.

| Check | Image #17 (before) | bp1 (after) |
|---|---|---|
| Suspend (`rtcwake -m mem -s 5`, deep, cpuidle on, 200 MB tmpfs sha256) | 5/5 + 20/20 rc=0, hash same | **60/60 rc=0**, mean 6.7 s per cycle, suspend_stats 60/0, tmpfs hash same |
| new err/warn per cycle | 2 (the musb "no ULPI bus control register" pair) | same 2, nothing else |
| cpufreq after resume (2 s after) | gov ondemand kept; 3/20 samples scaling 480000 vs cpuinfo 1512000 | gov kept; 12/60 samples showed a scaling/cpuinfo mismatch |
| GPU devfreq | simple_ondemand, 306 MHz, unchanged across cycles | simple_ondemand, 456 MHz (no GPU job since boot, runtime-suspended), governor and rate unchanged across 60 cycles |
| USB after resume | 3 EHCI + 3 OHCI root hubs present, runtime-suspended, no errors | same, no ohci/ehci errors (no USB device plugged in) |
| SPI NOR (mtd0, 2 MiB) sha256 | 557e5f3da8522563 before and after | 557e5f3da8522563 before and after 60 cycles |
| clk_summary diff (rates) | - | only gpu0/pll-gpu (306 vs 456 MHz, devfreq state) and iosc drift: 1913 changes no clock |
| v4l2-compliance cedrus /dev/video0 (1.32.0) | 49 tests, 43 OK, 6 FAIL; ext_ctrls fails on **HEVC Sequence Parameter Set** | 49/43/6; ext_ctrls now passes HEVC SPS and fails on the next control, **VC-1 Sequence Layer** (ours) |

The cpufreq mismatch is pre-existing and harmless: a detached probe (/root/mm.txt on the board, 15 cycles; numbers in §2 of this file)
showed vdd-cpu 1.1 V whenever cpuinfo read 1512 MHz and 0.9 V at 480/720 MHz. The two sysfs reads straddle an ondemand
transition. No under-volt.

What each patch does on the H616 (from code + the results above):
- **1407**: fixes the HEVC SPS part of the cedrus TRY_EXT_CTRLS failure (confirmed with `v4l2-compliance -v`). The test
  still fails, on our own VC-1 Sequence Layer default (open item below).
- **0514**: inert on H616. The path only runs when devfreq has a suspend OPP (`opp-suspend`), and our GPU OPP table has
  none. GPU devfreq governor/rate preserved across 60 cycles.
- **1102**: inert on H616. All four CPUs share one policy and CPU0 never goes offline, so `cpufreq_online()` is not
  called for an inactive policy on resume. The new check in `cpufreq_resume()` ran 60 times without a "failed to leave
  unlisted frequency" message.
- **1103**: exercised: the three ohci-platform controllers resume through the new PHY up/down pair 60 times with no
  errors. Not tested with a device attached (no USB device on the board; needs the user's printer/stick).
- **2206**: error path only. SPI NOR reads identical after 60 cycles; the imbalance case was not triggered.
- **1913**: no clock rate changed (clk_summary diff). Matters only for a ROUND_CLOSEST divider asked for a rate above its
  parent.

Other v4l2-compliance failures on cedrus (pre-existing, same before/after, not caused by these patches): duplicate format
AS01 in ENUM_FMT, MG2S accepted by G/TRY/S_FMT but not enumerated (3 tests), DECODER_CMD. dmesg had 360 "frame
processing timed out" lines before my run (from an earlier session's work, not investigated).

## 3. JPEG greyscale (task 3)

Folded into harness/research/impl-di-jpeg-avs.md §7.6. Summary: the 169-run greytrial probe (11-03) shows the H616 MPEG
JPEG engine stops after the first MCU for format code 5 regardless of every reachable register; codes 0-4 run the full
scan but decode it as 3-component garbage; the 0xE00 jpeg-plus block reads all zero. Greyscale JPEG is not decodable in
hardware; the refusal stays. New board check today: GStreamer autoplugs `v4l2jpegdec` (PRIMARY+1), which produces **0
bytes for colour JPEGs** and hangs on grey; with `GST_PLUGIN_FEATURE_RANK=v4l2jpegdec:MARGINAL` `jpegdec` decodes all four
test files. So option A (rank override) is decided. Still needed: ship the rank hook in the image and re-check on the
board after the rebuild.

## 4. Open

1. Our VC-1 Sequence Layer control: its zeroed default fails cedrus try_ctrl, so v4l2-compliance ext_ctrls still fails
   (next control after HEVC SPS). Needs a std_init_compound() default (or relaxed try check) in our VC-1 uAPI patch. The
   same check is worth doing for MPEG-4 VOL, AVS2 and AVS sequence defaults. New fix branch from test/cumulative.
2. cedrus v4l2-compliance: AS01 duplicate, MG2S not enumerated, DECODER_CMD (pre-existing).
3. 1103 with a real USB device across suspend (printer/scanner or stick, user hardware).
4. GPU devfreq across suspend under real GPU load (glmark2/kmscube need a connector; HDMI not attached).
5. Upstream (not by us): 1407 Tested-by for cedrus can be offered to Tharit's thread once someone decides to send it.
