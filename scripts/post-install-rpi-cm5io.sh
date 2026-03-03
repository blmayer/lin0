url="git@github.com:RPi-Distro/firmware-nonfree.git"

git clone "$ur"

mkdir -p ../rootfs/lib/firmware/brcm
cp firmware-nonfree/cypress/cyfmac43455-sdio-standard.bin ../rootfs/lib/firmware/brcm/brcmfmac43455.bin
