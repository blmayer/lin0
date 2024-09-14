#!/bin/sh

# create missing links
ln -sv ../rootfs/lib/libc.so ../rootfs/bin/ldd
ln -sv ../rootfs/lib/libc.so ../rootfs/bin/ld

# make kernel
mkdir ../rootfs/boot
cd "linux-$linuxver"
make -j 4
make INSTALL_MOD_PATH=../../rootfs/lib INSTALL_PATH=../../rootfs/boot install modules_install
cd ..

# install iw firmware
git clone https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git
cd linux-firmware
