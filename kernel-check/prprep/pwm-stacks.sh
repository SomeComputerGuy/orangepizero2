#!/usr/bin/env bash
# fdtoverlay matrix for H616 PWM overlays on the Zero2 DTB. $1 = linux tree with built dtbs/overlays
set -u
L=$1; D=$L/arch/arm64/boot/dts/allwinner; O=$D/overlay; T=$(mktemp -d)
base=$D/sun50i-h616-orangepi-zero2.dtb
chk() { # name overlays...
	local name=$1; shift; local args=()
	for o in "$@"; do args+=("$O/sun50i-h616-$o.dtbo"); done
	if ! "$L/scripts/dtc/fdtoverlay" -i "$base" -o "$T/m.dtb" "${args[@]}" 2> "$T/err"; then
		echo "== $name: FDTOVERLAY FAIL: $(tr '\n' ' ' < "$T/err")"; return
	fi
	"$L/scripts/dtc/dtc" -I dtb -O dts -q "$T/m.dtb" > "$T/m.dts"
	local st; st=$(for n in pwm@300a000 serial@5000000 ethernet@5020000; do
		s=$(awk -v n="$n" '$1==n||$2==n{f=1} f&&/status = /{print $3;exit} f&&/^\t\t};/{print "(none)";exit}' "$T/m.dts" | tr -d '";'); printf '%s=%s ' "${n%%@*}" "$s"; done)
	echo "== $name: applied; $st"
	python3 -I "$(dirname "$0")/pinconf.py" "$T/m.dts" PH0 PH1 PH2 PH3 PI11 PI12 PI13 PI14 | grep -E 'claim|CONFLICT|conflicts' | sed 's/^/   /'
}
for o in pwm1-ph3 pwm2-ph2 pwm3-ph0 pwm4-ph1 pwm1-pi11 pwm2-pi12 pwm3-pi13 pwm4-pi14; do chk "$o" "$o"; done
chk "PH header pair (pwm1-ph3 pwm2-ph2)" pwm1-ph3 pwm2-ph2
chk "PH all four" pwm1-ph3 pwm2-ph2 pwm3-ph0 pwm4-ph1
chk "PI all four" pwm1-pi11 pwm2-pi12 pwm3-pi13 pwm4-pi14
chk "mixed pwm1-ph3 pwm2-pi12" pwm1-ph3 pwm2-pi12
chk "same channel both pins pwm1-ph3 pwm1-pi11" pwm1-ph3 pwm1-pi11
chk "pwm + uart5 (PH2/PH3)" pwm1-ph3 pwm2-ph2 uart5
chk "pwm + i2c2-ph" pwm1-ph3 i2c2-ph
chk "pwm + i2c3-ph + spidev1_0" pwm1-ph3 pwm2-ph2 i2c3-ph spidev1_0
chk "pwm + expansion + usb-otg-host + ir" pwm1-ph3 pwm2-ph2 orangepi-zero2-expansion usb-otg-host ir
rm -rf "$T"
