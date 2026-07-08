# lin0 — file prerequisites, literal paths, no stamps
#
#   make                 # host arch -> rootfs-<arch>.tar.xz
#   make radxacm5io      # rootfs tarball + hybrid image
#   make list | help | clean | distclean

SHELL := /bin/sh
.SHELLFLAGS := -ec

MUSLVER    := 1.2.5
LINUXVER   := 6.13.3
MAKEVER    := 4.4.1
MKSHVER    := R59c
BEARSSLVER  := 0.6
LIBTLS_BEARSSL_MAJOR := 33

MUSLURL    := https://musl.libc.org/releases/musl-$(MUSLVER).tar.gz
LINUXURL   := https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$(LINUXVER).tar.xz
TCCURL     := https://repo.or.cz/tinycc.git
TOYBOXURL  := https://github.com/landley/toybox.git
MKSHURL    := http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-$(MKSHVER).tgz
MAKEURL    := https://ftp.gnu.org/gnu/make/make-$(MAKEVER).tar.gz
BEARSSLURL := https://bearssl.org/bearssl-$(BEARSSLVER).tar.gz
LIBTLS_BEARSSL_URL := https://github.com/michaelforney/libtls-bearssl.git
REGDBURL   := https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/plain
CACERT_URL := https://curl.se/ca/cacert.pem
# Mozilla CA bundle via curl.se (mk-ca-bundle). Bump with the file.
CACERT_SHA256 := 86a1f3366afac7c6f8ae9f3c779ac221129328c43f0ab2b8817eb2f362a5025c
TLS_CFLAGS := -Os -fPIC -ffunction-sections -fdata-sections \
	-fno-asynchronous-unwind-tables -fno-unwind-tables
ROOTFS_LIBBEARSSL := rootfs/lib/libbearssl.so.$(BEARSSLVER)
ROOTFS_LIBTLS := rootfs/lib/libtls.so.$(LIBTLS_BEARSSL_MAJOR)
ROOTFS_TLS_LIBS := $(ROOTFS_LIBBEARSSL) $(ROOTFS_LIBTLS)
ROOTFS_TLS_HDRS := rootfs/include/tls.h rootfs/include/bearssl.h

# Platforms that have configs/<name>-{linux,toybox}.config
PLATFORMS  := x86_64 hpelitedesk pinebookpro rpi3bplus rpi-cm5io m1mac rpizero radxacm5io
AARCH64_PLATS := radxacm5io rpi3bplus pinebookpro rpi-cm5io m1mac

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
  HOST_ARCH := aarch64
endif
HOST_OS := $(shell uname -s)

PLATFORM ?= $(HOST_ARCH)

export outdir := $(CURDIR)/rootfs
export PLATFORM

RADXA_LINUXVER   ?= master
RADXA_P3_MB      ?= 384
RADXA_P3_LBA     := 679936
RADXA_DTB        := rk3588s-radxa-cm5-io.dtb
RADXA_OFFICIAL   ?= build/official-radxa-inspect/radxa-cm5-io_bookworm_cli_b3.output.img
RADXA_BUILDER    := lin0-radxacm5io-builder:latest
RADXA_ROOT_LABEL := lin0root
RADXA_ROOT_UUID  := a1ce5ba1-b0fe-43c3-b85c-eca170319b83
RADXA_CMN        := console=tty0 rootwait rw init=/bin/init

MUSL_ARCH = $(if $(filter $(PLATFORM),$(AARCH64_PLATS)),aarch64,$(if $(filter rpizero,$(PLATFORM)),arm,$(if $(filter hpelitedesk,$(PLATFORM)),x86_64,$(PLATFORM))))
MUSL_LDSONAME := ld-musl-$(MUSL_ARCH).so.1
ROOTFS_MUSL_LD := rootfs/lib/$(MUSL_LDSONAME)
PLAT_CC := $(CURDIR)/rootfs/bin/musl-gcc

TOYBOX_CFLAGS := -Os -fPIE -I$(CURDIR)/rootfs/include $(TLS_CFLAGS)
TOYBOX_LDFLAGS = -pie -L$(CURDIR)/rootfs/lib -Wl,--gc-sections -Wl,-rpath,/lib \
	-ltls -lbearssl -Wl,-dynamic-linker,/lib/$(MUSL_LDSONAME)
TOYBOX_STRIP := strip -s -R .note -R .comment

ETC_SRC := $(shell find etc \( -type f -o -type l \) ! -path 'etc/ssl/*')
ROOTFS_ETC_SSL := rootfs/etc/ssl/cert.pem rootfs/etc/ssl/certs/ca-certificates.crt
ROOTFS_ETC := $(patsubst etc/%,rootfs/etc/%,$(ETC_SRC)) $(ROOTFS_ETC_SSL)

