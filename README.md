# lin0

[![License: BSD-2-Clause](https://img.shields.io/badge/license-BSD--2--Clause-blue.svg)](https://opensource.org/licenses/BSD-2-Clause)
[![Latest Release](https://img.shields.io/badge/release-v0.0.2-orange.svg)](#release-notes)
[![Docker Pulls](https://img.shields.io/docker/pulls/bleemayer/lin0)](https://hub.docker.com/r/bleemayer/lin0)
![Build Status](https://img.shields.io/badge/build-manual-lightgrey)

```
             _._
           e/` '\,.eo-__.     lin0 (linux zero) is a
          '/.' .|_/e--. '\e   super minimal source
    ,;-o-.'|`  //e    e\ |`   based linux meta
  ./' ,e0\o   //-o.__. ,. \'  distribution, aimed
 ./` /' -/e   e\o_/___.  \|'  at power users or
 e|`/`,o-o\  /v-/e_.  '\. \.  minimalism enthusiasts
'/  ._e._, \ //    \`  \e |'
'|'"/     \.V |    `|' `|'|`  it was born from
`|e`|'    | # /    `|.  |`|`  exercises in how
e|` `    /\- ,\    e|'  '\`   minimal a linux system
 '`    _/  / / \     `  `|'   can get.
   .,wW'^^^//;^-^;^;w_
```


## What is lin0?

**lin0 (linux zero)** is a **super minimal source-based Linux meta-distribution**, aimed at power users or minimalism enthusiasts. It was born from exercises in seeing just how minimal a Linux system can get.


### Features

The distro features a barebones system built from scratch:

- Linux kernel (no initrd)
- `musl` libc
- `mksh` (Myr Korn Shell)
- `tcc` (Tiny C Compiler)
- `toybox`
- Simple shell-script-based init system

---


## 📝 Release Notes

**v0.0.2**
- Improved compiler toolchain

**v0.0.1**
- Initial release

---


## 🛣️ Roadmap

### Current Work

- ~~~Support RPi Compute Module 5~~~
- ~~~Support Radxa CM5 + IO shield (mainline kernel)~~~
- Adjust kernel build:
  - Build HP EliteDesk with firmware built-in


### Planned Features

- Make system compile itself
- Improve RPi 3B+ rootfs
- Support mod loading and daemons in init script
- Improve issue file or add a login program like `ly`
- Create man pages
- ~~~Support RPi Zero W~~~ (`make rpizero` / `make rpizero-img`)
- Add lin0 to `fetch` et al. commands

---


## 📦 Images

We provide system images in multiple formats so you can get started without building everything from scratch.


### Tarballs (.tar.xz)

These are **architecture-targeted rootfs tarballs** (no kernel):

- [`x86_64`](./rootfs-x86_64.tar.xz) (3.3 MB)
- [`arm64`](./rootfs-arm64.tar.xz) (3.0 MB)


And these are Platform-specific and it includes the kernel:

- [`HP EliteDesk 800 G1`](./rootfs-hpelitedesk.tar.xz) (13 MB)
- [`Pinebook Pro`](./rootfs-pinebookpro.tar.xz) (13 MB)
- [`Raspberry Pi 3B+`](./rootfs-rpi3b+.tar.xz) (26 MB)
- Raspberry Pi Zero / Zero W — build: `make rpizero` → `rootfs-rpizero.tar.xz`; SD image: `make rpizero-img` → `lin0-rpizero.img`
- [`Raspberry Pi CM5 + io board`](./rootfs-rpi-cm5io.tar.xz) (32 MB)
- [`Radxa CM5 + IO shield`](./rootfs-radxacm5io.tar.xz) (mainline kernel; build via `./scripts/build-radxacm5io-docker.sh`)

Bootable disk image (kernel + U-Boot + rootfs) — **eMMC** (preferred) or SD:

- [`lin0-radxacm5io.img`](./lin0-radxacm5io.img) — full GPT image incl. SPL/U-Boot @ sector 64
- eMMC via Maskrom: `./scripts/flash-lin0-emmc-maskrom.sh`


### Docker

We also provide Docker images for quick testing or compiling with musl and tcc:

👉 [`bleemayer/lin0` on Docker Hub](https://hub.docker.com/r/bleemayer/lin0)

```sh
docker pull bleemayer/lin0:latest
```

Supported architectures match the tarballs.


## 🧰 Installation


### Radxa CM5 + IO shield (mainline)

Builds a complete bootable **disk image** (mainline kernel on `torvalds/linux` master for `rk3588s-radxa-cm5-io.dts`; Radxa vendor U-Boot `next-dev` for CM5 IO) inside Docker (`linux/arm64`):

```sh
git clone https://terminal.pink/lin0
cd lin0
./scripts/build-radxacm5io-docker.sh
```

Outputs:

| File | Purpose |
|------|---------|
| `lin0-radxacm5io.img` | Full disk image (loader @ sector 64, FAT boot, ext4 root) — flash to **eMMC** or SD |
| `rootfs-radxacm5io.tar.xz` | Root filesystem tarball (includes kernel + DTB under `/boot`) |
| `build/rk3588_spl_loader*.bin` | Maskrom/USB stage-1 loader for `rkdeveloptool db` |

**Install to eMMC (recommended, no SD)** — wipes existing Debian; writes SPL/U-Boot + lin0 in one image:

```sh
./scripts/flash-lin0-emmc-maskrom.sh          # instructions
# then, with board in Maskrom and rkdeveloptool installed:
rkdeveloptool ld
rkdeveloptool db build/rk3588_spl_loader.bin  # or exact rk3588_spl_loader_v*.bin path
rkdeveloptool wl 0 lin0-radxacm5io.img
rkdeveloptool rd
```

Optional SD path (**whole disk**, not a partition):

```sh
# Linux
sudo dd if=lin0-radxacm5io.img of=/dev/sdX bs=4M status=progress conv=fsync

# macOS (find disk with `diskutil list`, e.g. /dev/disk4)
diskutil unmountDisk /dev/disk4
sudo dd if=lin0-radxacm5io.img of=/dev/rdisk4 bs=4m
```

Power on the **Radxa CM5 IO** (12 V recommended); no SD required if eMMC was flashed.

- **Serial console**: `1500000 8N1` on the IO board debug UART (`ttyS2`)
- **Login**: `root` / `lin0`
- **DTB**: `rk3588s-radxa-cm5-io.dtb` (mainline `torvalds/linux` master)
- **Kernel**: mainline only (no vendor/rk-linux tree)

Optional overrides:

```sh
# pin a future stable once it includes the CM5 DTS, or stay on master:
# Kernel: mainline master (CM5 IO DTS). U-Boot: Radxa next-dev (no mainline CM5 IO defconfig).
LINUXVER=master UBOOTVER=next-dev IMG_SIZE_MB=512 ./scripts/build-radxacm5io-docker.sh
# default image is 256 MiB (BOOT_SIZE_MB=48, root ~192 MiB, labels LIN0BOOT / lin0root)
```

**Bootloader notes:** U-Boot itself is mainline (`v2025.04`, `rock5a-rk3588s_defconfig` — closest RK3588S board; the kernel uses the CM5 IO DTB). RK3588 still needs vendor DDR init + TF-A blobs from [rockchip-linux/rkbin](https://github.com/rockchip-linux/rkbin) (`BL31` + `ROCKCHIP_TPL`); these are not part of the Linux kernel and are the normal way to boot mainline U-Boot on RK3588 boards.

If the board fails to boot, re-flash only the bootloader with:

```sh
dd if=build/u-boot-rockchip.bin of=/dev/sdX seek=64 conv=notrunc
```

If the SoM boots from eMMC instead of SD, change `root=/dev/mmcblk1p2` in `boot/extlinux/extlinux.conf` to the correct root device (often `mmcblk0p2` for eMMC).


### From Source

Clone this repo:

```sh
git clone https://terminal.pink/lin0
```

Then follow these steps:

1. Copy your kernel config file to:
    ```sh
    configs/MODEL-linux.config
    ```

2. Build the root filesystem with Make (each platform is a target; deps are normal files so Make does incremental rebuilds):
    ```sh
    make help              # list targets
    make x86_64            # build rootfs-x86_64.tar.xz
    make pinebookpro       # build rootfs-pinebookpro.tar.xz
    make radxacm5io        # Docker hybrid image (Radxa CM5+IO)
    make                   # build for host arch
    ```
    Changing `configs/<platform>-*.config`, `init`, or an installed artifact under `rootfs/` causes Make to rebuild only what is out of date.


3. Copy the generated rootfs to your target system.

Extra packages in the `pkg/` folder will be copied to `/home/root/` on the target.


### From Tarball

If you downloaded one of the tarballs, you can install lin0 as follows:

1. Extract the root filesystem to your destination partition:
    ```sh
    tar -xf rootfs-ARCH.tar.xz -C /mnt/your-root
    ```
    Replace `ARCH` with the appropriate architecture (e.g., x86_64, arm64).

2. Copy your kernel to the boot folder:
    ```sh
    cp path/to/your/kernel /mnt/your-root/boot/
    ```
    (This could be a bzImage, Image, or zImage, depending on your platform.)


## 🚀 Usage

After successfully booting lin0, you'll be greeted with a login prompt.


### Default login

- **Username**: `root`
- **Password**: `lin0`

---


### Post-install setup

lin0 provides a minimal base system — to make it usable, you'll need to do a few things manually:


#### 1. Set up networking (DNS)

Create a simple `/etc/resolv.conf`:

```sh
echo "nameserver 1.1.1.1" > /etc/resolv.conf
```

Replace 1.1.1.1 with your preferred DNS server if needed.


#### 2. Add users

You can add users manually (note: toybox may provide a limited adduser):

```sh
adduser myuser
passwd myuser
```

But I recommend editing the shells file and creating the home folder.


#### 3. Secure your root account

```sh
passwd
```


#### 4. Install needed tools

Install extra software as required — for example, to connect to Wi-Fi install wpa_supplicant and its dependencies.



### Notes

lin0 does not come with systemd or other init frameworks — it uses a basic shell script–based init.

You are expected to customize your system configuration.

Think of lin0 as a starting point: it's minimal by design.

Welcome to lin0 — now you build the rest.


## 🙋 Help

Email the mailing list:  
`lin0 AT terminal DOT pink`

Wiki coming soon.


## 📜 License

This project is licensed under the BSD 2-Clause License.
(C) 2023-2025 Brian Mayer
