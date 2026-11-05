#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# One owner on the board at a time (parallel agents share the single Orange Pi Zero2).
#   harness/board-lock.sh acquire <owner> [max-wait-s]   blocks until free (default: wait forever), then holds it
#   harness/board-lock.sh release <owner>                frees it (only the owner may)
#   harness/board-lock.sh status
# Hold it for one test session (aim <= 60 min), leave the board booted on the image kernel (or the trial-kernel
# fallback armed) before release. A lock older than 4 h is reported as stale but never broken automatically.
set -uo pipefail
L=$(cd "$(dirname "$0")" && pwd)/queue/board.lock
mkdir -p "$(dirname "$L")"
case "${1:-status}" in
  acquire) o=${2:?owner}; max=${3:-0}; t0=$(date +%s)
    until mkdir "$L" 2>/dev/null; do
      if [ "$(cat "$L/owner" 2>/dev/null)" = "$o" ]; then echo "already held by $o"; exit 0; fi
      (( max > 0 && $(date +%s) - t0 > max )) && { echo "busy: $(cat "$L/owner" "$L/since" 2>/dev/null | tr '\n' ' ')"; exit 1; }
      sleep 30; done
    echo "$o" > "$L/owner"; date '+%F %T' > "$L/since"; echo "acquired by $o" ;;
  release) o=${2:?owner}; [ "$(cat "$L/owner" 2>/dev/null)" = "$o" ] || { echo "not held by $o (owner: $(cat "$L/owner" 2>/dev/null))"; exit 1; }
    rm -rf "$L"; echo "released by $o" ;;
  status) if [ -d "$L" ]; then s=$(cat "$L/since"); age=$(( $(date +%s) - $(date -d "$s" +%s) ))
      echo "held by $(cat "$L/owner") since $s (${age}s)$( (( age > 14400 )) && echo ' STALE?')"; else echo free; fi ;;
esac
