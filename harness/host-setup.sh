#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# One-shot host setup for the Orange Pi Zero2 test harness. Run as your normal user: ./harness/host-setup.sh
# Does the root bits (udev rule, networkd link) via sudo and creates the GitHub project repo.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1. serial: udev rule for the CP2102 on USB port 3-4 -> /dev/ttyOPIZ2 (does not touch port 3-3 / ttyUSB0)"
sudo cp harness/99-opiz2-serial.rules /etc/udev/rules.d/
sudo udevadm control --reload
sudo udevadm trigger -s tty
sleep 1; ls -l /dev/ttyOPIZ2

echo "== 2. network: 10.56.0.1/24 + DHCP/NAT on the USB adapter, board pinned to 10.56.0.107"
sudo cp harness/06-opiz2-enx68da73af6279.network /etc/systemd/network/
sudo networkctl reload
networkctl status enx68da73af6279 | grep -E 'State|Address: 10'

echo "== 3. GitHub: create SomeComputerGuy/orangepizero2 and push main"
if gh repo view SomeComputerGuy/orangepizero2 >/dev/null 2>&1; then
	git remote get-url origin >/dev/null 2>&1 || git remote add origin git@github.com:SomeComputerGuy/orangepizero2.git
	git push -u origin main
else
	gh repo create SomeComputerGuy/orangepizero2 --public --source . --remote origin --push \
		--description 'Orange Pi Zero2 (Allwinner H616): mainline Armbian bring-up, Ubuntu 26.10, print server'
fi
gh repo view SomeComputerGuy/orangepizero2 --json url -q .url

echo "== 4. WiFi credentials for board tests (stored only in local.env, chmod 600, git-ignored)"
if ! grep -q '^OPIZ2_WIFI_SSID=' local.env 2>/dev/null; then
	read -rp "WiFi SSID for the board to join (Enter to skip): " ssid
	if [[ -n $ssid ]]; then
		read -rsp "WiFi password: " psk; echo
		printf 'OPIZ2_WIFI_SSID=%s\nOPIZ2_WIFI_PSK=%s\n' "$ssid" "$psk" >> local.env
		chmod 600 local.env
	fi
fi
echo "done"
