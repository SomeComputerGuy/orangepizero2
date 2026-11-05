#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# One owner on the board at a time (parallel agents share the single Orange Pi Zero2). First come, first served.
#   harness/board-lock.sh acquire <owner> [max-wait-s]   queues, blocks until it is this owner's turn, then holds it
#                                                        (exit 3 if <owner> already holds it: owner names are per session)
#   harness/board-lock.sh release <owner>                frees it (only the owner may)
#   harness/board-lock.sh status                         holder + waiting queue
# Hold it only while the board is actively in use (never across host builds or idle waits), and leave the board
# booted on the image kernel (or the trial-kernel fallback armed) before release. A lock older than 4 h is
# reported as stale but never broken automatically.
set -uo pipefail
Q=$(cd "$(dirname "$0")" && pwd)/queue; L=$Q/board.lock; W=$Q/board.wait
mkdir -p "$W"
head_ok() { # am I the oldest live waiter? (waiters whose process is gone are dropped)
  local f; for f in $(ls "$W" 2>/dev/null | sort); do
    kill -0 "${f##*.}" 2>/dev/null || { rm -f "$W/$f"; continue; }
    [ "$f" = "$1" ]; return; done; return 1; }
case "${1:-status}" in
  acquire) o=${2:?owner}; max=${3:-0}; t0=$(date +%s)
    # Not re-entrant: a second session with the same owner name must not run on the first one's lock, and its
    # release would free the lock under the first (2026-11-05). Use one distinct owner name per session.
    [ "$(cat "$L/owner" 2>/dev/null)" = "$o" ] && { echo "ERROR: already held by $o (another session with the same owner name?); use a distinct owner name per session" >&2; exit 3; }
    tk=$(date +%s%N).${o//[^A-Za-z0-9_-]/_}.$$; : > "$W/$tk"; trap 'rm -f "$W/$tk"' EXIT
    until head_ok "$tk" && mkdir "$L" 2>/dev/null; do
      (( max > 0 && $(date +%s) - t0 > max )) && { echo "busy: $(cat "$L/owner" "$L/since" 2>/dev/null | tr '\n' ' ')"; exit 1; }
      sleep 15; done
    echo "$o" > "$L/owner"; date '+%F %T' > "$L/since"; echo "acquired by $o" ;;
  release) o=${2:?owner}; [ "$(cat "$L/owner" 2>/dev/null)" = "$o" ] || { echo "not held by $o (owner: $(cat "$L/owner" 2>/dev/null))"; exit 1; }
    rm -rf "$L"; echo "released by $o" ;;
  status) if [ -d "$L" ]; then s=$(cat "$L/since"); age=$(( $(date +%s) - $(date -d "$s" +%s) ))
      echo "held by $(cat "$L/owner") since $s (${age}s)$( (( age > 14400 )) && echo ' STALE?')"; else echo free; fi
    n=$(ls "$W" 2>/dev/null | wc -l); [ "$n" -gt 0 ] && echo "waiting: $(ls "$W" | sort | cut -d. -f2 | tr "\n" " ")"; true ;;
esac
