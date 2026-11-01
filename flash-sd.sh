#!/usr/bin/env bash
# Flash the Orange Pi Zero2 image to an SD card.
# Usage: sudo ./flash-sd.sh /dev/sdX      (run without a device to list candidates)
set -euo pipefail

IMG_DIR=/home/aruni/orangepizero2/armbian-build/output/images
IMG_XZ=$(ls -t "$IMG_DIR"/Armbian-*Orangepizero2*.img.xz | head -1)
DEV="${1:-}"

if [[ -z $DEV ]]; then
	echo "Removable/USB block devices:"
	lsblk -d -o NAME,SIZE,MODEL,TRAN,RM,MOUNTPOINTS | awk 'NR==1 || $4=="usb" || $5=="1"'
	echo
	echo "Usage: sudo $0 /dev/sdX"
	exit 1
fi

[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
[[ -b $DEV ]] || { echo "$DEV is not a block device."; exit 1; }

# Refuse anything that is not a whole disk, or that holds a mounted system path.
[[ $(lsblk -dno TYPE "$DEV") == disk ]] || { echo "$DEV is a partition, give the whole disk."; exit 1; }
ROOTDEV=$(lsblk -no PKNAME "$(findmnt -no SOURCE /)" 2>/dev/null || true)
[[ -n $ROOTDEV && $DEV == /dev/$ROOTDEV ]] && { echo "$DEV holds the root filesystem. Refusing."; exit 1; }
if lsblk -no MOUNTPOINTS "$DEV" | grep -qE '^/(boot|home|usr|var)?$'; then
	echo "$DEV has system mounts. Refusing."; exit 1
fi
SIZE_GB=$(( $(blockdev --getsize64 "$DEV") / 1000000000 ))
(( SIZE_GB >= 4 )) || { echo "$DEV is ${SIZE_GB}GB; need at least 4GB."; exit 1; }
(( SIZE_GB <= 512 )) || { echo "$DEV is ${SIZE_GB}GB; that does not look like an SD card. Refusing."; exit 1; }

echo "Image : $IMG_XZ"
echo "Target: $DEV (${SIZE_GB}GB $(lsblk -dno MODEL "$DEV"))"
lsblk "$DEV"
echo
read -rp "This ERASES $DEV. Type 'yes' to continue: " ans
[[ $ans == yes ]] || { echo "Aborted."; exit 1; }

echo "Verifying image checksum..."
(cd "$IMG_DIR" && sha256sum -c "$(basename "$IMG_XZ").sha")

echo "Unmounting any mounted partitions..."
for p in $(lsblk -lno PATH "$DEV" | tail -n +2); do umount "$p" 2>/dev/null || true; done

echo "Writing..."
xzcat "$IMG_XZ" | dd of="$DEV" bs=4M status=progress conv=fsync
sync

echo "Verifying written data..."
IMG_BYTES=$(xz --robot --list "$IMG_XZ" | awk '$1=="totals"{print $5}')
IMG_SUM=$(xzcat "$IMG_XZ" | sha256sum | cut -d' ' -f1)
DEV_SUM=$(head -c "$IMG_BYTES" "$DEV" | sha256sum | cut -d' ' -f1)
if [[ $IMG_SUM == "$DEV_SUM" ]]; then
	echo "OK: card matches image. Eject it and boot the Orange Pi."
else
	echo "MISMATCH: card does not match image. Try another card or reader."; exit 1
fi
