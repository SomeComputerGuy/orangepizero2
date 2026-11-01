#!/usr/bin/env bash
# Stage a freshly built kernel for netbooting the Orange Pi Zero2 (needs netboot-setup.sh once).
# Copies Image + the Zero2 DTB (+ optional raw initrd, + optional overlays) into the TFTP
# root and writes the U-Boot extlinux/pxe config pxelinux.cfg/default-arm-sunxi.
#
#   KERNEL_TREE  built kernel tree (default: kernel-check/work/linux-7.3.1, output of build-kernel.sh)
#   ROOTMODE     sd     - rootfs from the SD card (/dev/mmcblk0p1); no initrd needed: the Armbian
#                         sunxi64 kernel has MMC_SUNXI/EXT4 built in. Default, best for kernel tests.
#                initrd - also load $INITRD (a RAW initramfs, e.g. the board's /boot/initrd.img-<ver>,
#                         NOT the legacy-wrapped uInitrd) and still mount the SD rootfs from it.
#                nfs    - root over NFS from $NFS_ROOT (needs an initrd with the dwmac_sun8i/realtek/
#                         nfs modules: in linux-sunxi64-edge.config DWMAC_SUN8I=m and NFS_FS=m, so
#                         pure kernel NFS root is impossible without a config change; requires
#                         INITRD= built by initramfs-tools with MODULES=most and nfs-kernel-server on
#                         the host exporting $NFS_ROOT to 10.56.0.0/24).
#   INITRD       path to a raw initramfs (optional for sd, required for initrd/nfs)
#   OVERLAYS     space separated .dtbo paths to copy and apply via fdtoverlays (optional)
#   EXTRAARGS    appended to the kernel command line
set -euo pipefail

TFTP_ROOT="${TFTP_ROOT:-/srv/tftp/opiz2}"
KERNEL_TREE="${KERNEL_TREE:-/home/aruni/orangepizero2/kernel-check/work/linux-7.3.1}"
ROOTMODE="${ROOTMODE:-sd}"
INITRD="${INITRD:-}"
OVERLAYS="${OVERLAYS:-}"
EXTRAARGS="${EXTRAARGS:-}"
HOST_IP="${HOST_IP:-10.56.0.1}"
NFS_ROOT="${NFS_ROOT:-/srv/nfs/opiz2}"
DTB_NAME=sun50i-h616-orangepi-zero2.dtb
CFG="$TFTP_ROOT/pxelinux.cfg/default-arm-sunxi"

IMAGE="$KERNEL_TREE/arch/arm64/boot/Image"
DTB="$KERNEL_TREE/arch/arm64/boot/dts/allwinner/$DTB_NAME"
[[ -f $IMAGE && -f $DTB ]] || { echo "missing $IMAGE or $DTB (run kernel-check/build-kernel.sh first)"; exit 1; }
[[ -d $TFTP_ROOT/pxelinux.cfg ]] || { echo "$TFTP_ROOT missing: run harness/netboot-setup.sh first"; exit 1; }

install -m 0644 "$IMAGE" "$TFTP_ROOT/Image"
install -m 0644 "$DTB" "$TFTP_ROOT/$DTB_NAME"
kver="$(strings "$IMAGE" 2> /dev/null | grep -m1 -oE 'Linux version [^ ]+' || true)"

initrd_line=""
if [[ -n $INITRD ]]; then
	[[ -f $INITRD ]] || { echo "INITRD=$INITRD not found"; exit 1; }
	# U-Boot's pxe passes the initrd as <addr>:<size> to booti, i.e. raw: refuse a legacy uImage wrapper.
	if [[ $(od -An -tx1 -N4 "$INITRD" | tr -d ' ') == 27051956 ]]; then
		echo "$INITRD is a legacy U-Boot image (uInitrd); use the raw initrd.img-<ver> instead"; exit 1
	fi
	install -m 0644 "$INITRD" "$TFTP_ROOT/initrd.img"
	initrd_line="  initrd initrd.img"
elif [[ $ROOTMODE != sd ]]; then
	echo "ROOTMODE=$ROOTMODE needs INITRD=<raw initramfs>"; exit 1
fi

overlay_line=""
if [[ -n $OVERLAYS ]]; then
	mkdir -p "$TFTP_ROOT/overlay"
	names=()
	for o in $OVERLAYS; do install -m 0644 "$o" "$TFTP_ROOT/overlay/"; names+=("overlay/$(basename "$o")"); done
	overlay_line="  fdtoverlays ${names[*]}"
fi

common="console=ttyS0,115200 console=tty1 consoleblank=0 loglevel=7 cgroup_enable=memory"
case $ROOTMODE in
	sd | initrd) rootargs="root=/dev/mmcblk0p1 rootwait rootfstype=ext4" ;;
	nfs) rootargs="root=/dev/nfs nfsroot=$HOST_IP:$NFS_ROOT,vers=3,tcp ip=dhcp rw boot=nfs" ;;
	*) echo "unknown ROOTMODE=$ROOTMODE"; exit 1 ;;
esac

cat > "$CFG" <<- EOF
	# written by harness/netboot-stage.sh $(date -u +%FT%TZ) -- $kver
	default netboot
	timeout 10
	label netboot
	  menu label Zero2 netboot ($ROOTMODE) $kver
	  kernel Image
	  fdt $DTB_NAME
	$initrd_line
	$overlay_line
	  append $rootargs $common $EXTRAARGS
EOF
sed -i '/^$/d' "$CFG"
echo "staged into $TFTP_ROOT:"; ls -l "$TFTP_ROOT"; echo "--- $CFG"; cat "$CFG"
