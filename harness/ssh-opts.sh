# Sourced by harness/ssh.sh and every runner package that talks to the board (bash): one set of ssh/scp options.
#   . /home/aruni/orangepizero2/harness/ssh-opts.sh; K=("${BOARD_SSH_OPTS[@]}")   then  scp "${K[@]}" ...
# Why (status.md item 8, 2026-11-06): job 16's restore ssh sat 1.5 h on a board that had reset under it (the old
# options had no keepalive and the step watchdog did not cover that call). Now:
#  - ConnectTimeout: a board that is down or rebooting fails the connect within 8 s;
#  - ServerAliveInterval/CountMax: an open session to a board that died or reset ends after 15 s x 8 = 2 min;
#  - BatchMode: never wait for a password/passphrase/host-key prompt;
#  - host keys: the harness's own known_hosts (reset by reflash.sh step 9, as the board regenerates its host keys on
#    the first boot of every new image), StrictHostKeyChecking=accept-new: a first contact is recorded, a CHANGED key
#    fails ("Host key verification failed") instead of being accepted silently as StrictHostKeyChecking=no did.
#    After a reflash not done by reflash.sh: ssh-keygen -R 10.56.0.107 -f harness/known_hosts (only that file).
#  - scp() below: an overall timeout for copies (SCP_TIMEOUT s, default 900), killed with KILL 10 s later;
#    harness/ssh.sh takes SSH_TIMEOUT=<s> for the same on one-shot commands.
#  - kill_pid <pid>: what stall watchdogs use on the background ssh they started (exact PID, never pkill -f):
#    TERM, then KILL if it is still there after 5 s.
BOARD_HARNESS=/home/aruni/orangepizero2/harness
BOARD_ADDR=root@10.56.0.107
BOARD_SSH_OPTS=(-i "$BOARD_HARNESS/id_ed25519" -o IdentitiesOnly=yes -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$BOARD_HARNESS/known_hosts" -o GlobalKnownHostsFile=/dev/null
  -o ConnectTimeout=8 -o ServerAliveInterval=15 -o ServerAliveCountMax=8 -o LogLevel=ERROR)
scp() { timeout --foreground -k 10 "${SCP_TIMEOUT:-900}" /usr/bin/scp "$@"; }
kill_pid() { local p=$1 i; kill "$p" 2>/dev/null || return 0
  for i in 1 2 3 4 5; do kill -0 "$p" 2>/dev/null || return 0; sleep 1; done; kill -9 "$p" 2>/dev/null; return 0; }
