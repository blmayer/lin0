#!/bin/bash
# Runs inside privileged Docker; env: P3_START_LBA P3_SECTS ROOT_UUID ROOT_LABEL
# KERNEL_REL DTB_REL ROOTFS_REL OUT_REL (paths under /work)
#
# lin0 kernel has no initrd: root=UUID= is rejected ("root= is invalid" → unknown-block(0,0)).
# Use explicit /dev/mmcblkXp3 (GPT p3 = official root) + LABEL= for the built-in cmdline fallback.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq util-linux e2fsprogs rsync >/dev/null

IMG="/work/${OUT_REL}"
ROOTFS="/work/${ROOTFS_REL}"
KERNEL="/work/${KERNEL_REL}"
DTB="/work/${DTB_REL}"
MNT=/mnt/lin0-hybrid-p3
mkdir -p "$MNT"

# Match lin0 kernel CONFIG_CMDLINE root=LABEL=lin0root when unset/overridden badly.
ROOT_LABEL="${ROOT_LABEL:-lin0root}"

OFF=$((P3_START_LBA * 512))
SZ=$((P3_SECTS * 512))
LOOP=$(losetup --find --show -o "$OFF" --sizelimit "$SZ" "$IMG")
cleanup() {
	set +e
	sync
	umount "$MNT" 2>/dev/null || true
	losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

echo " loop $LOOP -> p3 @ LBA $P3_START_LBA (label=$ROOT_LABEL)"

# Optional UUID for reference; LABEL is what no-initrd path relies on besides mmcblk.
if [ -n "${ROOT_UUID:-}" ]; then
	mkfs.ext4 -F -L "$ROOT_LABEL" -U "$ROOT_UUID" "$LOOP"
else
	mkfs.ext4 -F -L "$ROOT_LABEL" "$LOOP"
fi
mount "$LOOP" "$MNT"

echo " installing lin0 rootfs..."
rsync -aH "$ROOTFS"/ "$MNT"/

# Musl: /lib/libc.so *is* the dynamic loader; ld-musl-* must resolve to it (symlink).
if [ -f "$MNT/lib/libc.so" ]; then
	chmod 755 "$MNT/lib/libc.so"
	ln -sfn libc.so "$MNT/lib/ld-musl-aarch64.so.1"
	ln -sfn libc.so "$MNT/lib/ld-linux-aarch64.so.1" 2>/dev/null || true
fi

mkdir -p "$MNT/boot/extlinux" "$MNT/proc" "$MNT/sys" "$MNT/dev" "$MNT/tmp" "$MNT/run" "$MNT/mnt"
install -m 0644 "$KERNEL" "$MNT/boot/Image"
install -m 0644 "$KERNEL" "$MNT/boot/vmlinuz-lin0"
install -m 0644 "$DTB" "$MNT/boot/rk3588s-radxa-cm5-io.dtb"
mkdir -p "$MNT/usr/lib/linux-image-lin0"
install -m 0644 "$DTB" "$MNT/usr/lib/linux-image-lin0/rk3588s-radxa-cm5-io.dtb"

if [ ! -e "$MNT/dev/console" ]; then
	mknod -m 600 "$MNT/dev/console" c 5 1 2>/dev/null || true
	mknod -m 666 "$MNT/dev/null" c 1 3 2>/dev/null || true
	# Nodes for explicit root= paths (kernel does not need them to exist before mount, but init might)
	mkdir -p "$MNT/dev"
fi

# Always use platform PID1 (banner + mounts + shell; never getty/exit)
if [ -f /work/scripts/radxacm5io-init.sh ]; then
	install -m 0755 /work/scripts/radxacm5io-init.sh "$MNT/sbin/init"
elif [ ! -x "$MNT/sbin/init" ] && [ ! -x "$MNT/init" ]; then
	echo "error: no init in installed rootfs" >&2
	exit 1
fi

# Kernel cmdline — no UUID (needs initramfs). Prefer mmcblk0p3 (eMMC on CM5); extras for SD/remap.
# rootwait keeps trying until the mmc host probes the card.
CMDLINE_COMMON="rootfstype=ext4 rootwait rw init=/sbin/init console=tty0"

cat > "$MNT/boot/extlinux/extlinux.conf" << EOF
## lin0 on official Radxa layout (p3 /boot/extlinux — stock U-Boot)
## No initrd: use /dev/mmcblk*p3 or LABEL= (UUID= is invalid on this kernel)
default emmc
menu title lin0 on official CM5 IO U-Boot
prompt 1
timeout 20

label emmc
	menu label lin0 root=/dev/mmcblk0p3 (eMMC GPT p3)
	linux /boot/Image
	fdt /boot/rk3588s-radxa-cm5-io.dtb
	append root=/dev/mmcblk0p3 $CMDLINE_COMMON

label emmc1
	menu label lin0 root=/dev/mmcblk1p3 (alt mmc index)
	linux /boot/Image
	fdt /boot/rk3588s-radxa-cm5-io.dtb
	append root=/dev/mmcblk1p3 $CMDLINE_COMMON

label emmc2
	menu label lin0 root=/dev/mmcblk2p3
	linux /boot/Image
	fdt /boot/rk3588s-radxa-cm5-io.dtb
	append root=/dev/mmcblk2p3 $CMDLINE_COMMON

label bylabel
	menu label lin0 root=LABEL=$ROOT_LABEL
	linux /boot/Image
	fdt /boot/rk3588s-radxa-cm5-io.dtb
	append root=LABEL=$ROOT_LABEL $CMDLINE_COMMON
EOF

echo "lin0-hybrid" > "$MNT/etc/lin0-hybrid-stamp" 2>/dev/null || echo "lin0-hybrid" > "$MNT/lin0-hybrid-stamp"

sync
umount "$MNT"
losetup -d "$LOOP"
trap - EXIT
echo " p3 done: label=$ROOT_LABEL extlinux prefers root=/dev/mmcblk0p3"
