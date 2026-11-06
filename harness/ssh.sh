#!/usr/bin/env bash
# ssh to the Zero2 as root with the harness key. Usage: harness/ssh.sh [cmd...]
# ConnectTimeout + ServerAlive (2 min): a session whose board side hangs or reboots ends with an error instead of
# waiting forever (runner jobs 29/32, 2026-11-06).
exec ssh -i "$(dirname "$0")/id_ed25519" -o StrictHostKeyChecking=no -o UserKnownHostsFile="$(dirname "$0")/known_hosts" -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -o LogLevel=ERROR root@10.56.0.107 "$@"
