#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Armbian customize-image hook: runs chrooted in the image at the end of the build.
# Board-level configuration for the Orange Pi Zero2 print server. Keep everything here
# (not on the board) so a clean build reproduces the deployed state.
set -euo pipefail
RELEASE=$1; LINUXFAMILY=$2; BOARD=$3; BUILD_DESKTOP=$4

# Networking. The stack is Armbian's NETWORKING_STACK: systemd-networkd on minimal, NetworkManager
# on the server variant (BUILD_MINIMAL=no). Each Armbian network extension drops its netplan file
# before this script runs, so that file tells the stacks apart.
if [ -e /etc/netplan/10-dhcp-all-interfaces.yaml ]; then OPIZ2_NET=networkd
elif [ -e /etc/netplan/00-default-use-network-manager.yaml ]; then OPIZ2_NET=networkmanager
else OPIZ2_NET=none; echo "customize-image: no Armbian netplan config found, network tweaks skipped" >&2
fi

# 1. Do not hold boot for Wi-Fi: wait-online only needs one routable link (Ethernet usually).
# networkd only: NetworkManager-wait-online is disabled by Armbian, and on NetworkManager images
# networkd manages no link, so --any would only make systemd-networkd-wait-online time out.
if [ "$OPIZ2_NET" = networkd ]; then
mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d
cat > /etc/systemd/system/systemd-networkd-wait-online.service.d/any-link.conf <<'CONF'
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-networkd-wait-online --any
CONF
fi

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
# networkd: extends Armbian's all-eth-interfaces netplan definition (10-dhcp-all-interfaces.yaml).
if [ "$OPIZ2_NET" = networkd ]; then
cat > /etc/netplan/20-dhcp-identifier-mac.yaml <<'NETPLAN'
network:
  version: 2
  ethernets:
    all-eth-interfaces:
      dhcp-identifier: mac
NETPLAN
chmod 600 /etc/netplan/20-dhcp-identifier-mac.yaml
fi
# NetworkManager: netplan defines no Ethernet connection there (NM's automatic "Wired connection"
# profiles do DHCP), so set the same identity as a connection default for Ethernet devices. A
# zz- file loads last, so its section takes precedence. ipv6.dhcp-duid=ll matches Armbian's
# networkd DUIDType=link-layer.
if [ "$OPIZ2_NET" = networkmanager ]; then
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/zz-30-opiz2-dhcp-identity.conf <<'CONF'
# Orange Pi Zero2: one DHCP identity (01:<MAC>) for U-Boot, the kernel's ip=dhcp and the OS.
[connection-opiz2-dhcp-identity]
match-device=type:ethernet
ipv4.dhcp-client-id=mac
ipv6.dhcp-duid=ll
CONF
fi

# 3. CUPS: reachable from the LAN, shared printers, web admin for the lpadmin group.
if command -v cupsd >/dev/null; then
	cupsctl --remote-admin --remote-any --share-printers 2>/dev/null || true
	systemctl enable cups cups-browsed ipp-usb avahi-daemon >/dev/null 2>&1 || true
fi
