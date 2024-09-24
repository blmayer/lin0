#!/bin/sh

# make kernel
[ -d ../rootfs/boot ] || mkdir ../rootfs/boot
cd "linux-$linuxver"
#make -j 4
#make INSTALL_MOD_PATH=../../rootfs INSTALL_PATH=../../rootfs/boot install modules_install
cd ..

# install iw firmware
#git clone https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git
[ -d ../rootfs/lib/firmware/brcm ] || mkdir -p ../rootfs/lib/firmware/brcm
cp linux-firmware/brcm/brcmfmac43430a0-sdio.bin ../rootfs/lib/firmware/brcm/
#cp linux-firmware/brcm/brcmfmac43456-sdio.bin ../rootfs/lib/firmware
#cp linux-firmware/brcm/brcmfmac43456-sdio.clm_blob ../rootfs/lib/firmware
#cp linux-firmware/brcm/brcmfmac43456-sdio.AP6256.txt ../rootfs/lib/firmware
#cp linux-firmware/brcm/brcmfmac43456-sdio.pine64,pinebook-pro.txt ../rootfs/lib/firmware
#cp linux-firmware/brcm/BCM4345C5.hcd ../rootfs/lib/firmware
