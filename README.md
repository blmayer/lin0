# lin0

[![License: BSD-2-Clause](https://img.shields.io/badge/license-BSD--2--Clause-blue.svg)](https://opensource.org/licenses/BSD-2-Clause)
[![Rolling release](https://img.shields.io/badge/release-rolling-orange.svg)](#roadmap)
[![Docker Pulls](https://img.shields.io/docker/pulls/bleemayer/lin0)](https://hub.docker.com/r/bleemayer/lin0)

```
             _._
           e/` '\,.eo-__.        lin0 (linux zero) is a
          '/.' .|_/e--. '\e      super minimal source
    ,;-o-.'|`  //e    e\ |`      based linux meta
  ./' ,e0\o   //-o.__. ,. \'     distribution, aimed
 ./` /' -/e   e\o_/___.  \|'     at power users or
 e|`/`,o-o\  /v-/e_.  '\. \.     minimalism enthusiasts
'/  ._e._, \ //    \`  \e |'
'|'"/     \.V |    `|' `|'|`     it was born from
`|e`|'    | # /    `|.  |`|`     exercises in how
e|` `    /\- ,\    e|'  '\`      minimal a linux system
 '`    _/  / / \     `  `|'      can get.
   .,wW'^^^//;^-^;^;w_
```

## Features

- Linux kernel (no initrd)
- `musl` libc
- `mksh` (MirBSD Korn Shell)
- `tcc` (Tiny C Compiler)
- `toybox`
- Shell-script init (`init`)

## Quick start

```sh
git clone https://terminal.pink/lin0
cd lin0
make help          # list platforms
make               # build for the host architecture
```

Each platform is a Make target. Outputs are `rootfs-<platform>.tar.xz`
(and a full disk image for some boards).

```sh
make x86_64
make pinebookpro
make rpizero       # also: make rpizero-img
make radxacm5io    # rootfs tarball + hybrid disk image
```

Edit `configs/<platform>-*.config`, `etc/*`, or `init`, then rebuild — Make
only rebuilds what changed.

## Images

### Rootfs tarballs

Architecture-only (no kernel):

| Artifact | Notes |
| --- | --- |
| [`rootfs-x86_64.tar.xz`](./rootfs-x86_64.tar.xz) | ~3.3 MB |
| [`rootfs-arm64.tar.xz`](./rootfs-arm64.tar.xz) | ~3.0 MB |

Platform images (include kernel where applicable):

| Platform | Artifact | Build |
| --- | --- | --- |
| HP EliteDesk 800 G1 | [`rootfs-hpelitedesk.tar.xz`](./rootfs-hpelitedesk.tar.xz) | `make hpelitedesk` |
| Pinebook Pro | [`rootfs-pinebookpro.tar.xz`](./rootfs-pinebookpro.tar.xz) | `make pinebookpro` |
| Raspberry Pi 3B+ | [`rootfs-rpi3b+.tar.xz`](./rootfs-rpi3b+.tar.xz) | `make rpi3bplus` |
| Raspberry Pi Zero / Zero W | `rootfs-rpizero.tar.xz`, `lin0-rpizero.img` | `make rpizero` / `make rpizero-img` |
| Raspberry Pi CM5 + IO | [`rootfs-rpi-cm5io.tar.xz`](./rootfs-rpi-cm5io.tar.xz) | `make rpi-cm5io` |
| Radxa CM5 + IO | `rootfs-radxacm5io.tar.xz`, `lin0-radxacm5io.img` | `make radxacm5io` |

### Docker

Prebuilt images for trying the userland or compiling with musl/`tcc`:

```sh
docker pull bleemayer/lin0:latest
```

See [`bleemayer/lin0`](https://hub.docker.com/r/bleemayer/lin0) on Docker Hub.
Architectures match the tarballs above.

## Install from a tarball

```sh
tar -xf rootfs-ARCH.tar.xz -C /mnt/your-root
cp path/to/kernel /mnt/your-root/boot/   # if the tarball has no kernel
```

Replace `ARCH` with `x86_64`, `arm64`, or a platform name. Kernel name is
platform-specific (`bzImage`, `Image`, `zImage`, …).

Files under `pkg/` are copied to `/home/root/` on the target when present.

## Radxa CM5 + IO (mainline)

`make radxacm5io` builds a **hybrid** bootable disk image: SPL/U-Boot and the
GPT layout come from the official Radxa Debian image; partition 3 is resized
and filled with lin0 (mainline kernel + `rk3588s-radxa-cm5-io.dtb`).

On macOS, Make runs the arm64 compile and the privileged partition formatting
inside Docker automatically.

```sh
git clone https://terminal.pink/lin0
cd lin0
make radxacm5io
```

| Output | Purpose |
| --- | --- |
| `lin0-radxacm5io.img` | Full GPT image (loader at sector 64, ext4 root on partition 3) |
| `rootfs-radxacm5io.tar.xz` | Root filesystem (kernel + DTB under `/boot`) |
| `build/rk3588_spl_loader*.bin` | Maskrom stage-1 loader for `rkdeveloptool db` |

### Flash to eMMC (recommended)

Puts the board in Maskrom mode (hold recovery, power on), then:

```sh
rkdeveloptool ld
rkdeveloptool wl 0 lin0-radxacm5io.img
rkdeveloptool rd
```

This overwrites the existing Debian install.

### Flash to SD (whole disk)

```sh
# Linux
sudo dd if=lin0-radxacm5io.img of=/dev/sdX bs=4M status=progress conv=fsync

# macOS — use diskutil list; example disk4
diskutil unmountDisk /dev/disk4
sudo dd if=lin0-radxacm5io.img of=/dev/rdisk4 bs=4m
```

Power the **Radxa CM5 IO** with 12 V. Console is HDMI (`tty0`) with a USB
keyboard.

Optional knobs:

```sh
make radxacm5io RADXA_LINUXVER=master RADXA_P3_MB=128
```

U-Boot offers two root choices: `root=/dev/mmcblk0p3` (eMMC partition 3) and
`root=LABEL=lin0root`. Pick one from the boot menu if the default does not
find the rootfs.

## Build from source

1. Add or edit kernel/toybox configs:

   ```text
   configs/MODEL-linux.config
   configs/MODEL-toybox.config
   ```

2. Build:

   ```sh
   make help
   make x86_64
   make pinebookpro
   make radxacm5io
   make              # host architecture
   ```

3. Install the resulting `rootfs-*.tar.xz` (or disk image) on the target.

Static system config lives in `etc/` (generic only). TLS trust anchors are
fetched at build time from [curl.se/ca/cacert.pem](https://curl.se/ca/cacert.pem)
into `rootfs/etc/ssl/` (SHA-256 pinned as `CACERT_SHA256` in the Makefile).
`wget` links against BearSSL + libtls-bearssl and loads `/etc/ssl/cert.pem` by
default.

## Usage

- **Username:** `root`
- **Password:** `lin0`

There is no systemd — init is a shell script. Expect to configure the rest
yourself.

### Networking

Default DNS ships in `etc/resolv.conf`. On a running system:

```sh
vi /etc/resolv.conf
```

### Users

```sh
adduser myuser
passwd myuser
```

Or edit `etc/passwd` / `etc/shells` in the tree and create the home directory
before rebuilding. Lock down root with `passwd` after first boot.

### Extra software

Install what you need on the target (for example `wpa_supplicant` for Wi-Fi).
lin0 is a starting point, not a full desktop stack.

## Roadmap

- Ship HP EliteDesk with firmware built into the kernel
- Make the system able to compile itself
- Improve the Raspberry Pi 3B+ rootfs
- Load modules and start daemons from `init`
- Better login/issue screen (something like `ly`)
- Man pages
- Add lin0 to `fetch` and similar tools

## Help

Mailing list: `lin0 AT terminal DOT pink`

## License

BSD 2-Clause. © 2023–2026 Brian Mayer
