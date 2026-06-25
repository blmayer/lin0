#!/bin/sh
# PID1 for Radxa CM5 IO lin0 — keep simple; never exit (panic if init dies).
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

banner() {
	[ -r /etc/issue ] || return 0
	echo
	cat /etc/issue
	echo
}

banner
banner >/dev/console 2>/dev/null
banner >/dev/tty0 2>/dev/null

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t tmpfs tmpfs /run
mount -t tmpfs tmpfs /var/run
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# Apple USB keyboards (built-in preferred; fall back to module if present)
modprobe hid_apple 2>/dev/null || true
kver=$(uname -r 2>/dev/null)
for f in \
	"/lib/modules/$kver/kernel/drivers/hid/hid-apple.ko" \
	"/lib/modules/$kver/kernel/drivers/hid/hid-apple.ko.xz"
do
	[ -f "$f" ] && insmod "$f" 2>/dev/null && break
done

exec /bin/sh
