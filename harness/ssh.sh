#!/usr/bin/env bash
# ssh to the Zero2 as root with the harness key. Usage: [SSH_TIMEOUT=<s>] harness/ssh.sh [cmd...]
# Options (keepalive, connect timeout, BatchMode, host-key file) live in harness/ssh-opts.sh, shared with the packages'
# scp calls. SSH_TIMEOUT=<s>: overall limit for a one-shot command (KILL 10 s after); unset = no limit (long steps run
# under their own board-side `timeout` and the package's stall watchdog). Either way the PID a caller gets for
# `harness/ssh.sh ... &` is the process to kill (ssh itself, or timeout, which passes the signal on).
. "$(dirname "$(readlink -f "$0")")/ssh-opts.sh"
if [ -n "${SSH_TIMEOUT:-}" ]; then exec timeout --foreground -k 10 "$SSH_TIMEOUT" /usr/bin/ssh "${BOARD_SSH_OPTS[@]}" "$BOARD_ADDR" "$@"; fi
exec /usr/bin/ssh "${BOARD_SSH_OPTS[@]}" "$BOARD_ADDR" "$@"
