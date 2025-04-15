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

- Adjust kernel build:
  - Build HP EliteDesk with firmware built-in


### Planned Features

- Make system compile itself
- Improve RPi 3B+ rootfs
- Support mod loading and daemons in init script
- Improve issue file or add a login program like `ly`
- Create man pages
- Support RPi Zero W
- Support RPi Compute Module 5
- Add lin0 to `fetch` et al. commands

---


## 📦 Images

We provide system images in multiple formats so you can get started without building everything from scratch.


### Tarballs (.tar.xz)

These are **platform-targeted rootfs tarballs** (no kernel):

**v0.0.2**
- [`x86_64`](./rootfs-x86_64.tar.xz) (3.3 MB)

**v0.0.1**
- [`arm64`](./rootfs-arm64.tar.xz) (3.0 MB)


### Platform-specific (includes kernel)

- [`HP EliteDesk 800 G1`](./rootfs-hpelitedesk.tar.xz) (13 MB)
- [`Pinebook Pro`](./rootfs-pinebookpro.tar.xz) (13 MB)
- [`Raspberry Pi 3B+`](./rootfs-rpi3b+.tar.xz) (26 MB)


### Docker

We also provide Docker images for quick testing or compiling with musl and tcc:

👉 [`bleemayer/lin0` on Docker Hub](https://hub.docker.com/r/bleemayer/lin0)

```sh
docker pull bleemayer/lin0:latest
```

Supported architectures match the tarballs.


## 🧰 Installation


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

2. Build the root filesystem with:
    ```sh
    platform=PLATFORM ./make.sh
    ```
    Replace `PLATFORM` with the name of your target system (see configs/ folder).


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
