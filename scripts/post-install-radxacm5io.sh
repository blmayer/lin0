#!/bin/sh
# Radxa CM5 + IO post-install: boot files aligned with official Radxa layout.
# Official boots: sysboot mmc 0:3 /boot/extlinux/extlinux.conf on ext4 root.
# lin0 has 2 partitions: p1 FAT (optional), p2 ext4 lin0root — so use /boot on p2.

set -e

ROOTFS="${outdir:-../rootfs}"
BOOT="$ROOTFS/boot"
DTB_NAME="rk3588s-radxa-cm5-io.dtb"
ROOT_LABEL="${ROOT_LABEL:-lin0root}"
BOOT_LABEL="${BOOT_LABEL:-LIN0BOOT}"
CMN="console=tty0 rootwait rw init=/sbin/init"

mkdir -p "$BOOT/extlinux" "$ROOTFS/lib/firmware" "$ROOTFS/etc"

# --- ext4 /boot/extlinux (primary — same idea as official p3) ---
# Paths are absolute from filesystem root of the partition (U-Boot loads from part 2).
cat > "$BOOT/extlinux/extlinux.conf" << EOF
DEFAULT lin0
TIMEOUT 10
MENU TITLE lin0 CM5 IO (ext4 /$ROOT_LABEL — official-style /boot)
LABEL lin0
	MENU LABEL lin0 root=LABEL=$ROOT_LABEL
	LINUX /boot/Image
	FDT /boot/$DTB_NAME
	APPEND $CMN root=LABEL=$ROOT_LABEL rootfstype=ext4
LABEL lin0-mmc0
	MENU LABEL lin0 root=/dev/mmcblk0p2
	LINUX /boot/Image
	FDT /boot/$DTB_NAME
	APPEND $CMN root=/dev/mmcblk0p2 rootfstype=ext4
LABEL lin0-mmc1
	MENU LABEL lin0 root=/dev/mmcblk1p2
	LINUX /boot/Image
	FDT /boot/$DTB_NAME
	APPEND $CMN root=/dev/mmcblk1p2 rootfstype=ext4
EOF

# FAT-style copy for p1 (paths at partition root — secondary)
mkdir -p "$BOOT/fat-extlinux"
cat > "$BOOT/fat-extlinux/extlinux.conf" << EOF
DEFAULT lin0
TIMEOUT 10
MENU TITLE lin0 CM5 IO (FAT $BOOT_LABEL)
LABEL lin0
	MENU LABEL lin0 root=LABEL=$ROOT_LABEL
	LINUX /Image
	FDT /$DTB_NAME
	APPEND $CMN root=LABEL=$ROOT_LABEL rootfstype=ext4
EOF

printf 'lin0 radxa-cm5-io\n' > "$BOOT/lin0.id"

# boot.scr mirrors U-Boot lin0_boot (p2 /boot first, then p1)
cat > "$BOOT/boot.cmd" << 'BOOTCMD'
echo lin0 boot.scr official-style
setenv scriptaddr 0x00500000
setenv fdtfile rockchip/rk3588s-radxa-cm5-io.dtb
setenv bootargs console=tty0 root=LABEL=lin0root rootfstype=ext4 rootwait rw init=/sbin/init
for d in 0 1; do
	if test -e mmc ${d}:2 /boot/extlinux/extlinux.conf; then
		echo lin0 root mmc ${d}:2
		sysboot mmc ${d}:2 any ${scriptaddr} /boot/extlinux/extlinux.conf && exit
	fi
	if test -e mmc ${d}:1 /extlinux/extlinux.conf; then
		echo lin0 fat mmc ${d}:1
		sysboot mmc ${d}:1 any ${scriptaddr} /extlinux/extlinux.conf && exit
	fi
done
echo lin0 FAIL
sleep 30
BOOTCMD

if command -v mkimage >/dev/null 2>&1; then
	mkimage -C none -A arm64 -T script -d "$BOOT/boot.cmd" "$BOOT/boot.scr" 2>/dev/null \
		|| mkimage -C none -A arm -T script -d "$BOOT/boot.cmd" "$BOOT/boot.scr" 2>/dev/null || true
fi

for d in \
	"linux-"*/arch/arm64/boot/dts/rockchip/"$DTB_NAME" \
	arch/arm64/boot/dts/rockchip/"$DTB_NAME"; do
	if [ -f "$d" ]; then
		cp -f "$d" "$BOOT/$DTB_NAME"
		break
	fi
done
if [ ! -f "$BOOT/$DTB_NAME" ]; then
	find "$ROOTFS" -name "$DTB_NAME" 2>/dev/null | head -1 | while read -r f; do
		cp -f "$f" "$BOOT/$DTB_NAME"
	done
fi

[ -f "$ROOTFS/etc/resolv.conf" ] || echo "nameserver 1.1.1.1" > "$ROOTFS/etc/resolv.conf"
if ! grep -q radxacm5io "$ROOTFS/etc/issue" 2>/dev/null; then
	printf '\nlin0 on Radxa CM5 IO\nserial 1500000 8N1 ttyS2 | eMMC: flash-lin0-emmc-maskrom.sh\n' >> "$ROOTFS/etc/issue"
fi

echo "radxacm5io post-install done (boot=$BOOT, official-style /boot/extlinux)"
