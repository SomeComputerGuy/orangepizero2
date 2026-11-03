#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Hands-off reflash of the Orange Pi Zero2 SD card over netboot (needs harness/netboot-setup.sh once).
#
#   harness/reflash.sh --dry-run        everything except the reboot/serial/write steps; prints the plan
#   harness/reflash.sh                  real run: REWRITES THE BOARD'S SD CARD with the newest image
#   options: --image X.img.xz  --sectors N (SD size, default: read over ssh)  --no-post (stop after flashing)
#            --power-cycle (allowed only when ssh and serial are both dead, per the harness rules)
#
# Steps: build flasher (Image + DTB + BusyBox initramfs) -> manifest (uncompressed sha256/size) -> start
# HTTP server on 10.56.0.1:8080 -> stage TFTP (pxelinux.cfg backed up) -> reboot board -> interrupt
# U-Boot on /dev/ttyOPIZ2, dhcp + pxe boot -> restore pxelinux.cfg as soon as the kernel starts (a later
# reboot can never re-enter the flasher) -> flasher writes /dev/mmcblk0, verifies sha256, reboots ->
# first-login wizard over serial -> harness ssh key, timezone Etc/UTC, known_hosts reset -> verify-board.sh.
set -euo pipefail
HARNESS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(dirname "$HARNESS")"
TFTP_ROOT="${TFTP_ROOT:-/srv/tftp/opiz2}"
HOST_IP="${HOST_IP:-10.56.0.1}"
PORT="${PORT:-8080}"
BOARD_IP=10.56.0.107
CFG="$TFTP_ROOT/pxelinux.cfg/default-arm-sunxi"
BACKUP="$CFG.reflash-backup"
WORK="$TOP/kernel-check/work-flasher"
OUTD="$WORK/out"
DTB_NAME=sun50i-h616-orangepi-zero2.dtb
DRY=0 IMAGE="" SECTORS="" POST=1 POWERCYCLE=0
while [[ $# -gt 0 ]]; do
	case $1 in
		--dry-run) DRY=1 ;;
		--image) IMAGE=$2; shift ;;
		--sectors) SECTORS=$2; shift ;;
		--no-post) POST=0 ;;
		--power-cycle) POWERCYCLE=1 ;;
		*) echo "unknown option $1"; exit 2 ;;
	esac
	shift
done
step() { printf '\n== %s\n' "$*"; }
would() { echo "[dry-run] would: $*"; }
SSH() { "$HARNESS/ssh.sh" "$@"; }
SRV=""
cleanup() {
	[[ -n $SRV ]] && kill "$SRV" 2> /dev/null || true
	restore_cfg
}
restore_cfg() {
	if [[ -f $BACKUP ]]; then mv -f "$BACKUP" "$CFG"; echo "restored $CFG"
	elif [[ -f $CFG.reflash-none ]]; then rm -f "$CFG" "$CFG.reflash-none"; echo "removed flasher $CFG"; fi
}

step "0. preconditions"
[[ -d $TFTP_ROOT/pxelinux.cfg && -w $TFTP_ROOT ]] || { echo "$TFTP_ROOT not set up/writable: run harness/netboot-setup.sh"; exit 1; }
[[ $(readlink -f /dev/ttyOPIZ2) == /dev/ttyUSB1 ]] || { echo "/dev/ttyOPIZ2 must point at ttyUSB1 (our CP2102), is $(readlink -f /dev/ttyOPIZ2)"; exit 1; }
pgrep -f 'scripts/serial-log.py$' > /dev/null || pgrep -fx 'python3 -I scripts/serial-log.py' > /dev/null ||
	{ echo "scripts/serial-log.py is not running (harness/serial.log would not update)"; exit 1; }
[[ -f $TFTP_ROOT/pxelinux.cfg/default-arm-sunxi.reflash-backup || -f $CFG.reflash-none ]] &&
	{ echo "a previous reflash left $BACKUP/.reflash-none: check and remove it first"; exit 1; }
