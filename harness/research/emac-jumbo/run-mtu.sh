#!/bin/bash
# Host-side jumbo test round for one board MTU. Usage: run-mtu.sh <mtu> [iperf]
# Sets end0 MTU (link bounces), waits for ssh, then DF pings both ways at payload sizes around the MTU,
# optional iperf3 TCP both ways, and prints the counter deltas. Never touches host interfaces.
H=/home/aruni/orangepizero2/harness; SSH=$H/ssh.sh; B=10.56.0.107; mtu=$1
cnt() { $SSH "ethtool -S end0 | grep -E ' (rx_length|rx_crc_errors|overflow_error|rx_desc|rx_errors|tx_errors|rx_collision|ipc_csum_error):' | tr -s ' ' | tr '\n' ' '; ip -s link show end0 | awk '/RX:/{getline; print \"RXpk=\"\$2, \"RXerr=\"\$3, \"RXdrop=\"\$4} /TX:/{getline; print \"TXpk=\"\$2, \"TXerr=\"\$3}' | tr '\n' ' '"; echo; }
cur=$($SSH "cat /sys/class/net/end0/mtu")
if [ "$cur" != "$mtu" ]; then
	echo "== set mtu $mtu (was $cur)"
	$SSH "ip link set end0 mtu $mtu; echo rc=\$?" 2>&1
	sleep 4
	for i in $(seq 1 20); do $SSH true 2>/dev/null && break; sleep 2; done
fi
echo "== board: $($SSH 'cat /sys/class/net/end0/mtu; cat /sys/class/net/end0/carrier' | tr '\n' ' ')"
echo "-- counters before: $(cnt)"
max=$((mtu - 28))
for s in 1472 $((max - 1)) $max; do
	[ $s -gt $max ] && continue
	r1=$(ping -M do -s $s -c 10 -i 0.2 -W 1 $B 2>&1 | grep -o '[0-9]* received')
	r2=$($SSH "ping -M do -s $s -c 10 -i 0.2 -W 1 10.56.0.1 2>&1 | grep -o '[0-9]* received'")
	echo "ping -s $s: host->board $r1/10; board->host $r2/10"
done
echo "-- counters after pings: $(cnt)"
if [ "$2" = iperf ]; then
	$SSH "pgrep -x iperf3 >/dev/null || iperf3 -s -D"
	sleep 1
	echo "iperf3 host->board: $(iperf3 -c $B -t 10 -f m 2>&1 | grep -E 'receiver' | awk '{print $7, $8}')"
	echo "iperf3 board->host (-R): $(iperf3 -c $B -t 10 -R -f m 2>&1 | grep -E 'receiver' | awk '{print $7, $8}')"
	echo "-- counters after iperf: $(cnt)"
fi
