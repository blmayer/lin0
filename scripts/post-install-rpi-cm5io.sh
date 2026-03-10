#!/bin/sh

set -e

[ -d ../rootfs/boot ] || mkdir -p ../rootfs/boot

# Clone RPi firmware repo (bootloader, DTBs, boot files)
echo "Fetching RPi firmware..."
[ -d firmware-rpi ] || git clone --depth 1 https://github.com/raspberrypi/firmware.git firmware-rpi

# Clone linux-firmware repo for additional firmware
echo "Fetching linux-firmware..."
[ -d linux-firmware ] || git clone --depth 1 https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git

# Clone RPi closed-source firmware (WiFi/BT)
echo "Fetching RPi non-free firmware..."
[ -d firmware-nonfree ] || git clone --depth 1 https://github.com/RPi-Distro/firmware-nonfree.git

# Install DTBs (bcm2712 for CM5, RPi 5)
echo "Installing DTBs..."
cp -v firmware-rpi/boot/dtbs/bcm2712-rpi-cm5*.dtb ../rootfs/boot/
cp -v firmware-rpi/boot/dtbs/bcm2712-rpi-5*.dtb ../rootfs/boot/

# Install boot files (bootcode.bin, start*.elf, fixup*.dat)
echo "Installing boot files..."
cp -v firmware-rpi/boot/{bootcode.bin,start*.elf,fixup*.dat} ../rootfs/boot/

# Install WiFi/BT firmware (BCM43455/BCM43456 on CM5)
echo "Installing WiFi/BT firmware..."
mkdir -p ../rootfs/lib/firmware/brcm
cp -v firmware-nonfree/cypress/cyfmac43455-sdio-standard.bin ../rootfs/lib/firmware/brcm/brcmfmac43455.bin
cp -v firmware-nonfree/cypress/cyfmac43455-sdio.clm_blob ../rootfs/lib/firmware/brcm/
cp -v firmware-nonfree/cypress/cyfmac43456-sdio-standard.bin ../rootfs/lib/firmware/brcm/brcmfmac43456.bin

# Install additional broadcom firmware from linux-firmware
echo "Installing additional firmware..."
cp -v linux-firmware/brcm/brcmfmac43430a0-sdio.bin ../rootfs/lib/firmware/brcm/
cp -v linux-firmware/brcm/brcmfmac43430-sdio.clm_blob ../rootfs/lib/firmware/brcm/
cp -v linux-firmware/brcm/brcmfmac43455-sdio.clm_blob ../rootfs/lib/firmware/brcm/
cp -v linux-firmware/brcm/brcmfmac43456-sdio.clm_blob ../rootfs/lib/firmware/brcm/

# Install overlays
[ -d ../rootfs/boot/overlays ] || mkdir -p ../rootfs/boot/overlays
cp -v firmware-rpi/boot/overlays/*.dtb ../rootfs/boot/overlays/
cp -v firmware-rpi/boot/overlays/README ../rootfs/boot/overlays/

echo "Done installing RPi CM5 firmware and DTBs."

