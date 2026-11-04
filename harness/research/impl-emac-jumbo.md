# H616 EMAC0 jumbo frames (dwmac-sun8i): root cause, fix, board test plan

Branch: `fix/sunxi-h616-emac-jumbo` (off `stonking-orangepizero2` 16cdd50a9), fork SomeComputerGuy/build.
Patches (in series.conf after `drv-net-stmmac-dwmac-sun8i-add-h616-internal-phy.patch`):
1. `patches.armbian/drv-net-stmmac-norm-desc-drop-multi-descriptor-frame-tails.patch`: stmmac core, normal descriptors
2. `patches.armbian/drv-net-stmmac-dwmac-sun8i-enable-jumbo-frames.patch`: dwmac-sun8i JUMBO_FRM_EN + max_mtu 2021

## Symptom (board, 7.3.1-edge-sunxi64, before the fix)

- `ip -d link` shows maxmtu 3712; `ip link set end0 mtu 3712` is accepted.
- DF pings from the host (r8152, MTU 9000): up to `-s 1472` work; `-s 1600/2000/2500/3000/3684` get no replies.
- `ethtool -S end0` rx_length goes up and `ip -s link` RX errors/dropped go up at the same rate.

## Root cause

There are two separate limits. Either one is enough to break MTU > 1500.

1. **RX_CTL0 bit 29 JUMBO_FRM_EN is never set.** dwmac-sun8i only touches RX_CTL0 bits 31 (RX_EN),
   27 (CHECK_CRC) and 16 (flow control). With bit 29 clear, the MAC flags any frame over 1518/1522 bytes
   as a length error. ndesc_get_rx_status() counts that as rx_length and drops the frame.
   The Allwinner BSP (sunxi-gmac, orangepi-xunlong orange-pi-5.4/6.1-sun50iw9, `sunxi_mac_init()`) sets it
   at init: RX_CTL0 |= BIT(27) | BIT(28) STRIP_FCS | BIT(29) JUMBO_FRM_EN, and TX_CTL0 |= BIT(30)
   ("Jabber Disable", TX_FRM_LEN_CTL: 0 = 2048, 1 = 16384). The D1 register description (same EMAC IP)
   gives bit 30 RX_FRM_LEN_CTL as 0 = 2048, 1 = 16384, and bit 29 as JUMBO_FRM_EN.
   The local H616 datasheet only says "up to 16 KB"; the user manual EMAC chapter is not in docs/vendor/.
2. **max_mtu 3712 is not a hardware value.** sun8i has no HW feature register, so enh_desc = 0, and
   stmmac sets max_mtu = SKB_MAX_HEAD(NET_SKB_PAD + NET_IP_ALIGN) = 3712 (4K pages). The EMAC descriptor
   buffer-size field is 11 bits (BSP `buf1_size:11`, QEMU `DESC_STATUS2_BUF_SIZE_MASK 0x7ff`). In the
   stmmac core (normal descriptors, chain mode, forced for sun8i):
   - `ndesc_init_rx_desc()` caps each RX buffer at min(dma_buf_sz, 2047). For MTU 3712, dma_buf_sz is 4096,
     but the descriptor still says 2047.
   - `ndesc_get_rx_status()` returns discard_frame (and rx_length++) for any descriptor without the
     LAST bit. It never returns rx_not_ls, so a frame that needs two descriptors is always dropped.
     (The tail descriptor is then picked up as if it were a new frame; that is pre-existing behaviour.)
   - TX: `stmmac_xmit()` only splits jumbo frames when enh_desc is set, and
     `norm_set_tx_desc_len_on_chain()` masks the length with the 11-bit TDES1 mask. So a linear
     frame over 2047 bytes would be silently truncated on TX.
   The BSP also uses 2047-byte buffers (MAX_BUF_SZ = SZ_2K - 1) and also drops non-last descriptors,
   so the vendor driver never really supported frames over about 2 KB either.

The EMAC DMA itself can chain a frame across descriptors (FIRST/LAST bits, as modelled in QEMU). But
supporting that needs multi-descriptor RX in ndesc plus TX splitting for !enh_desc in the shared stmmac
core. That is a larger net-next change that also affects other normal-descriptor GMACs, so it is not
done here.

