#!/bin/bash
# run-sim.sh + kbdecode, then print the fragment render-target formats: sim-rt.sh <workdir> [KBFAKE_SET]
H=$(cd "$(dirname "$0")/.." && pwd)
W=$1
"$H/hostsim/run-sim.sh" "$@"
"$H/kbdecode" "$W/kbtrace.bin" "$W/dec" > "$W/kbdecode.txt" 2>&1
printf '%s SET[%s] %s | RT: %s\n' "$(basename "$W")" "${2:-}" "$(tail -1 "$W/run.log")" \
	"$(grep -h 'Color Render Target 0:' "$W"/dec/submit-*.txt | sed 's/ Color Render Target 0://; s/^ *//' | sort | uniq -c | tr -s ' \n' ' ')"
