#!/bin/sh
# Raspberry Pi Zero / Zero W — boot files for RPi firmware (FAT /boot + ext4 root).
# Kernel: mainline arm ARCH_BCM2835 (zImage + bcm2835-rpi-zero*.dtb).
# Run from build/ with outdir/PLATFORM/linuxver set (Makefile post-install).

set -e

ROOTFS="${outdir:-../rootfs}"
BOOT="$ROOTFS/boot"
LINUX_SRC="${linux_src:-linux-$linuxver}"
FW_REPO="${FW_REPO:-https://github.com/raspberrypi/firmware.git}"

mkdir -p "$BOOT" "$ROOTFS/lib/firmware/brcm" "$ROOTFS/etc"

# --- kernel + DTB (built during linux step; re-copy if present) ---
if [ -d "$LINUX_SRC" ]; then
	(
		cd "$LINUX_SRC"
		# armv6: zImage, not Image/bzImage
		if [ -f arch/arm/boot/zImage ]; then
			cp -f arch/arm/boot/zImage "$BOOT/kernel.img"
		fi
		for dtb in \
			arch/arm/boot/dts/broadcom/bcm2835-rpi-zero-w.dtb \
			arch/arm/boot/dts/broadcom/bcm2835-rpi-zero.dtb \
			arch/arm/boot/dts/bcm2835-rpi-zero-w.dtb \
			arch/arm/boot/dts/bcm2835-rpi-zero.dtb
		do
			[ -f "$dtb" ] && cp -f "$dtb" "$BOOT/"
		done
	)
fi

# --- RPi GPU/start firmware (bootcode, start.elf, fixup.dat) ---
if [ ! -d raspberrypi-firmware/.git ]; then
	echo "cloning raspberrypi/firmware (boot blobs only)..."
	git clone --depth 1 --filter=blob:none --sparse "$FW_REPO" raspberrypi-firmware
	(
		cd raspberrypi-firmware
		git sparse-checkout set boot
	)
fi
for f in bootcode.bin start.elf fixup.dat start_cd.elf fixup_cd.dat; do
	[ -f "raspberrypi-firmware/boot/$f" ] && cp -f "raspberrypi-firmware/boot/$f" "$BOOT/"
done

# Prefer Zero W DTB if present
DTB=bcm2835-rpi-zero-w.dtb
[ -f "$BOOT/$DTB" ] || DTB=bcm2835-rpi-zero.dtb

cat > "$BOOT/config.txt" << EOF
# lin0 — Raspberry Pi Zero / Zero W
arm_64bit=0
kernel=kernel.img
device_tree=$DTB
enable_uart=1
dtoverlay=disable-bt
gpu_mem=16
EOF

cat > "$BOOT/cmdline.txt" << EOF
console=serial0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw init=/bin/init
EOF

# --- WiFi firmware for Zero W (brcmfmac43430) ---
if [ ! -d linux-firmware/.git ] && [ ! -d ../linux-firmware/.git ]; then
	echo "cloning linux-firmware (brcm wifi)..."
	git clone --depth 1 --filter=blob:none --sparse \
		https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git \
		linux-firmware 2>/dev/null || true
	if [ -d linux-firmware ]; then
		( cd linux-firmware && git sparse-checkout set brcm cypress 2>/dev/null || true )
	fi
fi
FW_SRC=linux-firmware
[ -d ../linux-firmware/brcm ] && FW_SRC=../linux-firmware
if [ -d "$FW_SRC/brcm" ]; then
	cp -f "$FW_SRC/brcm/brcmfmac43430-sdio.bin" "$ROOTFS/lib/firmware/brcm/" 2>/dev/null || true
	cp -f "$FW_SRC/brcm/brcmfmac43430-sdio.txt" "$ROOTFS/lib/firmware/brcm/" 2>/dev/null || true
	cp -f "$FW_SRC/brcm/brcmfmac43430-sdio.clm_blob" "$ROOTFS/lib/firmware/brcm/" 2>/dev/null || true
	# Pi Zero W NVRAM variant
	if [ -f "$FW_SRC/brcm/brcmfmac43430-sdio.raspberrypi,model-zero-w.txt" ]; then
		cp -f "$FW_SRC/brcm/brcmfmac43430-sdio.raspberrypi,model-zero-w.txt" \
			"$ROOTFS/lib/firmware/brcm/"
	fi
	cp -f "$FW_SRC/brcm/LICENSE.broadcom_bcm43xx" "$ROOTFS/lib/firmware/brcm/" 2>/dev/null || true
fi

echo "rpizero post-install: boot files in $BOOT (kernel.img, $DTB, config.txt, cmdline.txt)"
echo "  flash: partition SD (p1 FAT boot, p2 ext4 root), copy $BOOT/* to p1, rootfs to p2"
echo "  or: make rpizero-img  (if mkimg-rpizero.sh present)"
