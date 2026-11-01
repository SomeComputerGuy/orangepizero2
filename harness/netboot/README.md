# Zero2 netboot link: DHCP identity rules

systemd-networkd's DHCP server (host, `06-opiz2-enx68da73af6279.network`) keys every bound
lease by the client identifier: option 61 if the client sends one, else `01:<MAC>` built from
the frame header (`dhcp_request_set_client_id()`, src/libsystemd-network/dhcp-server-request.c).
A `[DHCPServerStaticLease] MACAddress=` entry is stored under the `01:<MAC>` key and matched
for any client of that MAC through the same header fallback — but `dhcp_server_process_discover()`
then checks `bound_leases_by_address[static address]` and, if that lease belongs to a
different client identity, returns `-EADDRINUSE` and sends nothing (no OFFER, no NAK).

That is exactly the U-Boot → Linux handover on this link: U-Boot's `dhcp`/`pxe` sends no
option 61 (U-Boot has no client-id support) → lease `.107` bound to `01:02:00:8a:27:57:7d`
for `DefaultLeaseTimeSec` (1 h if unset; U-Boot never renews or releases). Linux networkd
(Armbian netplan default) identifies as RFC 4361 `ff:<IAID>:<DUID>` → static lease found via
the MAC fallback, address bound to someone else → refused for the rest of the hour,
across reboots (the server persists leases, `PersistLeases=yes`).

What other servers do: ISC dhcpd `host { hardware ethernet …; fixed-address …; }` matches by
MAC and does not track fixed addresses as leases, so the OS simply gets the reservation;
dnsmasq (most home routers) keys leases by client-id too but treats a lease with the same
MAC as the same machine and lets the OS take it over (`dhcp-host=<mac>,<ip>`); without a
reservation a router hands the firmware and the OS two different pool addresses and nobody
notices. networkd's server is the strict one.

Fix, in order of correctness:
1. Board (the right place: a netboot-capable device should present one DHCP identity from
   firmware, kernel `ip=dhcp` and OS): `dhcp-identifier: mac` in the Armbian netplan
   config, i.e. networkd `ClientIdentifier=mac`. One-time, on the board:
   ```
   cat /etc/netplan/*.yaml            # note the ethernet definition id (Armbian default: all-eth-interfaces)
   sudo netplan set ethernets.all-eth-interfaces.dhcp-identifier=mac
   sudo netplan apply
   networkctl status <iface> | grep -i 'DHCP'     # client id now 01:02:00:8a:27:57:7d, lease .107
   ```
   (Equivalent snippet: `netplan/opiz2-dhcp-identifier-mac.yaml`; merge it into the existing
   definition rather than adding a second one matching the same NIC.)
2. Host (defence in depth, applied by `netboot-setup.sh` through the .network file):
   `DefaultLeaseTimeSec=5min` so a firmware-only lease can block the address for minutes,
   not an hour (networkd's minimum is 30 s; Linux renews at T1 = 2.5 min, harmless here).
3. Unblock a board that is locked out *now*: the bound lease lives in the server and in
   `/var/lib/systemd/network/dhcp-server-lease/`. `sudo networkctl reconfigure enx68da73af6279`
   restarts the server; if it reloads the stale lease, run
   `sudo systemctl stop systemd-networkd && sudo rm -f /var/lib/systemd/network/dhcp-server-lease/* && sudo systemctl start systemd-networkd`
   (test link only; nothing else leases from this host). Or wait for the lease to expire.

Not done on purpose: making U-Boot send option 61 (upstream U-Boot has no such option and the
kernel's `ip=dhcp` would still differ), removing the static lease (the harness depends on
.107), `PersistLeases=no` (hides the symptom, leases still collide within a boot).