INIT_COMMON := rootfs/bin/toybox $(ROOTFS_MUSL_LD) $(ROOTFS_TLS_LIBS) $(ROOTFS_ETC)
INIT_DEPS = rootfs/bin/tcc rootfs/bin/cc $(INIT_COMMON)
ifeq ($(PLATFORM),radxacm5io)
  INIT_DEPS += rootfs/boot/Image
endif

# --- copy rules (repo file -> rootfs file) ----------------------------------

rootfs/etc/%: etc/%
	mkdir -p $(dir $@)
	rm -f $@
	cp -P $< $@

# CA bundle from curl.se (Mozilla certdata); not copied from etc/ssl.
build/cacert.pem:
	mkdir -p build
	curl -fsSL "$(CACERT_URL)" -o build/cacert.pem.tmp
	@cd build && printf '%s  %s\n' "$(CACERT_SHA256)" cacert.pem.tmp > cacert.pem.tmp.sha256
	@cd build && { command -v sha256sum >/dev/null && sha256sum -c cacert.pem.tmp.sha256 \
		|| shasum -a 256 -c cacert.pem.tmp.sha256; }
	mv -f build/cacert.pem.tmp build/cacert.pem
	rm -f build/cacert.pem.tmp.sha256

rootfs/etc/ssl/cert.pem rootfs/etc/ssl/certs/ca-certificates.crt: build/cacert.pem
	mkdir -p $(dir $@)
	rm -f $@
	cp build/cacert.pem $@

rootfs/bin/init: init $(INIT_DEPS) | rootfs/home/root
	mkdir -p $(dir $@) rootfs/dev/pts \
		rootfs/proc rootfs/sys rootfs/tmp rootfs/var/run rootfs/run
	chmod 1777 rootfs/tmp
	cp -f $< $@ && chmod +x $@

rootfs/bin/hotplugd: hotplugd
	mkdir -p $(dir $@)
	cp -f $< $@ && chmod +x $@