echo "tftp root $TFTP_ROOT ok, console /dev/ttyOPIZ2 -> ttyUSB1, serial logger running"

step "1. build the flasher"
"$HARNESS/flasher/build-flasher.sh" | tail -4

step "2. image manifest"
IMGARG=(); [[ -n $IMAGE ]] && IMGARG=(--image "$IMAGE")
python3 -I "$HARNESS/flasher/serve-image.py" "${IMGARG[@]}" --manifest-only | tee "$WORK/manifest"
SIZE=$(sed -n 's/^SIZE=//p' "$WORK/manifest")

step "3. SD card size"
if [[ -z $SECTORS ]]; then
	SECTORS=$(SSH cat /sys/block/mmcblk0/size 2> /dev/null || true)
	[[ $SECTORS =~ ^[0-9]+$ ]] || { echo "board not reachable over ssh: pass --sectors N (sectors of the SD card)"; exit 1; }
fi
echo "SD card: $SECTORS sectors ($((SECTORS / 2048)) MiB); image $((SIZE / 1048576)) MiB"
[[ $((SECTORS * 512)) -ge $SIZE ]] || { echo "image larger than the SD card"; exit 1; }

step "4. stage TFTP ($TFTP_ROOT/flasher/, $CFG)"
APPEND="console=ttyS0,115200 loglevel=4 rdinit=/init flasher.url=http://$HOST_IP:$PORT flasher.sectors=$SECTORS"
read -r -d '' PXE <<- EOM || true
	# written by harness/reflash.sh $(date -u +%FT%TZ): netboot flasher (rewrites the SD card)
	default flasher
	timeout 10
	label flasher
	  menu label Zero2 SD flasher
	  kernel flasher/Image
	  fdt flasher/$DTB_NAME
	  initrd flasher/initrd.img
	  append $APPEND
EOM
if [[ $DRY == 1 ]]; then
	mkdir -p "$TFTP_ROOT/flasher.dryrun"
	install -m 0644 "$OUTD/Image" "$OUTD/$DTB_NAME" "$OUTD/initrd.img" "$TFTP_ROOT/flasher.dryrun/"
	for f in Image "$DTB_NAME" initrd.img; do
		if curl -s --connect-timeout 3 "tftp://$HOST_IP/flasher.dryrun/$f" | cmp -s - "$OUTD/$f"; then echo "tftp fetch flasher.dryrun/$f: identical"
		else echo "tftp fetch flasher.dryrun/$f: FAILED (is dnsmasq TFTP up?)"; fi
	done
	rm -rf "$TFTP_ROOT/flasher.dryrun"
	would "back up $CFG -> $BACKUP and write:"; echo "$PXE" | sed 's/^/    /'
else
	mkdir -p "$TFTP_ROOT/flasher"
	install -m 0644 "$OUTD/Image" "$OUTD/$DTB_NAME" "$OUTD/initrd.img" "$TFTP_ROOT/flasher/"
	if [[ -f $CFG ]]; then cp -p "$CFG" "$BACKUP"; else : > "$CFG.reflash-none"; fi
	trap cleanup EXIT
	echo "$PXE" > "$CFG"
fi

step "5. HTTP server http://$HOST_IP:$PORT/"
if [[ $DRY == 1 ]]; then
	TP=$((20000 + RANDOM % 20000))
	python3 -I "$HARNESS/flasher/serve-image.py" "${IMGARG[@]}" --bind 127.0.0.1 --port $TP --status-file "$WORK/flasher-status.dryrun" 2> "$WORK/serve-dryrun.log" &
	SRV=$!; trap cleanup EXIT; sleep 1
	curl -s "http://127.0.0.1:$TP/manifest" | cmp -s - "$WORK/manifest" && echo "manifest served ok (test port $TP)" || echo "manifest NOT served"
	magic=$(curl -s "http://127.0.0.1:$TP/$(sed -n 's/^IMAGE=//p' "$WORK/manifest")" 2> /dev/null | head -c 6 | od -An -tx1 | tr -d ' \n' || true)
	[[ $magic == fd377a585a00 ]] && echo "image served ok (xz magic)" || echo "image NOT served ($magic)"
	kill $SRV; SRV=""
	would "serve on $HOST_IP:$PORT for the board"
