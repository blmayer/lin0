#!/bin/sh
# Build a flashable SD image for Raspberry Pi Zero / Zero W from rootfs-rpizero.tar.xz
#
# Layout (classic RPi):
#   p1  FAT32  ~64 MiB   /boot (firmware + kernel.img + DTB + config.txt)
#   p2  ext4   rest      lin0 rootfs (init=/bin/init)
#
# Usage (from repo root, after make rpizero):
#   ./scripts/mkimg-rpizero.sh
#   sudo dd if=lin0-rpizero.img of=/dev/sdX bs=4M status=progress conv=fsync
#
# Env: IMG_SIZE_MB (default 256), BOOT_SIZE_MB (default 64), ROOTFS_TAR

set -e

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

IMG_SIZE_MB="${IMG_SIZE_MB:-256}"
BOOT_SIZE_MB="${BOOT_SIZE_MB:-64}"
ROOTFS_TAR="${ROOTFS_TAR:-$REPO_ROOT/rootfs-rpizero.tar.xz}"
OUT_IMG="${OUT_IMG:-$REPO_ROOT/lin0-rpizero.img}"
WORK="${WORK:-$REPO_ROOT/build/rpizero-img}"

if [ ! -f "$ROOTFS_TAR" ]; then
	echo "error: missing $ROOTFS_TAR — run: make rpizero" >&2
	exit 1
fi

if ! command -v sfdisk >/dev/null 2>&1; then
	echo "error: need sfdisk (util-linux)" >&2
	exit 1
fi
if ! command -v mkfs.vfat >/dev/null 2>&1 && ! command -v mkfs.fat >/dev/null 2>&1; then
	echo "error: need mkfs.vfat / mkfs.fat" >&2
	exit 1
fi
if ! command -v mkfs.ext4 >/dev/null 2>&1; then
	echo "error: need mkfs.ext4" >&2
	exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK/boot" "$WORK/root"

echo "==> extracting $ROOTFS_TAR"
tar xf "$ROOTFS_TAR" -C "$WORK/root"

# Split /boot out for FAT partition (RPi firmware expects FAT)
if [ -d "$WORK/root/boot" ]; then
	cp -a "$WORK/root/boot/." "$WORK/boot/"
	rm -rf "$WORK/root/boot"
	mkdir -p "$WORK/root/boot"
fi

if [ ! -f "$WORK/boot/kernel.img" ]; then
	echo "warning: no kernel.img in boot/ — image may not boot (was linux built for arm?)" >&2
fi

IMG_BYTES=$((IMG_SIZE_MB * 1024 * 1024))
BOOT_BYTES=$((BOOT_SIZE_MB * 1024 * 1024))
# sectors (512)
BOOT_SECTS=$((BOOT_BYTES / 512))
# align boot start at 2048 sectors (1 MiB)
START=2048
BOOT_END=$((START + BOOT_SECTS - 1))
ROOT_START=$((BOOT_END + 1))

echo "==> creating sparse image ${IMG_SIZE_MB} MiB -> $OUT_IMG"
rm -f "$OUT_IMG"
dd if=/dev/zero of="$OUT_IMG" bs=1M count=0 seek="$IMG_SIZE_MB" status=none

echo "==> partitioning (p1 FAT ${BOOT_SIZE_MB}M, p2 ext4)"
sfdisk "$OUT_IMG" << EOF
label: dos
unit: sectors

${OUT_IMG}1 : start=${START}, size=${BOOT_SECTS}, type=c, bootable
${OUT_IMG}2 : start=${ROOT_START}, type=83
EOF

# loop setup
LO=$(sudo losetup -f --show -P "$OUT_IMG")
cleanup() {
	sync
	sudo umount "$WORK/mnt-boot" 2>/dev/null || true
	sudo umount "$WORK/mnt-root" 2>/dev/null || true
	sudo losetup -d "$LO" 2>/dev/null || true
}
trap cleanup EXIT

# wait for partitions
for i in 1 2 3 4 5; do
	[ -b "${LO}p1" ] && [ -b "${LO}p2" ] && break
	sleep 0.5
done

echo "==> formatting"
if command -v mkfs.vfat >/dev/null 2>&1; then
	sudo mkfs.vfat -F 32 -n LIN0BOOT "${LO}p1"
else
	sudo mkfs.fat -F 32 -n LIN0BOOT "${LO}p1"
fi
sudo mkfs.ext4 -F -L lin0root "${LO}p2"

mkdir -p "$WORK/mnt-boot" "$WORK/mnt-root"
sudo mount "${LO}p1" "$WORK/mnt-boot"
sudo mount "${LO}p2" "$WORK/mnt-root"

echo "==> copying boot + rootfs"
sudo cp -a "$WORK/boot/." "$WORK/mnt-boot/"
sudo cp -a "$WORK/root/." "$WORK/mnt-root/"
sudo mkdir -p "$WORK/mnt-root/boot"
sync

echo ""
echo "Image ready: $OUT_IMG (${IMG_SIZE_MB} MiB)"
echo "  dd:  sudo dd if=$OUT_IMG of=/dev/sdX bs=4M status=progress conv=fsync"
echo "  login: root / lin0 (serial 115200 on UART, or tty0)"
