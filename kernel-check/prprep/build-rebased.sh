#!/usr/bin/env bash
# Build stonking-orangepizero2-rebased = origin/main + merges of pr/* (integration order).
set -u
W=/home/aruni/orangepizero2/wt-prprep-rebase; A=/home/aruni/orangepizero2/armbian-build; S=patch/kernel/archive/sunxi-7.3/series.conf
G="git -c core.hooksPath=/nonexistent"; NEW=stonking-orangepizero2-rebased
cd "$W"; git rev-parse -q --verify "refs/heads/$NEW" >/dev/null && { echo "$NEW exists"; exit 1; }
git checkout -q -b "$NEW" origin/main
for b in feat/distro-ubuntu-stonking fix/uboot-sunxi64-host-tools-openssl4 fix/apt-utils-upstream-pkg-fallback \
	fix/rootfs-armbian-gpg-symlink-on-host fix/rootfs-dbus-launch-helper-guard fix/sunxi-dwmac-sun8i-upstream-reset \
	fix/sunxi-cedrus-h616-upstream feat/sunxi-zero2-gpu-opp feat/sunxi-zero2-usb-otg-host-overlay fix/sunxi-pm-s2idle-dpm-backports \
	fix/uwe5622-bump-driver-pin fix/uwe5622-services fix/uwe5622-powersave fix/uwe5622-bt-wake fix/uwe5622-regdomain \
	fix/sunxi-zero2-regulators fix/sunxi-drm-blend-mode fix/sunxi-h616-thermal-trips fix/bsp-systemd-boot-warnings \
	fix/sunxi-zero2-mmc-aliases fix/uboot-h616-spl-rsb fix/uboot-zero2-env-nowhere feat/uboot-zero2-spi-nor feat/uboot-zero2-usb-boot \
	fix/sunxi64-bootscript-boot-source feat/sunxi-h616-tv-encoder fix/sunxi-h616-gpu-cooling fix/uboot-sunxi-ce-rng-kaslr \
	feat/uwe5622-bt-no-blob feat/atf-h616-psci-cpu-suspend feat/atf-h616-system-suspend feat/sunxi-h616-cpuidle-dt \
	fix/sunxi-h616-orangepi-zero2-emac-rxid fix/uwe5622-quiet-expected-log feat/sunxi-h616-vdec-spec fix/sunxi-h616-vdd-sys-floor \
	fix/uwe5622-5ghz-ap fix/sunxi-h616-pwm-uart0-pins; do
	msg="Merge branch 'pr/$b' into $NEW"
	if $G merge -q --no-ff --no-edit -m "$msg" "pr/$b" > /tmp/prprep-merge.log 2>&1; then echo "merged $b"; continue; fi
	u=$(git diff --name-only --diff-filter=U)
	for f in $u; do
		[[ $f == "$S" ]] && continue
		# take theirs only if ours' exact content occurs in theirs' history (theirs is a content descendant)
		ok=0; ho=$(git rev-parse "HEAD:$f")
		for c in $(git rev-list "HEAD..pr/$b"); do [[ $(git rev-parse -q "$c:$f" 2>/dev/null) == "$ho" ]] && { ok=1; break; }; done
		if (( ok )); then git checkout -q --theirs -- "$f"; git add "$f"; echo "  $f: took theirs (descendant of ours)"; else echo "STOP $b: conflict in $f"; exit 2; fi
	done
	if ! git diff --name-only --diff-filter=U | grep -qx "$S"; then $G commit -q --no-edit -m "$msg"; echo "merged $b (resolved)"; continue; fi
	git checkout -q --ours -- "$S"
	for c in $(git rev-list --reverse "HEAD..pr/$b" -- "$S"); do python3 -I /home/aruni/orangepizero2/kernel-check/prprep/series-merge.py "$A" "$c" "$S" stonking-orangepizero2; done
	git add "$S"; $G commit -q --no-edit -m "$msg" && echo "merged $b (series.conf resolved)"
done