else
	python3 -I "$HARNESS/flasher/serve-image.py" "${IMGARG[@]}" --bind "$HOST_IP" --port "$PORT" 2> "$WORK/serve.log" &
	SRV=$!; sleep 1
	curl -s "http://$HOST_IP:$PORT/manifest" | cmp -s - "$WORK/manifest" || { echo "HTTP server not answering on $HOST_IP:$PORT"; exit 1; }
fi

step "6. reboot the board into U-Boot"
if [[ $DRY == 1 ]]; then
	would "ssh root@$BOARD_IP systemctl reboot (or, with --power-cycle and ssh+serial dead: scripts/board-power.py cycle)"
	python3 -I "$HARNESS/serialcon.py" uboot-pxe --dry-run --server "$HOST_IP"
else
	if SSH true 2> /dev/null; then
		SSH 'sync; systemctl reboot' || true
	elif [[ $POWERCYCLE == 1 ]]; then
		python3 -I "$TOP/scripts/board-power.py" cycle 5
	else
		echo "board not reachable over ssh; reboot it by hand (or --power-cycle if serial is dead too)"
	fi
	python3 -I "$HARNESS/serialcon.py" uboot-pxe --timeout 240 --server "$HOST_IP" || { echo "U-Boot pxe step failed"; exit 1; }
	restore_cfg # the flasher kernel is running: a later reboot must not come back here
fi

step "7. flasher: write + verify"
if [[ $DRY == 1 ]]; then
	would "wait for 'FLASHER: RESULT OK' on the console (timeout 30 min); on FAIL stop with the board in the flasher shell"
else
	python3 -I "$HARNESS/serialcon.py" wait-flasher --timeout 1800 || { echo "flasher failed: board left in the flasher shell (SD may be partly written; U-Boot on SPI NOR is untouched, just re-run)"; exit 1; }
	kill "$SRV" 2> /dev/null; SRV=""
fi

[[ $POST == 1 ]] || { echo "done (--no-post)"; exit 0; }

step "8. first boot of the new image: first-login wizard"
if [[ $DRY == 1 ]]; then python3 -I "$HARNESS/serialcon.py" firstlogin --dry-run
else python3 -I "$HARNESS/serialcon.py" firstlogin --timeout 900 || { echo "first-login automation failed"; exit 1; }; fi

step "9. harness ssh key, timezone, known_hosts"
PUB=$(cat "$HARNESS/id_ed25519.pub")
[[ $PUB =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+(\ [^\'\"]*)?$ ]] || { echo "unexpected public key format"; exit 1; }
SETUP="install -d -m 700 /root/.ssh && touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && (grep -qF '${PUB%% *} ${PUB#* }' /root/.ssh/authorized_keys || echo '$PUB' >> /root/.ssh/authorized_keys) && timedatectl set-timezone Etc/UTC"
if [[ $DRY == 1 ]]; then
	would "run on the serial root shell: ${SETUP:0:120}..."
	would "ssh-keygen -R $BOARD_IP -f $HARNESS/known_hosts"
else
	python3 -I "$HARNESS/serialcon.py" shell "$SETUP" --timeout 60 || { echo "key/timezone setup failed"; exit 1; }
	ssh-keygen -R "$BOARD_IP" -f "$HARNESS/known_hosts" > /dev/null 2>&1 || true
	for i in $(seq 1 30); do SSH true 2> /dev/null && break; sleep 5; done
	SSH 'echo ssh ok: $(uname -r), tz $(cat /etc/timezone 2>/dev/null || timedatectl show -p Timezone --value)'
fi

step "10. verify-board.sh"
if [[ $DRY == 1 ]]; then would "harness/verify-board.sh"; echo; echo "dry run complete"
else "$HARNESS/verify-board.sh"; fi
