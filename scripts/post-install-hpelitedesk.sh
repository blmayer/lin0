#!/bin/sh

# pwd is /tmp

# make kernel
[ -d linux-firmware ] || git clone https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git
cd "linux-$linuxver"
make -j 4
[ -d /boot ] || mkdir /boot
make INSTALL_MOD_PATH=/ INSTALL_PATH=/boot install modules_install
cd ..

echo "copying firmware license"
[ -d /lib/firmware ] || mkdir -p /lib/firmware
cp linux-firmware/LICENSE.iwlwifi_firmware /lib/firmware
cd ..
