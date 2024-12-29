#!/bin/sh

cd build

# make kernel
[ -d linux-firmware ] || git clone https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git
cd "linux-$linuxver"
make -j 4
[ -d ../../rootfs/boot ] || mkdir ../../rootfs/boot
make INSTALL_MOD_PATH=../../rootfs INSTALL_PATH=../../rootfs/boot install modules_install
cd ..

echo "copying firmware license"
[ -d ../../rootfs/lib/firmware ] || mkdir ../../rootfs/lib/firmware
cp linux-firmware/LICENSE.iwlwifi_firmware ../rootfs/lib/firmware
cd ..
