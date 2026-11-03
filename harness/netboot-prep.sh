#!/usr/bin/env bash
# One-shot host prep for hands-off reflash (harness/reflash.sh) and the jumbo-frame test.
# Touches ONLY the Zero2 test link enx68da73af6279 (10.56.0.1). Run: harness/netboot-prep.sh
#   1. installs the updated 06-opiz2 .network (MTUBytes=9000, DefaultLeaseTimeSec=5min)
#   2. replaces the PXE drop-in (BootServerAddress only; BootFilename dropped)
#   3. ufw: allows TFTP (69/udp) and the flasher HTTP server (8080/tcp) in on that link
#   4. reloads networkd, restarts dnsmasq, verifies
set -euo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IF=enx68da73af6279 NET=06-opiz2-enx68da73af6279.network HOST_IP=10.56.0.1
D=/etc/systemd/network/$NET.d

echo "== 1. network file"
sudo install -m 0644 "$H/$NET" /etc/systemd/network/$NET
echo "== 2. PXE drop-in"
sudo install -d -m 0755 "$D"
printf '[DHCPServer]\nBootServerAddress=%s\n' "$HOST_IP" | sudo tee "$D/netboot.conf" >/dev/null
echo "== 3. firewall"
if systemctl is-active -q ufw; then
	sudo ufw allow in on "$IF" to "$HOST_IP" port 69 proto udp comment 'opiz2 tftp'
	sudo ufw allow in on "$IF" to "$HOST_IP" port 8080 proto tcp comment 'opiz2 flasher http'
fi
echo "== 4. reload"
sudo networkctl reload
sudo networkctl reconfigure "$IF"
sudo systemctl restart dnsmasq
sleep 3
echo "== verify"
ip -br link show "$IF"; ip -d link show "$IF" | grep -o 'mtu [0-9]*' | head -1
grep -q BootFilename "$D/netboot.conf" && echo "FAIL BootFilename still set" || echo "OK  drop-in: $(tr '\n' ' ' < "$D/netboot.conf")"
grep -q DefaultLeaseTimeSec /etc/systemd/network/$NET && echo "OK  DefaultLeaseTimeSec set" || echo "FAIL lease time"
systemctl is-active -q dnsmasq && echo "OK  dnsmasq active" || echo "FAIL dnsmasq"
printf 'netboot-selftest\n' > /srv/tftp/opiz2/.selftest
curl -s --connect-timeout 3 "tftp://$HOST_IP/.selftest" | grep -q netboot-selftest && echo "OK  TFTP" || echo "FAIL TFTP"
rm -f /srv/tftp/opiz2/.selftest
ping -c2 -W2 10.56.0.107 >/dev/null && echo "OK  board reachable" || echo "WARN board not answering ping (link renegotiating? retry in 10 s)"
