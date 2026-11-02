#!/bin/sh
# One-time host setup for board WiFi tests (run as: sudo harness/wifi-host-setup.sh).
# - adds aruni to netdev, so Claude can drive wlo1 through wpa_supplicant's D-Bus API
#   (station or AP mode) without sudo
# - installs iperf3 for throughput tests
# - pins wlo1 to the isolated 10.57.0.0/24 test subnet (no default route)
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
cd "$(dirname "$0")"
usermod -aG netdev aruni
DEBIAN_FRONTEND=noninteractive apt-get install -y iperf3
install -m 0644 07-opiz2-wlo1.network /etc/systemd/network/
networkctl reload
networkctl status wlo1 --no-pager | sed -n 1,8p
echo "done"
