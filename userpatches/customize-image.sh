#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Armbian customize-image hook: runs chrooted in the image at the end of the build.
# Board-level configuration for the Orange Pi Zero2 print server. Keep everything here
# (not on the board) so a clean build reproduces the deployed state.
set -euo pipefail
RELEASE=$1; LINUXFAMILY=$2; BOARD=$3; BUILD_DESKTOP=$4

# 1. Do not hold boot for Wi-Fi: wait-online only needs one routable link (Ethernet usually).
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
cat > /etc/systemd/system/systemd-networkd-wait-online.service.d/any-link.conf <<'CONF'
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-networkd-wait-online --any
CONF

# 2. Hardware watchdog: sun4i wdt maximum is 16 s, so stay below it.
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/watchdog.conf <<'CONF'
[Manager]
RuntimeWatchdogSec=15
RebootWatchdogSec=2min
CONF

# DHCP: one identity (01:<MAC>) for U-Boot (netboot/PXE), kernel ip=dhcp and the OS. With the
# default DUID client ID, a server that keys leases by client ID (systemd-networkd's) refuses the
# OS its reserved address for the lease time after any U-Boot DHCP attempt.
cat > /etc/netplan/20-dhcp-identifier-mac.yaml <<'NETPLAN'
network:
  version: 2
  ethernets:
    all-eth-interfaces:
      dhcp-identifier: mac
NETPLAN
chmod 600 /etc/netplan/20-dhcp-identifier-mac.yaml

# 3. CUPS: reachable from the LAN, shared printers, web admin for the lpadmin group.
if command -v cupsd >/dev/null; then
	cupsctl --remote-admin --remote-any --share-printers 2>/dev/null || true
	systemctl enable cups cups-browsed ipp-usb avahi-daemon >/dev/null 2>&1 || true
fi
