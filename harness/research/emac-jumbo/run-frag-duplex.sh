#!/bin/bash
# Host side, EMAC follow-up (impl-emac-jumbo.md, 2026-11-05 round). Never touches host interfaces.
#   run-frag-duplex.sh frag LABEL     8000-byte (fragmented) pings both ways + IP reassembly/NIC counters
#   run-frag-duplex.sh duplex         forced 100/10 Mbit half/full on the board (auto-revert armed), iperf3 + frag ping each
H=/home/aruni/orangepizero2/harness; SSH=$H/ssh.sh; B=10.56.0.107
stats() { $SSH "nstat -az IpReasmReqds IpReasmOKs IpReasmFails IpReasmTimeout IpFragOKs IpFragFails IpFragCreates IpInDiscards 2>/dev/null | awk 'NR>1{printf \"%s=%s \", \$1, \$2}'; ethtool -S end0 | grep -E ' (rx_length|rx_crc_errors|overflow_error|rx_desc|rx_errors|tx_errors|rx_missed_cntr|rx_overflow_cntr|tx_underflow):' | tr -s ' ' | tr '\n' ' '; ip -s link show end0 | awk '/RX:/{getline; print \"RXpk=\"\$2, \"RXerr=\"\$3, \"RXdrop=\"\$4} /TX:/{getline; print \"TXpk=\"\$2, \"TXerr=\"\$3, \"TXdrop=\"\$4}' | tr '\n' ' '"; echo; }
frag() {
	echo "== frag $1: board mtu $($SSH cat /sys/class/net/end0/mtu) $($SSH "ethtool end0 | grep -E 'Speed|Duplex' | tr -d '\t' | tr '\n' ' '")"
	echo "-- before: $(stats)"
	for s in 3000 8000 16000; do
		r1=$(ping -c 50 -i 0.2 -W 2 -s $s $B 2>&1 | grep -oE '[0-9]+ received|[0-9.]+% packet loss' | tr '\n' ' ')
		r2=$($SSH "ping -c 50 -i 0.2 -W 2 -s $s 10.56.0.1 2>&1 | grep -oE '[0-9]+ received|[0-9.]+% packet loss' | tr '\n' ' '")
		echo "ping -s $s x50: host->board $r1; board->host $r2"
	done
	echo "-- after: $(stats)"
}
duplex() {
	$SSH "pgrep -x iperf3 >/dev/null || iperf3 -s -D"
	for m in '100 full' '100 half' '10 full' '10 half'; do set -- $m
		echo "=== forced $1/$2"
		$SSH "systemd-run --on-active=300 --unit=bpethrevert --collect ethtool -s end0 autoneg on >/dev/null 2>&1; ethtool -s end0 speed $1 duplex $2 autoneg off" 2>/dev/null
		sleep 8; for i in $(seq 1 30); do $SSH true 2>/dev/null && break; sleep 2; done
		echo "board: $($SSH "ethtool end0 | grep -E 'Speed|Duplex' | tr -d '\t' | tr '\n' ' '; dmesg | grep 'Link is Up' | tail -1")"
		echo "host:  $(ethtool enx68da73af6279 2>/dev/null | grep -E 'Speed|Duplex' | tr -d '\t' | tr '\n' ' ')"
		echo "-- before: $(stats)"
		t=10; [ $1 = 10 ] && t=15
		echo "iperf3 host->board: $(iperf3 -c $B -t $t -f m 2>&1 | grep -E 'receiver' | awk '{print $7, $8}')  retr $(iperf3 -c $B -t 5 -f m 2>&1 | grep sender | awk '{print $9}')"
		echo "iperf3 board->host: $(iperf3 -c $B -t $t -R -f m 2>&1 | grep -E 'receiver' | awk '{print $7, $8}')"
		r1=$(ping -c 20 -i 0.2 -W 2 -s 8000 $B 2>&1 | grep -oE '[0-9.]+% packet loss')
		r2=$(ping -c 20 -i 0.2 -W 2 -s 1472 $B 2>&1 | grep -oE '[0-9.]+% packet loss')
		echo "ping 8000 x20: $r1; ping 1472 x20: $r2"
		echo "-- after: $(stats)"
		$SSH "ethtool -s end0 autoneg on; systemctl stop bpethrevert.timer 2>/dev/null" 2>/dev/null
		sleep 8; for i in $(seq 1 30); do $SSH true 2>/dev/null && break; sleep 2; done
	done
	echo "back to: $($SSH "ethtool end0 | grep -E 'Speed|Duplex' | tr -d '\t' | tr '\n' ' '")"
}
case $1 in frag) frag "$2" ;; duplex) duplex ;; esac
