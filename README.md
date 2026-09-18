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
```

Each platform is a Make target. Most write `rootfs-<platform>.tar.gz`.
`make x86_64-generic` writes `rootfs-x86_64-generic.tar.gz`. Radxa also writes a
hybrid disk image; `make rpizero-img` builds an SD image from the zero
tarball.

```sh
make x86_64        # userland only (no kernel)
make x86_64-generic       # that userland + Linux 7.2.6 for PCs/VMs
make pinebookpro
make rpizero       # also: make rpizero-img
make radxacm5io    # rootfs tarball + hybrid disk image
```

Bare `make` builds the host architecture when that name is a platform
(for example `x86_64` on an x86_64 Linux box). On Apple Silicon it prints
the platform list and exits.

On macOS, `make x86_64-generic` and `make radxacm5io` run the compile in Docker.
Other platforms expect a Linux host (they chroot into the new rootfs).

Edit `configs/<platform>-*.config`, `etc/*`, or `init`, then rebuild — Make
only rebuilds what changed.

## Images

Prebuilt tarballs live under [`www/`](./www/). After download, verify the
full SHA-256 digest so the file has not been corrupted or tampered with:

```sh
# Linux
sha256sum -c SHA256SUMS

# macOS
shasum -a 256 -c SHA256SUMS
```

[`www/SHA256SUMS`](./www/SHA256SUMS) has the full digests. The `sha256` column
below is the first 16 hex chars for a quick eyeball check. Arch-only builds
have no kernel; the rest do. Raspberry Pi Zero is build-only (not published).

```
+----------------------+------+------------------+------------------+
| platform             | size | sha256           | build            |
+----------------------+------+------------------+------------------+
| x86_64               | 4.7M | ad3d52203ff36ac3 | make x86_64      |
| x86_64-generic       |  19M | 336be7abb70930ab | make x86_64-generic     |
| arm64                | 3.9M | a4f99c89fb6b2d97 | make arm64       |
| hp elite desk 800 g1 |  14M | 73752c23c40d1fdd | make hpelitedesk |
| pinebook pro         |  14M | 3e49689772dc0235 | make pinebookpro |
| raspberry pi 3b+     |  35M | 6b859999760e0d59 | make rpi3bplus   |
| rpi cm5 + io board   |  51M | 06bb5b9fdda241a9 | make rpi-cm5io   |
| radxa cm5 + io       |  27M | 0af2d1501e4e6c82 | make radxacm5io  |
| rpi zero / zero w    |    — | (local)          | make rpizero     |
+----------------------+------+------------------+------------------+
```

Tarballs: [`www/rootfs-*.tar.gz`](./www/).

### Docker

Prebuilt images for trying the userland or compiling with musl/`tcc`:

```sh
docker pull bleemayer/lin0:latest
```

See [`bleemayer/lin0`](https://hub.docker.com/r/bleemayer/lin0) on Docker Hub.
Architectures match the tarballs above.

## Install from a tarball

```sh
tar -xf rootfs-ARCH.tar.gz -C /mnt/your-root
cp path/to/kernel /mnt/your-root/boot/   # if the tarball has no kernel
```

Replace `ARCH` with `x86_64`, `x86_64-generic`, `arm64`, or a platform
name. Kernel name is platform-specific (`vmlinuz`, `Image`, `zImage`, …).

### x86_64-generic (kernel + userland)

`make x86_64-generic` builds the same musl/tcc userland as `x86_64` plus the current
stable kernel (7.2.6) with the usual PC and VM drivers built in (no initrd):
AHCI, NVMe, virtio, USB HID/storage, EFI stub, VGA/simpledrm, e1000/e1000e/r8169.

The tarball includes one kernel, `/boot/vmlinuz` (EFI-stub bzImage). There is
no disk image; partition a disk, extract the tarball, then copy that file onto
the ESP as `\EFI\BOOT\BOOTX64.EFI`.

Default kernel cmdline (EFI stub, overridable by the bootloader):

```
root=PARTLABEL=lin0root rootfstype=ext4 rw console=tty0 console=ttyS0,115200 init=/bin/init
```

Install on a disk (`/dev/sdX` — check `lsblk` first):

```sh
# GPT: 64MiB EFI System partition + the rest as Linux root
sgdisk --zap-all /dev/sdX
sgdisk --new=1:2048:+64M --typecode=1:ef00 --change-name=1:EFI \
       --new=2:0:0       --typecode=2:8300 --change-name=2:lin0root \
       /dev/sdX

mkfs.vfat -F 32 -n EFI /dev/sdX1
mkfs.ext4 -L lin0root /dev/sdX2

mount /dev/sdX2 /mnt
tar -xf rootfs-x86_64-generic.tar.gz -C /mnt
mkdir -p /mnt/boot/efi
mount /dev/sdX1 /mnt/boot/efi
mkdir -p /mnt/boot/efi/EFI/BOOT
cp /mnt/boot/vmlinuz /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI
umount /mnt/boot/efi /mnt
```

NVMe disks are `/dev/nvme0n1` with partitions `p1`/`p2` (`/dev/nvme0n1p1`).
The GPT name `lin0root` is what `root=PARTLABEL=lin0root` matches.

Firmware should boot `\EFI\BOOT\BOOTX64.EFI` from the ESP (removable-media
path). For QEMU with SeaBIOS, load the kernel yourself:

```sh
qemu-system-x86_64 -machine q35 -m 512 \
  -kernel /mnt/boot/vmlinuz \
  -drive file=/dev/sdX,format=raw,if=virtio \
  -append 'root=PARTLABEL=lin0root rootfstype=ext4 rw console=ttyS0,115200 init=/bin/init' \
  -nographic
```

On macOS, `make x86_64-generic` cross-builds the kernel in Docker.

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
| `rootfs-radxacm5io.tar.gz` | Root filesystem (kernel + DTB under `/boot`) |
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

The tree is one Makefile. It fetches musl 1.2.6, TinyCC, toybox, mksh,
GNU make, BearSSL, and libtls-bearssl, then chroots into the new rootfs
to self-host tcc. Most platforms also build a kernel (no initrd). Generic
uses Linux 7.2.6; the others use 6.13.3. Radxa follows Linus’s tree
(`RADXA_LINUXVER`, default `master`).

Need a C toolchain on the host (`gcc`, `make`, `bison`, `flex`, `bc`).
The chroot step needs Linux. On macOS only `x86_64-generic` and `radxacm5io`
are wired through Docker.

```sh
git clone https://terminal.pink/lin0
cd lin0
make help
make x86_64          # userland tarball, kernel headers only
make x86_64-generic         # userland + PC/VM kernel -> rootfs-x86_64-generic.tar.gz
make pinebookpro
make radxacm5io      # tarball + lin0-radxacm5io.img
```

Configs: `configs/<platform>-linux.config` and
`configs/<platform>-toybox.config`. Static files: `etc/`. Optional
`pkg/*` is copied to `/home/root` except on `x86_64` (that tarball ships
an empty home). TLS trust anchors come from
[curl.se/ca/cacert.pem](https://curl.se/ca/cacert.pem) at build time
(SHA-256 pinned as `CACERT_SHA256`). `wget` links against BearSSL +
libtls and loads `/etc/ssl/cert.pem`.

`make clean` removes `rootfs/` and tarballs. `make distclean` also
removes `build/`.

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

lin0 ships as a single-user system (root only). Toybox `useradd` /
`adduser` are not built in; add accounts by hand.

On a running system, as root:

```sh
# primary group (gid 100 is already in /etc/group as "users")
echo 'myuser::1000:100:myuser:/home/myuser:/bin/sh' >> /etc/passwd
mkdir -p /home/myuser
chown 1000:100 /home/myuser
passwd myuser
```

Then `su - myuser` or log in as `myuser` at the getty prompt.

Passwords live in `/etc/passwd` (there is no `/etc/shadow`). `passwd`
updates that file. Use a free uid (1000+) and an existing gid from
`/etc/group` (default `users` is 100). Shell must be listed in
`/etc/shells` (default `/bin/sh`).

To bake a user into the image, edit `etc/passwd` and `etc/group` in the
tree, create the home directory under `rootfs/home/`, then rebuild.
Lock down root with `passwd` after first boot.

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

## Site pages

The public site is the static files under [`www/`](./www/), served from
the bare repo at [terminal.pink/lin0](https://terminal.pink/lin0/index.html).
Hand-write `www/index.html`.
[captain](https://terminal.pink/captain) fills in `log.html`, `tree.html`,
`refs.html`, and per-commit pages. It never edits `index.html`.

Only `www/` is exported to the forge. Links that point outside that
folder (for example `../docs/`) 404 on the site; point at `tree.html`
or copy the page into `www/`.

### Index style

Match this page (and the other repos on terminal.pink):

- 52-character `<pre>`, magenta links (`#ff00ff`), `color-scheme: light dark`
- nav line: `log | tree | refs`
- lowercase running text; do not indent code snippets
- clone URL with no `.git` suffix: `git clone https://terminal.pink/lin0`

### New repo on terminal.pink

Same layout as this one. Replace `NAME` with the project directory name.

1. Hand-write `www/index.html` as above.

2. Init and commit the tree. Skip build artifacts.

   ```sh
   git init -b main
   git add …
   git commit
   ```

3. Install captain and generate pages. Generated files describe the
   commit they were built from, so they lag the tip by one unless you
   make a follow-up refresh commit (`--no-verify` so the hook does not
   dirty the tree again).

   ```sh
   /path/to/captain install   # post-commit hook
   captain -f
   git add www
   git commit --no-verify -m "www: initial captain pages."
   captain -f
   git add www
   git commit --no-verify -m "www: refresh captain pages."
   ```

4. Create the bare on the Pi and install the forge hooks.

   ```sh
   ssh pi 'cd ~/terminal.pink && git init --bare NAME'
   ```

   Copy `~/terminal.pink/captain/hooks/post-receive` to
   `NAME/hooks/post-receive`. On each push to `main` it walks every
   new commit, writes `www/*` into the bare root (prefix stripped),
   and appends `feed.xml`. lin0’s copy of this hook also
   `git push --mirror` to GitHub; skip that line until a mirror exists.

   Servrian serves the bare directory as static files. Git’s first
   request is `info/refs?service=git-upload-pack`, which 404s unless
   that name exists. `post-update` should keep dumb HTTP working:

   ```sh
   #!/bin/sh
   git gc
   git update-server-info
   ln -sfn refs "info/refs?service=git-upload-pack"
   ```

5. Push, then list the project on
   [`s.html`](https://terminal.pink/s.html) in the terminal.pink repo.

   ```sh
   git remote add origin pi:terminal.pink/NAME
   git push -u origin main
   ```

   SSH clone is `pi:terminal.pink/NAME`. HTTPS is
   `https://terminal.pink/NAME` (no `.git` suffix; shallow clones are
   not supported over this dumb transport).

## Help

Mailing list: `lin0 AT terminal DOT pink`

## License

BSD 2-Clause. © 2023–2026 Brian Mayer
