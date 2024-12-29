#!/bin/sh

mount -v --bind /dev rootfs/dev
mount -vt devpts devpts -o gid=5,mode=0620 rootfs/dev/pts
mount -vt proc proc rootfs/proc
mount -vt sysfs sysfs rootfs/sys

chroot rootfs /bin/env -i HOME=/home/root PATH=/bin sh # for testing
# chroot rootfs /bin/env -i HOME=/home/root PATH=/bin make-target.sh

umount rootfs/dev/pts 
umount rootfs/dev
umount rootfs/proc
umount rootfs/sys 
