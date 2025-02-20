#!/bin/sh

mount -v --bind /dev rootfs/dev
mount -vt devpts devpts -o gid=5,mode=0620 rootfs/dev/pts
mount -vt proc proc rootfs/proc
mount -vt sysfs sysfs rootfs/sys

