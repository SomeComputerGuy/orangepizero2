#!/usr/bin/env bash
# ssh to the Zero2 as root with the harness key. Usage: harness/ssh.sh [cmd...]
exec ssh -i "$(dirname "$0")/id_ed25519" -o StrictHostKeyChecking=no -o UserKnownHostsFile="$(dirname "$0")/known_hosts" -o ConnectTimeout=8 -o LogLevel=ERROR root@10.56.0.107 "$@"