# Optional drop-ins: pkg/* -> rootfs/home/root/* (pattern rule, no staging).
PKG_FILES := $(wildcard pkg/*)
ROOTFS_PKG := $(patsubst pkg/%,rootfs/home/root/%,$(PKG_FILES))

rootfs/home/root/%: pkg/%
	mkdir -p $(dir $@)
	cp -a $< $@

.PHONY: rootfs-home-pkg
rootfs-home-pkg: $(ROOTFS_PKG) | rootfs/home/root

rootfs/home/root:
	mkdir -p $@

# --- sources under build/ ---------------------------------------------------

define fetch_tar
build/$(1):
	mkdir -p build
	curl -fsSL "$(2)" | tar xz -C build
endef
$(eval $(call fetch_tar,musl-$(MUSLVER)/configure,$(MUSLURL)))
$(eval $(call fetch_tar,make-$(MAKEVER)/configure,$(MAKEURL)))
$(eval $(call fetch_tar,mksh/Build.sh,$(MKSHURL)))
$(eval $(call fetch_tar,bearssl-$(BEARSSLVER)/Makefile,$(BEARSSLURL)))

build/linux-$(LINUXVER).tar.xz:
	mkdir -p build
	curl -fsSL -o $@ "$(LINUXURL)"

build/linux-$(LINUXVER)/Makefile: build/linux-$(LINUXVER).tar.xz
	tar xf $< -C build

define fetch_git
build/$(1)/.git:
	mkdir -p build
	git clone $(2) $(3) build/$(1)
endef
$(eval $(call fetch_git,toybox,,$(TOYBOXURL)))
$(eval $(call fetch_git,libtls-bearssl,--depth=1,$(LIBTLS_BEARSSL_URL)))

build/tinycc/.git:
	rm -rf build/tinycc
	mkdir -p build
	git clone "$(TCCURL)" build/tinycc

$(ROOTFS_LIBBEARSSL) rootfs/include/bearssl.h: build/bearssl-$(BEARSSLVER)/Makefile rootfs/bin/musl-gcc
	@echo "==> bearssl ($(BEARSSLVER))"
	mkdir -p rootfs/lib rootfs/include
	$(MAKE) -C build/bearssl-$(BEARSSLVER) CC=$(PLAT_CC) \
		CFLAGS="-std=c99 -Wall $(TLS_CFLAGS) -I src -I inc" build/libbearssl.a
	rm -rf build/bearssl-so.tmp && mkdir build/bearssl-so.tmp
	(cd build/bearssl-so.tmp && ar x $(CURDIR)/build/bearssl-$(BEARSSLVER)/build/libbearssl.a)
	$(PLAT_CC) -shared -Wl,-soname,libbearssl.so.0 -o $(ROOTFS_LIBBEARSSL) \
		build/bearssl-so.tmp/*.o -Wl,--gc-sections
	rm -rf build/bearssl-so.tmp && $(TOYBOX_STRIP) $(ROOTFS_LIBBEARSSL)
	ln -sfn libbearssl.so.$(BEARSSLVER) rootfs/lib/libbearssl.so.0
	ln -sfn libbearssl.so.0 rootfs/lib/libbearssl.so
	cp -f build/bearssl-$(BEARSSLVER)/inc/*.h rootfs/include/

$(ROOTFS_LIBTLS) rootfs/include/tls.h: build/libtls-bearssl/.git $(ROOTFS_LIBBEARSSL)
	@echo "==> libtls-bearssl"
	$(MAKE) -C build/libtls-bearssl clean >/dev/null 2>&1 || true
	rm -f build/libtls-bearssl/config.mk build/libtls-bearssl/*.o \
		build/libtls-bearssl/compat/*.o build/libtls-bearssl/libtls.a
	printf '%s\n' 'CC=$(PLAT_CC)' \
		'CFLAGS=-Wall $(TLS_CFLAGS) -I. -I$(CURDIR)/rootfs/include -D_GNU_SOURCE -DLIBRESSL_INTERNAL' \
		'LDFLAGS=-L$(CURDIR)/rootfs/lib' 'LDLIBS=-lbearssl' \
		> build/libtls-bearssl/config.mk
	$(MAKE) -C build/libtls-bearssl libtls.a
	mkdir -p rootfs/lib rootfs/include
	rm -rf build/libtls-so.tmp && mkdir build/libtls-so.tmp
	(cd build/libtls-so.tmp && ar x $(CURDIR)/build/libtls-bearssl/libtls.a)
	$(PLAT_CC) -shared -Wl,-soname,libtls.so.$(LIBTLS_BEARSSL_MAJOR) -o $(ROOTFS_LIBTLS) \
		build/libtls-so.tmp/*.o -L$(CURDIR)/rootfs/lib -lbearssl -lpthread -Wl,--gc-sections
	rm -rf build/libtls-so.tmp && $(TOYBOX_STRIP) $(ROOTFS_LIBTLS)
	ln -sfn libtls.so.$(LIBTLS_BEARSSL_MAJOR) rootfs/lib/libtls.so
	cp -f build/libtls-bearssl/tls.h rootfs/include/
	strings $(ROOTFS_LIBTLS) | grep -q '/etc/ssl/cert.pem'

rootfs/lib/firmware/regulatory.db:
	mkdir -p $(dir $@)
	curl -fsSL -o $@ "$(REGDBURL)/regulatory.db"
	curl -fsSL -o $@.p7s "$(REGDBURL)/regulatory.db.p7s"

# --- toolchain pieces in rootfs/ --------------------------------------------

rootfs/lib/libc.so rootfs/bin/musl-gcc: build/musl-$(MUSLVER)/configure
	@echo "==> musl"
	mkdir -p rootfs
	cd build/musl-$(MUSLVER) && ./configure --prefix=$(CURDIR)/rootfs --enable-static
	$(MAKE) -C build/musl-$(MUSLVER)
	$(MAKE) -C build/musl-$(MUSLVER) install

$(ROOTFS_MUSL_LD) rootfs/bin/ldd rootfs/bin/ld: rootfs/lib/libc.so
	mkdir -p rootfs/bin rootfs/lib
	ln -sfn libc.so $(ROOTFS_MUSL_LD)
	rm -f rootfs/lib/ld-linux-$(MUSL_ARCH).so.1
	ln -sf ../lib/libc.so rootfs/bin/ldd
	ln -sf ../lib/libc.so rootfs/bin/ld

# Kernel UAPI lands in rootfs/include via headers_install INSTALL_HDR_PATH=rootfs
# (alongside musl; never staged under usr/ or patched after the fact).
LINUX_HEADERS = rootfs/include/linux/version.h rootfs/include/linux/types.h
BOOT_IMAGE = rootfs/boot/vmlinuz
ifeq ($(PLATFORM),rpizero)
  BOOT_IMAGE = rootfs/boot/kernel.img
else ifeq ($(PLATFORM),radxacm5io)
  BOOT_IMAGE = rootfs/boot/Image
endif

rootfs/bin/toybox: configs/$(PLATFORM)-toybox.config build/toybox/.git \
		rootfs/bin/musl-gcc $(ROOTFS_MUSL_LD) $(LINUX_HEADERS) $(BOOT_IMAGE) \
		$(ROOTFS_TLS_LIBS) $(ROOTFS_TLS_HDRS)
	@echo "==> toybox ($(PLATFORM))"
	-$(MAKE) -C build/toybox distclean
	cd build/toybox && KCONFIG_ALLCONFIG=$(CURDIR)/configs/$(PLATFORM)-toybox.config \
		$(MAKE) allnoconfig
	CC=$(PLAT_CC) STRIP="$(TOYBOX_STRIP)" \
		$(MAKE) -C build/toybox CFLAGS="$(TOYBOX_CFLAGS)" LDFLAGS="$(TOYBOX_LDFLAGS)" toybox
	$(MAKE) -C build/toybox PREFIX=$(CURDIR)/rootfs/bin install_flat
	@if command -v readelf >/dev/null; then \
		! readelf -S $@ | grep -q '\.symtab' || { echo "toybox not stripped" >&2; exit 1; }; \
		readelf -d $@ | grep -q 'libtls\.so' || { echo "toybox missing NEEDED libtls" >&2; exit 1; }; \
		readelf -d $@ | grep -q '\[libc\.so\]' || { echo "toybox missing NEEDED libc.so" >&2; exit 1; }; \
	fi
	@! strings $@ | grep -q GLIBC_ || { echo "toybox linked against glibc" >&2; exit 1; }
	@ls -lh $@ $(ROOTFS_TLS_LIBS)

rootfs/bin/make: rootfs/bin/musl-gcc build/make-$(MAKEVER)/configure
	@echo "==> make"
	cd build/make-$(MAKEVER) && CC=$(PLAT_CC) ./configure --prefix=$(CURDIR)/rootfs \
		--host=x86_64-linux-gnu --target=x86_64-linux-musl
	$(MAKE) -C build/make-$(MAKEVER)
	$(MAKE) -C build/make-$(MAKEVER) install

rootfs/bin/sh: rootfs/bin/musl-gcc build/mksh/Build.sh
	@echo "==> mksh"
	cd build/mksh && chmod +x Build.sh && CC="$(PLAT_CC) -static --no-pie" ./Build.sh
	install -c -s -m 555 build/mksh/mksh $@
	mkdir -p rootfs/share/man/man1
	-install -c -m 444 build/mksh/mksh.1 rootfs/share/man/man1/

# tcc named tcc (libtool tcc*); cc is a symlink. Dynamic musl only.
# tccdir=/lib/tcc (private: libtcc1 + headers). Never tccdir=/lib (would create /lib/include).
TCC_ELFINTERP := /lib/$(MUSL_LDSONAME)
TCC_LDFLAGS := -Wl,-dynamic-linker,$(TCC_ELFINTERP) -L$(CURDIR)/rootfs/lib
rootfs/bin/tcc: rootfs/bin/make rootfs/bin/sh build/tinycc/.git \
		$(LINUX_HEADERS) $(BOOT_IMAGE) rootfs/bin/musl-gcc $(ROOTFS_MUSL_LD) \
		rootfs/lib/libc.so
	@echo "==> tcc (dynamic musl; interp $(TCC_ELFINTERP))"
	$(MAKE) -C build/tinycc distclean >/dev/null 2>&1 || true
	cd build/tinycc && ./configure --prefix=/ \
		--cc="$(PLAT_CC)" \
		--extra-ldflags="$(TCC_LDFLAGS)" \
		--sysincludepaths=/include \
		--libpaths=/lib \
		--crtprefix=/lib --tccdir=/lib/tcc \
		--elfinterp=$(TCC_ELFINTERP) \
		--config-bcheck=no --disable-rpath --config-musl
	# configure may force LDFLAGS=-static for *gcc*; override on the make line.
	$(MAKE) -C build/tinycc LDFLAGS='$(TCC_LDFLAGS)' tcc libtcc.a
	$(MAKE) -C build/tinycc/lib \
		XCC="$(CURDIR)/build/tinycc/tcc" \
		XAR="$(CURDIR)/build/tinycc/tcc -ar" \
		XFLAGS="-B$(CURDIR)/build/tinycc -I$(CURDIR)/rootfs/include \
		-I$(CURDIR)/build/tinycc -I$(CURDIR)/build/tinycc/include"
	$(MAKE) -C build/tinycc DESTDIR=$(CURDIR)/rootfs install
	@interp=$$(readelf -l rootfs/bin/tcc | sed -n 's/.*\[Requesting program interpreter: \(.*\)\]/\1/p'); \
	[ "$$interp" = "$(TCC_ELFINTERP)" ] || { \
		echo "error: tcc interpreter is '$$interp', expected $(TCC_ELFINTERP)" >&2; exit 1; }; \
	! readelf -d rootfs/bin/tcc | grep -q 'libc\.so\.6\|ld-linux' || { \
		echo "error: tcc is linked against glibc" >&2; exit 1; }; \
	readelf -d rootfs/bin/tcc | grep -q '\[libc\.so\]' || { \
		echo "error: tcc missing NEEDED libc.so (musl)" >&2; exit 1; }; \
	chroot $(CURDIR)/rootfs /bin/tcc -vv 2>&1 | grep -q '$(TCC_ELFINTERP)' || { \
		echo "error: tcc -vv does not report elfinterp $(TCC_ELFINTERP)" >&2; exit 1; }; \
	echo "tcc ok: interp=$$interp dynamic musl"

rootfs/bin/cc: rootfs/bin/tcc
	ln -sfn tcc $@

rootfs/bin/ar: rootfs/bin/tcc
	printf '%s\n' '#!/bin/sh' 'tcc -ar "$$@"' > $@
	chmod +x $@

rootfs/bin/ranlib: rootfs/bin/tcc
	printf '%s\n' '#!/bin/sh' 'exec true' > $@
	chmod +x $@

# --- kernel: one recipe family per PLATFORM (single writer for version.h) ---

LIN0_LINUX_PATCHES := $(sort $(wildcard patches/linux-radxacm5io-*.patch))

build/linux-src/Makefile:
	mkdir -p build
	git clone --depth=1 https://github.com/torvalds/linux.git build/linux-src

# Apply lin0 DTS/driver patches once per source tree checkout.
build/linux-src/.lin0-patched: build/linux-src/Makefile $(LIN0_LINUX_PATCHES)
	for p in $(LIN0_LINUX_PATCHES); do \
		patch -d build/linux-src -p1 -N < "$$p" || \
		patch -d build/linux-src -p1 -R -s --dry-run < "$$p"; \
	done
	grep -q 'hym8563: rtc@51' \
		build/linux-src/arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5-io.dts
	touch $@

configs/radxacm5io-linux.config: configs/radxacm5io-kernel.fragment build/linux-src/.lin0-patched
	sh scripts/gen-radxacm5io-linux-config.sh build/linux-src

ifeq ($(PLATFORM),radxacm5io)
rootfs/boot/Image rootfs/boot/$(RADXA_DTB) $(LINUX_HEADERS): configs/radxacm5io-linux.config \
		rootfs/bin/musl-gcc build/linux-src/.lin0-patched
	@echo "==> linux (radxacm5io)"
	mkdir -p build/dtbs rootfs/boot
	cp -f $(CURDIR)/configs/radxacm5io-linux.config build/linux-src/.config
	$(MAKE) -C build/linux-src ARCH=arm64 olddefconfig
	$(MAKE) -C build/linux-src ARCH=arm64 -j$$(nproc) Image modules dtbs
	$(MAKE) -C build/linux-src ARCH=arm64 \
		INSTALL_MOD_PATH=$(CURDIR)/rootfs \
		INSTALL_HDR_PATH=$(CURDIR)/rootfs \
		modules_install headers_install
	cp -f build/linux-src/arch/arm64/boot/Image rootfs/boot/Image
	cp -f build/linux-src/arch/arm64/boot/dts/rockchip/$(RADXA_DTB) \
		rootfs/boot/$(RADXA_DTB)
	cp -f rootfs/boot/$(RADXA_DTB) build/dtbs/
	strings rootfs/boot/$(RADXA_DTB) | grep -q haoyu,hym8563

else ifeq ($(PLATFORM),rpizero)
rootfs/boot/kernel.img $(LINUX_HEADERS): configs/rpizero-linux.config \
		rootfs/bin/musl-gcc build/linux-$(LINUXVER)/Makefile
	@echo "==> linux (rpizero)"
	mkdir -p rootfs/boot
	cp -f configs/rpizero-linux.config build/linux-$(LINUXVER)/.config
	$(MAKE) -C build/linux-$(LINUXVER) ARCH=arm CC=$(PLAT_CC) olddefconfig
	$(MAKE) -C build/linux-$(LINUXVER) ARCH=arm CC=$(PLAT_CC) \
		INSTALL_HDR_PATH=$(CURDIR)/rootfs \
		INSTALL_PATH=$(CURDIR)/rootfs/boot \
		INSTALL_MOD_PATH=$(CURDIR)/rootfs \
		zImage dtbs modules headers_install modules_install
	cp -f build/linux-$(LINUXVER)/arch/arm/boot/zImage rootfs/boot/kernel.img
	-cp -f build/linux-$(LINUXVER)/arch/arm/boot/dts/broadcom/bcm2835-rpi-zero*.dtb rootfs/boot/
	-cp -f build/linux-$(LINUXVER)/arch/arm/boot/dts/bcm2835-rpi-zero*.dtb rootfs/boot/

else
rootfs/boot/vmlinuz $(LINUX_HEADERS): configs/$(PLATFORM)-linux.config \
		rootfs/bin/musl-gcc build/linux-$(LINUXVER)/Makefile
	@echo "==> linux ($(PLATFORM))"
	cp -f configs/$(PLATFORM)-linux.config build/linux-$(LINUXVER)/.config
	$(MAKE) -C build/linux-$(LINUXVER) CC=$(PLAT_CC) olddefconfig
	$(MAKE) -C build/linux-$(LINUXVER) CC=$(PLAT_CC) \
		INSTALL_HDR_PATH=$(CURDIR)/rootfs \
		INSTALL_PATH=$(CURDIR)/rootfs/boot \
		INSTALL_MOD_PATH=$(CURDIR)/rootfs \
		install headers_install modules_install
endif

# --- skeleton / post-install ------------------------------------------------

.PHONY: skeleton
skeleton: rootfs/bin/init rootfs/bin/hotplugd $(INIT_DEPS)

.PHONY: skeleton-chroot
skeleton-chroot: skeleton build/tinycc/.git scripts/make-target.sh
	@echo "==> chroot tcc pass3"
	cp scripts/make-target.sh rootfs/tmp/make-target.sh
	rm -rf rootfs/tmp/tinycc && cp -a build/tinycc rootfs/tmp/tinycc
	sudo mount -v --bind /dev rootfs/dev
	sudo mount -vt devpts devpts -o gid=5,mode=0620 rootfs/dev/pts
	sudo mount -vt proc proc rootfs/proc
	sudo mount -vt sysfs sysfs rootfs/sys
	sudo chroot rootfs /bin/env -i HOME=/home/root PATH=/bin /tmp/make-target.sh \
		|| { sudo scripts/umounts.sh; exit 1; }
	sudo scripts/umounts.sh

# Host-only bits left after packaging the rootfs.
define finish_rootfs
	rm -f rootfs/bin/musl-gcc rootfs/lib/musl-gcc.specs \
		rootfs/lib/ld-linux-$(MUSL_ARCH).so.1
	-command -v sudo >/dev/null && sudo scripts/umounts.sh >/dev/null || true
endef

define POST_INSTALL_RULE
.PHONY: post-install-$(1)
post-install-$(1): skeleton-chroot rootfs-home-pkg
	@echo "==> post-install ($(1))"
	$(if $(wildcard scripts/post-install-$(1).sh),cd build && export outdir=$(CURDIR)/rootfs PLATFORM=$(1) linuxver=$(LINUXVER) linux_src=$(CURDIR)/build/linux-$(LINUXVER) && . $(CURDIR)/scripts/post-install-$(1).sh)
	@$(MAKE) rootfs-home-pkg
	$(finish_rootfs)
endef
$(foreach p,$(filter-out radxacm5io,$(PLATFORMS)),$(eval $(call POST_INSTALL_RULE,$(p))))

# --- platform tarballs ------------------------------------------------------

RADXA_BUILDER_PKGS := build-essential gcc g++ make bison flex bc kmod cpio rsync \
	gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
	libncurses-dev libelf-dev dwarves \
	git curl ca-certificates xz-utils bzip2 \
	python3 python3-dev python3-setuptools python3-pyelftools \
	device-tree-compiler u-boot-tools swig libgnutls28-dev \
	dosfstools e2fsprogs fdisk util-linux parted gdisk musl-tools xxd

define PLAT_RULE
.PHONY: $(1)
$(1): rootfs-$(1).tar.xz

rootfs-$(1).tar.xz: force-platform-$(1) configs/$(1)-linux.config configs/$(1)-toybox.config \
		rootfs/bin/init $(ROOTFS_ETC) rootfs-home-pkg
	@echo "==> tar rootfs-$(1).tar.xz"
	cd rootfs && tar cfJ $(CURDIR)/rootfs-$(1).tar.xz .
	@echo "Build complete: rootfs-$(1).tar.xz"

.PHONY: force-platform-$(1)
force-platform-$(1):
	@$(MAKE) PLATFORM=$(1) post-install-$(1)
	@$(MAKE) rootfs-home-pkg
endef
$(foreach p,$(filter-out radxacm5io,$(PLATFORMS)),$(eval $(call PLAT_RULE,$(p))))

# --- radxa boot files + image -----------------------------------------------

RTL_FW_SRC := $(wildcard linux-firmware/rtlwifi/rtl8188eufw.bin)
RTL_FW_DST := $(patsubst linux-firmware/%,rootfs/lib/firmware/%,$(RTL_FW_SRC))

ifneq ($(RTL_FW_SRC),)
rootfs/lib/firmware/rtlwifi/rtl8188eufw.bin: linux-firmware/rtlwifi/rtl8188eufw.bin
	mkdir -p $(dir $@)
	cp -f $< $@
endif

rootfs/boot/extlinux/extlinux.conf: rootfs/boot/Image $(RTL_FW_DST)
	mkdir -p $(dir $@) rootfs/lib/firmware/rtlwifi rootfs/bin
	printf '%s\n' \
		'DEFAULT lin0' 'TIMEOUT 10' 'MENU TITLE lin0 CM5 IO' \
		'LABEL lin0' '	MENU LABEL lin0 root=LABEL=$(RADXA_ROOT_LABEL)' \
		'	LINUX /boot/Image' '	FDT /boot/$(RADXA_DTB)' \
		'	APPEND $(RADXA_CMN) root=LABEL=$(RADXA_ROOT_LABEL) rootfstype=ext4' \
		'LABEL lin0-mmc0' '	MENU LABEL lin0 root=/dev/mmcblk0p3' \
		'	LINUX /boot/Image' '	FDT /boot/$(RADXA_DTB)' \
		'	APPEND $(RADXA_CMN) root=/dev/mmcblk0p3 rootfstype=ext4' \
		> $@

rootfs/boot/fat-extlinux/extlinux.conf: rootfs/boot/Image
	mkdir -p $(dir $@)
	printf '%s\n' \
		'DEFAULT lin0' 'TIMEOUT 10' 'MENU TITLE lin0 CM5 IO FAT' \
		'LABEL lin0' '	MENU LABEL lin0' \
		'	LINUX /Image' '	FDT /$(RADXA_DTB)' \
		'	APPEND $(RADXA_CMN) root=LABEL=$(RADXA_ROOT_LABEL) rootfstype=ext4' \
		> $@

rootfs/boot/lin0.id:
	mkdir -p $(dir $@)
	printf 'lin0 radxa-cm5-io\n' > $@

.PHONY: radxacm5io-bootfiles
radxacm5io-bootfiles: rootfs/boot/extlinux/extlinux.conf \
	rootfs/boot/fat-extlinux/extlinux.conf rootfs/boot/lin0.id \
	rootfs/lib/firmware/regulatory.db $(RTL_FW_DST)

.PHONY: post-install-radxacm5io
post-install-radxacm5io: skeleton radxacm5io-bootfiles rootfs-home-pkg \
		$(LINUX_HEADERS) rootfs/bin/toybox rootfs/bin/tcc \
		$(ROOTFS_TLS_LIBS) $(ROOTFS_TLS_HDRS)
	@echo "==> post-install (radxacm5io)"
	@test -f rootfs/include/tls.h
	@ls -lh rootfs/bin/toybox rootfs/bin/tcc rootfs/bin/hotplugd \
		rootfs/include/tls.h $(ROOTFS_TLS_LIBS)
	$(finish_rootfs)

# Build the arm64 toolchain image from an inline Dockerfile (Docker layer-caches repeats).
.PHONY: radxacm5io-builder
radxacm5io-builder:
	docker info >/dev/null
	@echo "==> $(RADXA_BUILDER)"
	@printf '%s\n' \
		'FROM debian:bookworm-slim' \
		'ENV DEBIAN_FRONTEND=noninteractive' \
		'RUN apt-get update && apt-get install -y --no-install-recommends \' \
		' $(RADXA_BUILDER_PKGS) \' \
		' && rm -rf /var/lib/apt/lists/*' \
		'WORKDIR /work' \
	| docker build --platform linux/arm64 -t "$(RADXA_BUILDER)" -

# On macOS/host != Linux, build the whole rootfs inside the aarch64 builder image.
.PHONY: radxacm5io-rootfs
ifneq ($(HOST_OS),Linux)
radxacm5io-rootfs: radxacm5io-builder
	docker run --rm --platform linux/arm64 \
		-e RADXA_LINUXVER="$(RADXA_LINUXVER)" \
		-v "$(CURDIR):/work" -w /work \
		"$(RADXA_BUILDER)" \
		make PLATFORM=radxacm5io RADXA_LINUXVER="$(RADXA_LINUXVER)" post-install-radxacm5io
else
radxacm5io-rootfs:
	@$(MAKE) PLATFORM=radxacm5io post-install-radxacm5io
endif

# Privileged p3 format/mount/rsync — piped into `docker run ... bash -s` (no script file).
RADXA_P3_PKGS := util-linux e2fsprogs rsync

.PHONY: radxacm5io-img
radxacm5io-img: $(RADXA_OFFICIAL) radxacm5io-rootfs
	@echo "==> hybrid image lin0-radxacm5io.img (p3=$(RADXA_P3_MB)MiB)"
	@P3_SECTS=$$(($(RADXA_P3_MB)*1024*1024/512)); \
	HEAD_BYTES=$$(($(RADXA_P3_LBA)*512)); \
	TOTAL_BYTES=$$((($(RADXA_P3_LBA)+P3_SECTS)*512)); \
	rm -f lin0-radxacm5io.img; \
	dd if="$(RADXA_OFFICIAL)" of=lin0-radxacm5io.img bs=4M \
		count=$$(((HEAD_BYTES+4194303)/4194304)) status=none; \
	python3 -c "p='lin0-radxacm5io.img';h=$$HEAD_BYTES;t=$$TOTAL_BYTES;f=open(p,'r+b');f.truncate(h);f.truncate(t);f.close();print('image bytes',t)"; \
	python3 scripts/gpt-resize-p3.py lin0-radxacm5io.img $(RADXA_P3_LBA) $$P3_SECTS; \
	printf '%s\n' \
		'set -euo pipefail' \
		'export DEBIAN_FRONTEND=noninteractive' \
		'apt-get update -qq && apt-get install -y -qq $(RADXA_P3_PKGS) >/dev/null' \
		'IMG=/work/lin0-radxacm5io.img' \
		'ROOTFS=/work/rootfs' \
		'MNT=/mnt/p3' \
		'mkdir -p "$$MNT"' \
		'OFF=$$((P3_START_LBA*512))' \
		'SZ=$$((P3_SECTS*512))' \
		'LOOP=$$(losetup --find --show -o "$$OFF" --sizelimit "$$SZ" "$$IMG")' \
		'LOOP_SZ=$$(blockdev --getsize64 "$$LOOP")' \
		'echo "p3 loop $$LOOP_SZ bytes (want $$SZ)"' \
		'test "$$LOOP_SZ" -eq "$$SZ"' \
		'mkfs.ext4 -F -b 4096 -L "$$ROOT_LABEL" -U "$$ROOT_UUID" "$$LOOP"' \
		'mount "$$LOOP" "$$MNT"' \
		'rsync -aH "$$ROOTFS"/ "$$MNT"/' \
		'chmod 755 "$$MNT/lib/libc.so"' \
		'ln -sfn libc.so "$$MNT/lib/ld-musl-aarch64.so.1"' \
		'rm -f "$$MNT/lib/ld-linux-"* "$$MNT/lib/ld-linux.so.2"' \
		'mkdir -p "$$MNT/bin" "$$MNT/boot/extlinux" "$$MNT/proc" "$$MNT/sys" "$$MNT/dev" "$$MNT/tmp" "$$MNT/run"' \
		'chmod 1777 "$$MNT/tmp"' \
		'install -m 0755 /work/init /work/hotplugd "$$MNT/bin/"' \
		'test -f "$$MNT/include/tls.h" && test -f "$$MNT/bin/hotplugd"' \
		'sync' \
		'umount "$$MNT"' \
		'losetup -d "$$LOOP"' \
		'echo p3 done' \
	| docker run --rm -i --privileged \
		-e P3_START_LBA="$(RADXA_P3_LBA)" -e P3_SECTS="$$P3_SECTS" \
		-e ROOT_UUID="$(RADXA_ROOT_UUID)" -e ROOT_LABEL="$(RADXA_ROOT_LABEL)" \
		-v "$(CURDIR):/work" debian:bookworm-slim \
		bash -s
	@ls -lh lin0-radxacm5io.img

.PHONY: radxacm5io
radxacm5io: radxacm5io-img
	@echo "==> tar rootfs-radxacm5io.tar.xz"
	cd rootfs && tar cfJ $(CURDIR)/rootfs-radxacm5io.tar.xz .
	@ls -lh lin0-radxacm5io.img rootfs-radxacm5io.tar.xz
	@echo "Flash: rkdeveloptool wl 0 lin0-radxacm5io.img"

# --- meta -------------------------------------------------------------------

.PHONY: all help list clean distclean umount-rootfs mount-rootfs rpizero-img

rpizero-img: rootfs-rpizero.tar.xz
	scripts/mkimg-rpizero.sh

ifeq ($(filter $(PLATFORM),$(PLATFORMS)),)
all:
	@echo "Host arch is $(HOST_ARCH); pick an explicit platform:"
	@echo "  $(PLATFORMS)"
	@exit 1
else
all: $(PLATFORM)
endif

help:
	@echo "lin0 — each platform is a Make target."
	@echo "  make <platform>   one of: $(PLATFORMS)"
	@echo "  make radxacm5io   rootfs tarball + hybrid image"
	@echo "  make rpizero-img  SD image from rootfs-rpizero.tar.xz"
	@echo "  Edit etc/*, init, configs/* — then rebuild."

list:
	@echo "Platforms: $(PLATFORMS)"

umount-rootfs:
	-sudo scripts/umounts.sh >/dev/null

mount-rootfs:
	sudo scripts/mounts.sh

clean: umount-rootfs
	rm -rf rootfs
	rm -f rootfs-*.tar.xz lin0-*.img lin0-*.tar.xz build/cacert.pem build/cacert.pem.tmp*

distclean: umount-rootfs
	rm -rf build rootfs
	rm -f rootfs-*.tar.xz lin0-*.img lin0-*.tar.xz

.DEFAULT_GOAL := all