## Fix

### Patch 1: norm_desc, drop every descriptor of an oversized frame
`ndesc_get_rx_status()` discarded only the descriptors without LAST. The final descriptor (LAST set, FIRST
clear) then reached stmmac_rx() as a "good" frame: a bogus skb holding the frame's tail, with its length
taken from the whole frame. Before this fix, the MAC also flagged such frames with a length error, which
hid the problem. Once JUMBO_FRM_EN is on, that flag goes away, so this has to be fixed first. The patch now
discards descriptors missing FIRST or LAST. With normal descriptors a valid frame always has both set,
because multi-descriptor RX is unsupported.

### Patch 2: dwmac-sun8i

- `sun8i_dwmac_core_init()`: set RX_CTL0 JUMBO_FRM_EN, always. core_init runs after every DMA soft
  reset, including the reopen done by an MTU change. It has to be unconditional because stmmac_change_mtu()
  writes dev->mtu only after __stmmac_open(), so core_init still sees the old MTU.
- Probe: `plat_dat->maxmtu = min(plat_dat->maxmtu, EMAC_MAX_MTU)`, where
  EMAC_MAX_MTU = 2044 - ETH_HLEN - 2*VLAN_HLEN - ETH_FCS_LEN = **2018** (2021 in Image.jumbo1, see board results). A DT max-frame-size can still
  lower it.
- TX_CTL0 is left alone: the largest frame is 2021 + 14 + 8 + 4 = 2047 bytes on the wire, which is under
  the 2048 jabber cutoff.
- At MTU 1500 (dma_buf_sz 1536), the only change is that the MAC no longer flags oversize frames.

Expected after the fix: `ip -d link` shows maxmtu 2018 (jumbo1: 2021), and MTU 1501..2021 works.
`ip link set end0 mtu 3000` (or 3712) is now refused with "mtu greater than device maximum".

## Test kernel

In `kernel-check/jumbo-serve/`. Built from both patches on the full sunxi-7.3 series (777 patches), with
LOCALVERSION=-edge-sunxi64 and linux-sunxi64-edge.config:
| File | Size | sha256 |
|---|---|---|
| Image.jumbo1 | 37538304 B | 5ec7cc29195fdc50 |
| modules-jumbo1.tgz | 33277759 B | 71d84e5e13db7bdc |
| Image.jumbo2 | 37538304 B | 7ca8ee3db5b3c634 |
| modules-jumbo2.tgz | 33279839 B | 1591b21481128d26 |

- `Image.jumbo1`: arm64 Image, release 7.3.1-edge-sunxi64
- `modules-jumbo1.tgz`: top dir `7.3.1-edge-sunxi64/`, INSTALL_MOD_STRIP=1
- DTB: unchanged (the patch has no DT part), so keep the image DTB.

Install it like the vdec trial kernels: copy Image to /boot/vmlinuz-7.3.1-jumbo1, back up
/lib/modules/7.3.1-edge-sunxi64 to .good, extract the tgz into /lib/modules/, run
`depmod 7.3.1-edge-sunxi64`, arm the one-shot fallback, then point /boot/Image at the new kernel and reboot.
Note that harness/research/vdec-perf/install-kernel.sh hardcodes `7.3.1`. Adjust it to `7.3.1-edge-sunxi64`
(including the vdec-fallback restore path) before using it on this image.

## Board test plan

Notes:
- **Every MTU change on end0 bounces the link** (stmmac does __stmmac_release/__stmmac_open, so the PHY
  renegotiates for about 3 s). Run MTU changes from the serial console, or from ssh with a delayed
  revert, e.g. `ip link set end0 mtu X; sleep 5; ...`. Wait for `carrier 1` before testing.
- Host side: enx68da73af6279 (10.56.0.1) is already MTU 9000. Do not touch enp130s0, enp129s0 or wlo1.
- Board address: below, B = board IP on the 10.56.0.0/24 link.
- Record before/after counters each round: `ethtool -S end0 | grep -E 'rx_length|rx_crc|overflow|rx_desc|tx_'`
  and `ip -s link show end0`.

