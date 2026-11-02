# uwe5622: driver pin bump, service/power-save fixes, regdomain, 5 GHz SoftAP, quieter logs

Branch: `pr/group/uwe5622` (d9826b7b1). Fork: SomeComputerGuy/build. Base: armbian/build `main` c2908d2 (2026-11-02). Draft only, not opened.

## What (8 commits)
- Pin bump to armbian/uwe5622 master f88cd0d25ff6 (IGTK OOB key write, Bad page state on unload, rfkill oops,
  cfg80211 unregister warning, TCP ACK stall).
- aw859a-wifi/bluetooth.service: correct unit types, BT ordered after WLAN, retry until the WCN firmware is up.
- Ship `/etc/modprobe.d/sprdwl_ng.conf` with `disable_powersave=1`.
- Kernel patches on the pin: bt_wake DT node optional (no error at every boot), unused-variable warning,
  regulatory domain from cfg80211 with correctly packed firmware rules (SUPE4COOKIE's fix), quiet expected log
  lines, 5 GHz SoftAP (DS Parameter Set from the chandef), AP station dump, IPv4 re-notify after reassociation.

## Why / evidence (Orange Pi Zero2)
- Power save: firmware acks power-down during the 4-way handshake; first association 12-25 s late.
- Regdomain: any country outside the driver's 7-entry table fell back to world, and only the first rule reached
  the firmware (DFS channels associated but passed no traffic).
- 5 GHz AP never beaconed (firmware takes the channel from the DS element hostapd only emits on 2.4 GHz). With the
  fix: hostapd ch36 beacons, host associates in 1.5 s, iperf3 128 Mbit/s host->board, 96.5 Mbit/s board->host,
  VHT80 MCS9; wpa_supplicant AP on 5 GHz also works (harness/research/impl-wifi-5g.md).
- After an AP restart the board was unreachable by ARP until the IPv4 address was re-sent.

## Upstream status
The driver patches should also go to armbian/uwe5622 so the pin can carry them; regdomain is SUPE4COOKIE's
unmerged fix.

## Notes
Firmware limitation (documented, not fixable in the driver): the AP always uses the widest 20/40/80 MHz block
containing the primary channel. The service/power-save changes affect every board with the uwe5622-allwinner
extension (Zero2/Zero2W/Zero3, WalnutPi); only the Zero2 was tested.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
