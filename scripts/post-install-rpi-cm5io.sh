#!/bin/sh

url="git@github.com:RPi-Distro/firmware-nonfree.git"

cd build
git clone "$url"

mkdir -p ../../rootfs/lib/firmware/brcm
cp firmware-nonfree/cypress/cyfmac43455-sdio-standard.bin ../../rootfs/lib/firmware/brcm/brcmfmac43455.bin