0. Sanity: `uname -r` = 7.3.1-edge-sunxi64 with the new Image (`uname -v` build date);
   `ip -d link show end0` shows **maxmtu 2021**;
   `devmem2 0x05020024` (EMAC0 RX_CTL0, if devmem2 is available) has bit 29 set while the interface is up.
1. **MTU 1500 (regression check)**
   - host -> board: `ping -M do -s 1472 -c 20 B` passes. For `-s 1473..1490` from the host (MTU 9000), the frame
     now fits the 1536-byte RX buffer and JUMBO_FRM_EN no longer flags it, so the board may accept it and
     answer with a fragmented reply. Either result is fine; just record it. `-s 1600` at MTU 1500 must be
     dropped (rx_length +1 because it spans two descriptors) without side effects.
   - board -> host: `ping -M do -s 1472 -c 20 10.56.0.1` passes.
   - `iperf3 -c B -t 20` and `-R`: about 940 Mbit/s each way, as before. No new RX errors.
2. **MTU 2000** (`ip link set end0 mtu 2000`)
   - host -> board: `ping -M do -s 1972 -c 20 B` gets 20/20 replies (this needs the reply TX at 2014 bytes too).
   - board -> host: `ping -M do -s 1972 -c 20 10.56.0.1` gets 20/20.
   - Sizes in between: `-s 1600`, `-s 1800`.
   - `iperf3 -c B -t 20` / `-R` with the host also at its MTU 9000 (TCP MSS negotiates down to 1960).
     Expect line rate and no rx_length/rx_crc growth.
   - UDP: `iperf3 -u -b 900M -l 1972 -c B` and `-R`; check loss is under about 0.1 %.
3. **MTU 2021 (new max)**
   - `ping -M do -s 1993 -c 20` in both directions gets 20/20.
   - With a VLAN: `ip link add link end0 name end0.10 type vlan id 10`, and the same on the host, with MTU 2021
     on both. `ping -M do -s 1993` over the VLAN in both directions (2047-byte frame with the tag).
   - `iperf3` TCP both directions.
4. **MTU 3000 / 3712**
   - `ip link set end0 mtu 3000` and `mtu 3712` must now fail with "Error: mtu greater than device maximum."
     The link must not bounce on a refused change. Confirm with `ip -s link` / dmesg.
   - Optional: send oversize frames at MTU 2021 with the host still at 9000:
     `ping -M do -s 3000 B` from the host. Expect no reply, rx_length/rx_errors +1 per packet,
     no stall, and normal traffic right after (`ping -c 5`).
