#!/usr/bin/env bash
# Apply patch/u-boot/v2026.10-sunxi64 (+board_orangepizero2) to v2026.10 and patch/atf/atf-sunxi64 (+board) to
# lts-v2.14.11 from an armbian-build rev, Armbian order (LC_ALL=C basename sort, patch --batch -p1 -N).
set -uo pipefail
REV=$1; A=/home/aruni/orangepizero2/armbian-build; B=orangepizero2
T=$(mktemp -d /tmp/fwcheck.XXXX); git -C "$A" archive "$REV" patch/u-boot/v2026.10-sunxi64 patch/atf/atf-sunxi64 | tar -x -C "$T"
run() { # srcdir patchroot label
	local src=$1 pr=$2 lab=$3 ok=0 bad=0 fails=""
	git -C "$src" checkout -q -f HEAD && git -C "$src" clean -qfdx
	while read -r name; do
		for d in "$pr/board_$B" "$pr"; do p="$d/$name"; [[ -f $p ]] || continue
			lsdiff -s --strip=1 "$p" 2>/dev/null | awk '/^\+/ {print $2}' | (cd "$src" && xargs -r rm -f)
			if patch -d "$src" --batch -p1 -N --quiet --reject-file=- -i "$p" >/dev/null 2>&1; then ok=$((ok+1)); else bad=$((bad+1)); fails="$fails $name"; fi; break; done
	done < <({ ls "$pr"/*.patch "$pr/board_$B"/*.patch 2>/dev/null || true; } | xargs -rn1 basename | LC_ALL=C sort -u)
	echo "$REV $lab: applied $ok failed $bad${fails:+ ->$fails}"
}
run /home/aruni/orangepizero2/wt-prprep-ubtest/u-boot "$T/patch/u-boot/v2026.10-sunxi64" u-boot
run /home/aruni/orangepizero2/wt-prprep-ubtest/tf-a "$T/patch/atf/atf-sunxi64" atf
rm -rf "$T"
