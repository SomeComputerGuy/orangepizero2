#!/usr/bin/env bash
# Build stonking-orangepizero2-rebased = origin/main + merges of pr/* (integration order).
set -u
W=/home/aruni/orangepizero2/wt-prprep-rebase; A=/home/aruni/orangepizero2/armbian-build; S=patch/kernel/archive/sunxi-7.3/series.conf
G="git -c core.hooksPath=/nonexistent"; NEW=stonking-orangepizero2-rebased
cd "$W"; [[ -z ${RESUME:-} ]] && git rev-parse -q --verify "refs/heads/$NEW" >/dev/null && { echo "$NEW exists"; exit 1; }
[[ -n ${RESUME:-} ]] || git checkout -q -b "$NEW" origin/main
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
	if [[ -n ${RESUME:-} ]] && git merge-base --is-ancestor "pr/$b" HEAD; then echo "already $b"; continue; fi
	msg="Merge branch 'pr/$b' into $NEW"
	if $G merge -q --no-ff --no-edit -m "$msg" "pr/$b" > /tmp/prprep-merge.log 2>&1; then echo "merged $b"; continue; fi
	u=$(git diff --name-only --diff-filter=U)
	if [[ $u != "$S" ]]; then echo "STOP $b: conflicts in $u"; exit 2; fi
	git checkout -q --ours -- "$S"
	for c in $(git rev-list --reverse "HEAD..pr/$b" -- "$S"); do python3 -I /home/aruni/orangepizero2/kernel-check/prprep/series-merge.py "$A" "$c" "$S"; done
	git add "$S"; $G commit -q --no-edit -m "$msg" && echo "merged $b (series.conf resolved)"
done
