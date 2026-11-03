#!/bin/bash
# SPDX-License-Identifier: MIT
# Host side: compare the board outputs fetched back from run.sh.
#   check.sh VECTORDIR [FMT]
d=$1
f=${2:-nv12}
here=$(cd "$(dirname "$0")" && pwd)
o=$d/out-$f
while read -r n w h r e; do
	rc=$(awk -v n="$n" '$1 == n { print $3 }' "$o/results.txt")
	case $e in
	ok)
		if [ "$rc" != 0 ]; then echo "FAIL $n: rc $rc"; continue; fi
		echo "== $n ($r)"
		python3 -I "$here/compare.py" "$w" "$h" "$o/$n.yuv" "$f" "$d/$n.ref.yuv" "$r"
		;;
	reject) [ "$rc" != 0 ] && echo "ok   $n rejected" || echo "FAIL $n: decoded, expected reject";;
	error)  [ "$rc" = 124 ] && echo "FAIL $n: hang" || echo "ok   $n completed (rc $rc)";;
	esac
done < "$d/cases.txt"