5. **Back to 1500**: `ip link set end0 mtu 1500`; repeat step 1. Also ssh, DNS, and the CUPS print path
   (the board's real job) still work.
6. **Persistence/resume**: `ip link set end0 down; ip link set end0 up` at MTU 2000, then repeat the
   step-2 pings. This checks that core_init re-applies JUMBO_FRM_EN after the soft reset.
   If suspend is in use (impl-pm.md), also do one suspend/resume cycle at MTU 2000.

Pass criteria: all pings in steps 1-3 and 5-6 at 100 %, iperf3 at line rate, MTU over 2021 refused, no new
rx_length/rx_crc/overflow errors except the deliberate oversize sends in step 4.

## Follow-up (not in this patch)

- MTU up to the TX FIFO limit (4096) would need stmmac core work: ndesc must return rx_not_ls for
  non-last RX descriptors (with buf1_len = min(dma_buf_sz, 2047), not dma_buf_sz), and normal-descriptor
  TX must split frames over 2047 bytes (chain_mode jumbo_frm with bmax 2047, not BUF_SIZE_2KiB, since 2048 & 0x7ff = 0).
- dwmac1000_core_init() has the same ordering issue (it reads dev->mtu before stmmac_change_mtu() updates it),
  so 2K/JE is only applied on the next down/up. Reportable upstream.

## Board results, 2026-11-03 (Image.jumbo1, maxmtu 2021)

Raw output is in harness/research/emac-jumbo/r-*.txt; the fallback unit and script are in the same dir.
Installed as a trial with the image DTB and a regenerated trial uInitrd. The jumbo-fallback unit was armed,
the trial boot confirmed, and afterwards the image kernel #11 was restored (DRAM: 1024 MiB, MTU 1500).

**Setup trap:** netplan's networkd config has `[DHCP] UseMTU=true`, so every link bounce re-applied the
DHCP MTU 1500. `ip link set end0 mtu 2000` returned 0 but the MTU was back at 1500 about 5 s later.
For the test I added a volatile drop-in in /run/systemd/network/10-netplan-all-eth-interfaces.network.d/
with `[DHCPv4] UseMTU=no`. Removed afterwards. Anyone using jumbo MTU on this image must do the same
(or set MTUBytes in netplan), or stop the DHCP server advertising MTU 1500.

| Test | Result |
|---|---|
| maxmtu reported | 2021; RX_CTL0 (ethtool -d, 0x24) = 0xa8010000, so bit 29 is set |
| MTU 1500 DF ping 1472, both directions | 10/10 both |
| MTU 1500 iperf3 TCP | 941 / 879 Mbit/s (host->board / board->host); 0 errors |
| MTU 1500, host sends -s 1480 / 1600 / 3000 | 5/5 (fits the 1536 buffer) / 0 / 0. Dropped whole: rx_length +2 per frame (head + tail descriptor), normal traffic fine after |
| MTU 2000 DF ping 1971/1972, both directions | 10/10 both |
| MTU 2000 iperf3 TCP | 956 / 915 Mbit/s; 0 new errors |
| MTU 2021 DF ping 1992/1993, both directions | 10/10 both |
| MTU 2021 iperf3 TCP (MSS 1969) | 946 / 913 Mbit/s; 0 new errors |
| MTU 2021 iperf3 UDP -l 1993 at 900M | host->board 886 Mbit/s with 1.5 % loss (CPU-bound RX at about 57 kpps); board->host 900 Mbit/s, 0 % loss |
| MTU 2022 / 3000 / 3712 | "Error: mtu greater than device maximum.", MTU unchanged, no link bounce |
| down/up at MTU 2000 | RX_CTL0 bit 29 still set; ping 1972 10/10 both directions |
| Oversize at MTU 2021, host -s 2001/2002/2600/3684 | all dropped whole (rx_length +2 each), no stall, normal ping 5/5 after |
| VLAN at 2021 | not run: needs a VLAN on the host NIC, and we have no sudo |
| suspend/resume | not run |

**RX boundary measured** (host DF pings, frame = s + 46 bytes including FCS): s = 1994..1998
(frames 2040..2044) are received, s = 1999/2000 (2045/2046) are not. The RX DMA only fills a multiple of 4
bytes of the 2047 programmed, so the real single-descriptor limit is **2044 bytes**. U-Boot's sun8i_emac
uses CFG_ETH_RXSIZE 2044 for the same reason. At MTU 2021, an untagged or single-tagged max frame (2039/2043)
fits, but a double-tagged one (2047) would not. The patch was therefore corrected to
EMAC_MAX_FRAME_LEN 2044, so maxmtu is 2018 (still covers two tags). TX of 2035-byte frames (not a multiple
of 4) works, so the restriction is RX-only.

## Board results, round 2 (Image.jumbo2, maxmtu 2018), 2026-11-03

Same trial procedure as round 1. Raw output: emac-jumbo/r2-*.txt.
- maxmtu 2018; RX_CTL0 = 0xa8010000 (JUMBO_FRM_EN set).
- MTU 2000: DF ping 1472/1971/1972 10/10 in both directions; iperf3 952 / 910 Mbit/s; 0 rx errors.
- MTU 2018: DF ping 1472/1989/1990 10/10 in both directions; iperf3 956 / 906 Mbit/s; 0 rx errors.
- `mtu 2019` is refused and the MTU stays at 2018.
- Restored afterwards: image kernel #11, DRAM: 1024 MiB, MTU 1500. Removed the trial files, the .good modules dir,
  /root/jumbo-bak, the jumbo-fallback unit/script and the /run UseMTU drop-in from the board.
