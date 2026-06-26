#!/bin/sh

# make kernel
[ -d ../rootfs/boot ] || mkdir ../rootfs/boot
cd "linux-$linuxver"
make -j 4
make INSTALL_MOD_PATH=../../rootfs INSTALL_PATH=../../rootfs/boot install modules_install
cd ..

# M1 Mac specific notes:
# - GPU acceleration requires Apple GPU firmware (not freely available)
# - Display works via framebuffer
# - USB/Thunderbolt should work out of the box

