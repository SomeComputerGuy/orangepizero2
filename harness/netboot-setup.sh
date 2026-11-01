#!/usr/bin/env bash
# Host-side netboot (DHCP + TFTP/PXE) setup for the Orange Pi Zero2 test link.
#
# Layout: systemd-networkd keeps serving DHCP on the Zero2 link (10.56.0.1/24,
# harness/06-opiz2-enx68da73af6279.network) and additionally hands out the PXE
# boot server (siaddr) and boot file (option 67) through a drop-in; dnsmasq runs
# in TFTP-only mode (port=0: no DNS, no DHCP) bound to that interface and serves
# $TFTP_ROOT. U-Boot's distro "pxe" target then does: dhcp -> tftp
# pxelinux.cfg/default-arm-sunxi -> tftp Image/dtb/initrd -> booti.
#
# Root is needed for: apt-get, /etc/dnsmasq.d, /etc/systemd/network drop-in,
# systemctl/networkctl, creating $TFTP_ROOT. Every such step runs via sudo and is
# listed by --dry-run. Files in $TFTP_ROOT are owned by $USER so netboot-stage.sh
# needs no root.
set -euo pipefail

HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IFACE="${IFACE:-enx68da73af6279}"
HOST_IP="${HOST_IP:-10.56.0.1}"
TFTP_ROOT="${TFTP_ROOT:-/srv/tftp/opiz2}"
NETWORK_FILE="${NETWORK_FILE:-06-opiz2-enx68da73af6279.network}"
PXE_CFG="pxelinux.cfg/default-arm-sunxi" # U-Boot's 2nd default path (default-arm-sunxi-sunxi, default-arm-sunxi, default-arm)
DRY=""
[[ ${1:-} == --dry-run ]] && DRY="echo [sudo]"

run_root() { if [[ -n $DRY ]]; then echo "[sudo] $*"; else sudo "$@"; fi; }

echo "== 1. dnsmasq (TFTP only)"
if ! command -v dnsmasq > /dev/null; then
	run_root apt-get install -y dnsmasq
fi
DNSMASQ_CONF="$HARNESS/netboot/dnsmasq-opiz2-tftp.conf"
mkdir -p "$HARNESS/netboot"
cat > "$DNSMASQ_CONF" <<- EOF
	# Orange Pi Zero2 test link: TFTP server only. DHCP stays with systemd-networkd
	# ($NETWORK_FILE), DNS stays with systemd-resolved (port=0 disables dnsmasq DNS).
	port=0
	interface=$IFACE
	bind-interfaces
	enable-tftp
	tftp-root=$TFTP_ROOT
	# U-Boot asks for files that do not exist while probing pxelinux.cfg/ names; keep quiet.
	log-facility=/var/log/dnsmasq-opiz2.log
EOF
run_root install -m 0644 "$DNSMASQ_CONF" /etc/dnsmasq.d/opiz2-tftp.conf
run_root install -d -m 0755 -o "$USER" -g "$(id -gn)" "$TFTP_ROOT" "$TFTP_ROOT/pxelinux.cfg"

echo "== 2. systemd-networkd DHCP: PXE boot server + boot file (drop-in)"
DROPIN_DIR="$HARNESS/netboot/$NETWORK_FILE.d"
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN_DIR/netboot.conf" <<- EOF
	# PXE hints for U-Boot's "dhcp"/"pxe" boot targets (systemd >= 251):
	# siaddr = TFTP server, option 67 = file U-Boot's \`dhcp\` command fetches first
	# (pointing it at the pxe config avoids the "no boot file name" TFTP noise).
	[DHCPServer]
	BootServerAddress=$HOST_IP
	BootFilename=$PXE_CFG
EOF
run_root install -d -m 0755 "/etc/systemd/network/$NETWORK_FILE.d"
run_root install -m 0644 "$DROPIN_DIR/netboot.conf" "/etc/systemd/network/$NETWORK_FILE.d/netboot.conf"
[[ -f /etc/systemd/network/$NETWORK_FILE ]] || run_root install -m 0644 "$HARNESS/$NETWORK_FILE" "/etc/systemd/network/$NETWORK_FILE"

echo "== 3. (re)start services"
run_root networkctl reload
run_root systemctl enable --now dnsmasq
run_root systemctl restart dnsmasq

[[ -n $DRY ]] && exit 0
echo "== 4. verify"
sleep 1
systemctl is-active dnsmasq
ss -ulnH "( sport = :69 )" | grep -q "$HOST_IP:69" && echo "TFTP listening on $HOST_IP:69" || { echo "TFTP NOT listening on $HOST_IP:69"; exit 1; }
networkctl status "$IFACE" | grep -i -E 'DHCP|Address' | head -5 || true
printf 'netboot-selftest\n' > "$TFTP_ROOT/.selftest"
if curl -s --connect-timeout 3 "tftp://$HOST_IP/.selftest" | grep -q netboot-selftest; then echo "TFTP self-test ok"; else echo "TFTP self-test FAILED"; exit 1; fi
rm -f "$TFTP_ROOT/.selftest"
if ! grep -q '^DefaultLeaseTimeSec=' "/etc/systemd/network/$NETWORK_FILE"; then
	echo "NOTE: /etc/systemd/network/$NETWORK_FILE lacks DefaultLeaseTimeSec= (see harness/netboot/README.md);"
	echo "      reinstall it: sudo install -m 0644 $HARNESS/$NETWORK_FILE /etc/systemd/network/ && sudo networkctl reload"
fi
cat <<- EOM
	Board side, once (see $HARNESS/netboot/README.md): make Linux use the same DHCP identity as U-Boot,
	otherwise the static lease stays bound to U-Boot's 01:<MAC> after a netboot attempt and Linux gets no OFFER:
	  sudo netplan set ethernets.all-eth-interfaces.dhcp-identifier=mac && sudo netplan apply
	Now stage a kernel: $HARNESS/netboot-stage.sh  (writes $TFTP_ROOT/$PXE_CFG)
EOM
