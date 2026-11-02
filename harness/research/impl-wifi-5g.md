# UWE5622 WiFi: 5 GHz AP, STA, regdomain, spec acceptance (a/b/g/n/ac)

Date: 2026-11-02. Board: Orange Pi Zero2, kernel 7.3.1 #6, sprdwl_ng (unisoc_wifi), fw wcnmodem.bin from armbian-firmware.
Host test client: wlo1 (Intel), driven via wpa_supplicant D-Bus with `harness/wifi-host.py` (new helper, `sg netdev -c "python3 -I harness/wifi-host.py <scan|sta|ap|state|wait|down>"`).

## 1. 5 GHz AP never beacons -- ROOT CAUSE FOUND

Debug: `echo 3 > /sys/module/sprdwl_ng/parameters/debug_level` (param `debug_level`, 0=ERR..3=DBG; default 1).
Command trace for hostapd ch36 HT20: OPEN -> SET_IE x3 -> START_AP -> DEL_STATION -> KEY x2. No channel command
at all: `sprdwl_cfg80211_start_ap()` never looks at `settings->chandef`; the only channel hook,
`sprdwl_cfg80211_set_channel`, is wired to `.libertas_set_mesh_channel` (never called for AP). The vendor
4.9/5.4/6.1 sun50iw9 drivers are identical here.

The firmware therefore takes the operating channel from the DS Parameter Set element (EID 3) in the beacon
it is handed. hostapd only emits DS Params for 2.4 GHz (hw_mode g/b), so on 5 GHz the firmware has no channel
and does not beacon (or beacons somewhere we cannot see).

Proof (no kernel change): add `vendor_elements=030124` (DS Params, channel 36) to the ch36 HT20 config ->
host immediately sees `opiz2-test-5g` on 5180 MHz at -52..-60 dBm.

Note: hostapd moved the primary from 36 to 40 for VHT80 ("Switch own primary and secondary channel", a neighbour
AP beacons on 5200), so the DS element must carry the *final* primary channel (cfg80211 chandef), not the
configured one. With DS=36 while hostapd used primary 40, the AP stayed invisible on 5180.

### Measured (proof config: VHT80, primary ch40 / centre 42, DS IE injected via vendor_elements=030128)
- Host sees AP at 5200 MHz -53 dBm, associates in <1 s. SignalPoll: width 80 MHz, rx-vht-mcs 7..9, tx-vht-mcs 6..9, nss 1, SGI.
- iperf3 15 s host->board: 125 Mbit/s sender / 123 receiver, 0 retr.
- iperf3 15 s board->host (-R): 119 / 118 Mbit/s, 168 retr.
- CAUTION: with debug_level=3 the console printk thread (pr/ttyS0) eats 96% CPU and board->host drops to 8.8 Mbit/s;
  always set debug_level back to 1 before measuring.

## 2. wpa_supplicant AP mode (mode=2)
Re-tested 2026-11-02 21:45 with /root/ap24.conf (2437 MHz, WPA2-CCMP): command trace identical to hostapd
(OPEN, SET_IE x3, START_AP, DEL_STATION, KEY), host sees `opiz2-test-24` at 2437 MHz -54 dBm, associates in 1 s,
iperf3 15 s host->board 31.5 Mbit/s, board->host 41.4 Mbit/s (HT20 MCS6/7 SGI). So wpa_s AP mode on 2.4 GHz
WORKS; the earlier "no beacons" on 2.4 was not reproducible (likely a host scan that had not finished --
an active scan here takes >6 s). wpa_s AP on 5 GHz fails for the same DS-element reason as hostapd.

## 3. Fix A: insert DS Parameter Set in start_ap (patch drv-net-wireless-uwe5622-softap-5ghz-ds-params.patch)
`sprdwl_beacon_add_ds_params()` inserts EID 3 (len 1, channel = ini softap_channel override if valid, else
`settings->chandef.chan->hw_value`) after SSID/Supported Rates when the beacon head lacks it.
Tested as an out-of-tree build of sprdwl_ng.ko against kernel-check/work-vdec/linux-7.3.1 (the board's running
kernel; BTF sections stripped with objcopy because the module BTF did not validate against the running vmlinux),
`rmmod sprdwl_ng; insmod sprdwl_ng-a.ko disable_powersave=1`, stock /root/hostapd5-20.conf (no vendor_elements):
- hostapd ch36 "HT20": beacon at 5180 -52 dBm, host associates in 1.5 s. iperf3 15 s host->board 128 Mbit/s,
  board->host 96.5 Mbit/s (140 retr). Host reports width 80 MHz, tx VHT MCS9 NSS1 SGI (433 Mbit/s).
- wpa_supplicant mode=2 /root/ap5.conf (5180 + vht_center_freq1=5210): wpa_s moved to 5200 (primary 40, HT40-),
  beacons, host associates in 0.5 s at 80 MHz. wpa_s AP on 5 GHz therefore PASSES with Fix A.

### Firmware picks the AP bandwidth itself (limitation, documented)
Beacon elements as received by the host (`wifi-host.py ies opiz2`):
- hostapd ch36 with ieee80211n=1 only (HT20, no VHT in config): HTCap 0x016f (HT40 bit set), HT Oper primary 36
  secoff=+1 STA-chw=any, VHT Oper chw=1 seg0=42. I.e. the firmware rebuilds HT/VHT elements and runs VHT80.
- hostapd ch165 HT20: HT Oper primary 165 secoff=0, VHT Oper chw=0 -> 20 MHz (165 has no 40/80 partner).
- wpa_s primary 40: HT Oper secoff=3 (below) VHT80 seg0 42.
- The DS element itself is stripped by the firmware from 5 GHz beacons; no Country element unless ieee80211d=1.
So the firmware takes only the primary channel from the host and always uses the widest 20/40/80 block that
contains it. hostapd's ht_capab/vht_oper_chwidth do not narrow it. Fine for US/ETSI UNII-1/3 channels, but it is a
firmware behaviour, not something the driver can pass (no width field in WIFI_CMD_START_AP).

## 4. Fix B: AP-mode station list (drv-net-wireless-uwe5622-ap-station-dump.patch)
Before: no .dump_station, so `iw station dump` was empty. get_station answered for any MAC, because
WIFI_CMD_GET_STATION has no address, and in AP mode it reported signal 0 and an unknown rate. That is a
firmware limit: there are no per-station stats.
After: AP/GO mode answers from the LUT peer table (intf->peer_entry, filled by sprdwl_event_sta_lut).
Unknown MACs return -ENOENT, and connected time comes from a timestamp taken when the peer is added. STA
mode dump returns the AP. Tested: `Station 34:13:e8:de:07:c9 ... connected time: 3 seconds`, and an
unknown MAC returns -2. The empty-ACL error log on each AP start was moved to debug level.

## 5. Board as STA, plus Fix C (drv-net-wireless-uwe5622-sta-renotify-ipv4.patch)
Host AP = wpa_supplicant mode=2 on wlo1 (Intel), through D-Bus. 2437 works, and 5180 works too: LAR did not refuse it.
- 2.4 GHz WPA2: associated in 3 s, -42 dBm, MCS7 65 Mbit/s. iperf3 15 s: host->board 28.7, board->host 45.1 Mbit/s.
- rtcwake -m mem -s 10 (twice): reconnected about 1 s after resume, traffic OK.
- AP restart: reassociated about 1 s after the AP returned. **Bug found:** the host could not reach the
  board afterwards (ARP "Destination Host Unreachable", wlan0 rx_packets frozen). The same happened on an open AP.
  Root cause: firmware ARP offload. The firmware passes only ARP for the IP given in
  WIFI_CMD_NOTIFY_IP_ACQUIRED, forgets it on reassociation, and the driver only sends it from the inetaddr
  notifier on address add. Proof: `ip addr del/add` restored reachability at once. With the stock module the
  failure reproduced after an AP restart. With Fix C, pings succeeded on first association with a preset IP, after
  2 AP restarts, and after suspend.
- 5 GHz STA (host AP 5180, 20 MHz only): VHT-MCS 9 NSS1 86.7 Mbit/s, -45 dBm. iperf3 15 s: host->board
  71.9, board->host 53.7 Mbit/s. That proves 802.11ac as STA at 20 MHz. VHT80 STA needs an 80 MHz AP.
- Test artifact, not fixed: the firmware scan cache keys BSS info by BSSID. After the host AP changed SSID on the
  same MAC, the board reported the old SSID (even on the new band). The result was "No network configuration found"
  or a PSK mismatch until the same SSID was reused. A real AP renaming itself would hit this too (rare).

## 6. Legacy PHY modes (all against the board AP, host client restricted)
- 802.11g: host disable_ht=1 -> "20 MHz (no HT)", 54 Mbit/s. iperf3 10 s 19.7 / 22.7 Mbit/s.
- 802.11a: 5180, disable_ht+disable_vht -> 54 Mbit/s. iperf3 10 s 29.7 / 34.0 Mbit/s.
- 802.11b: hostapd hw_mode=b is ignored by the firmware (beacon still carries HT Cap/Oper, client gets MCS7).
  DSSS works: right after association the host reports linkrxspeed 1000 (1 Mbit/s DSSS frames from the board),
  and 2.4 GHz beacons/probe responses are DSSS. A pure 11b-only BSS cannot be forced (firmware limitation).

## 7. Regulatory domain
- SET_REGDOM reaches the firmware on every change (debug_level=2 trace: WIFI_CMD_SET_REGDOM sent and acked
  after `iw reg set 00` and `iw reg set US`).
- Persistent knob: `options cfg80211 ieee80211_regdom=XX` in /etc/modprobe.d/cfg80211-regdom.conf. Tested on the
  board: after reloading cfg80211 + sprdwl_ng, `iw reg get` shows US with no iw call. The image writes the file
  (commented out, or set from build variable OPIZ2_WIFI_REGDOM). The file with US is left on the test board.
- Without the knob: world 00 at boot. hostapd country_code= and wpa_supplicant country= set it. cfg80211 resets
  to world on disconnect and the user setting is re-applied (seen in wpa_s log: REGDOM-CHANGE CORE WORLD, then USER US).

## 8. Side observations
- Copying a file from host to board over end0 (scp, ssh cat) stalled at exactly 512 KiB twice; the same copy
  over WiFi took 2 s. Possible EMAC RX issue, reported to main.
- debug_level=3 floods the serial console (pr/ttyS0 at 96% CPU) and cuts throughput about 10x.
