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
WOLFSSLVER  := 5.7.6
CURLVER     := 8.4.0
BEARSSLVER  := 0.6
LIBTLS_BEARSSL_MAJOR := 33

MUSLURL    := https://musl.libc.org/releases/musl-$(MUSLVER).tar.gz
LINUXURL   := https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$(LINUXVER).tar.xz
TCCURL     := https://repo.or.cz/tinycc.git
TOYBOXURL  := https://github.com/landley/toybox.git
MKSHURL    := http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-$(MKSHVER).tgz
MAKEURL    := https://ftp.gnu.org/gnu/make/make-$(MAKEVER).tar.gz
WOLFSSLURL := https://github.com/wolfSSL/wolfssl/archive/refs/tags/v$(WOLFSSLVER)-stable.tar.gz
CURLURL    := https://curl.se/tiny/tiny-curl-$(CURLVER).tar.gz
BEARSSLURL := https://bearssl.org/bearssl-$(BEARSSLVER).tar.gz
LIBTLS_BEARSSL_URL := https://github.com/michaelforney/libtls-bearssl.git
REGDBURL   := https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/plain
CACERT_URL := https://curl.se/ca/cacert.pem
# Mozilla CA bundle via curl.se (mk-ca-bundle). Bump with the file.
CACERT_SHA256 := 86a1f3366afac7c6f8ae9f3c779ac221129328c43f0ab2b8817eb2f362a5025c
TLS_CFLAGS := -Os -fPIC -ffunction-sections -fdata-sections \
	-fno-asynchronous-unwind-tables -fno-unwind-tables
TLS_INCLUDE := $(CURDIR)/build/tls-include
ROOTFS_LIBBEARSSL := rootfs/lib/libbearssl.so.$(BEARSSLVER)
ROOTFS_LIBTLS := rootfs/lib/libtls.so.$(LIBTLS_BEARSSL_MAJOR)
ROOTFS_TLS_LIBS := $(ROOTFS_LIBBEARSSL) $(ROOTFS_LIBTLS)

PLATFORMS  := aarch64 x86_64 hpelitedesk pinebookpro rpi3bplus rpi5 rpizero radxacm5io
AARCH64_PLATS := aarch64 arm64 radxacm5io rpi3bplus rpi5 pinebookpro rpi-cm5io m1mac

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
  HOST_ARCH := aarch64
endif
HOST_OS := $(shell uname -s)

PLATFORM ?= $(HOST_ARCH)
ifeq ($(PLATFORM),arm64)
  PLATFORM := aarch64
endif
ifneq ($(filter $(PLATFORM),radxa radxa-cm5 radxa-cm5-io radxa_cm5 cm5io cm5-io),)
  PLATFORM := radxacm5io
endif
ifneq ($(filter $(PLATFORM),rpi-zero rpi-zero-w rpizero-w rpi0 rpi0w zerow),)
  PLATFORM := rpizero
endif

export outdir := $(CURDIR)/rootfs
export PLATFORM

RADXA_LINUXVER   ?= master
RADXA_P3_MB      ?= 128
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

SKIP_CHROOT_radxacm5io := 1
POST_TARGET_radxacm5io := radxacm5io-postinstall
TOYBOX_CFLAGS := -Os -fPIE -I$(TLS_INCLUDE) $(TLS_CFLAGS)
TOYBOX_LDFLAGS = -pie -L$(CURDIR)/rootfs/lib -Wl,--gc-sections -Wl,-rpath,/lib \
	-ltls -lbearssl -Wl,-dynamic-linker,/lib/$(MUSL_LDSONAME)
TOYBOX_STRIP := strip -s -R .note -R .comment

ETC_SRC := $(shell find etc \( -type f -o -type l \) ! -path 'etc/ssl/*')
ROOTFS_ETC_SSL := rootfs/etc/ssl/cert.pem rootfs/etc/ssl/certs/ca-certificates.crt
ROOTFS_ETC := $(patsubst etc/%,rootfs/etc/%,$(ETC_SRC)) $(ROOTFS_ETC_SSL)

INIT_COMMON := rootfs/bin/toybox $(ROOTFS_MUSL_LD) $(ROOTFS_TLS_LIBS) $(ROOTFS_ETC)
INIT_DEPS = rootfs/bin/cc $(INIT_COMMON)
INIT_DEPS_radxacm5io = rootfs/bin/musl-gcc rootfs/boot/Image $(INIT_COMMON)
init_deps = $(or $(INIT_DEPS_$(PLATFORM)),$(INIT_DEPS))

POST_EXTRA = rootfs/lib/libwolfssl.a rootfs/lib/libcurl.so
POST_EXTRA_radxacm5io = rootfs/lib/firmware/regulatory.db
post_extra = $(or $(POST_EXTRA_$(1)),$(POST_EXTRA))

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

rootfs/bin/init: init $(init_deps)
	mkdir -p $(dir $@) rootfs/home/root rootfs/dev/pts \
		rootfs/proc rootfs/sys rootfs/tmp rootfs/var/run rootfs/run
	cp $< $@
	chmod +x $@

# --- sources under build/ ---------------------------------------------------

define fetch_tar
build/$(1):
	mkdir -p build
	curl -fsSL "$(2)" | tar xz -C build
endef
$(eval $(call fetch_tar,musl-$(MUSLVER)/configure,$(MUSLURL)))
$(eval $(call fetch_tar,make-$(MAKEVER)/configure,$(MAKEURL)))
$(eval $(call fetch_tar,mksh/Build.sh,$(MKSHURL)))
$(eval $(call fetch_tar,wolfssl-$(WOLFSSLVER)/configure,$(WOLFSSLURL)))
$(eval $(call fetch_tar,tiny-curl-$(CURLVER)/configure,$(CURLURL)))
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

$(ROOTFS_LIBBEARSSL): build/bearssl-$(BEARSSLVER)/Makefile rootfs/bin/musl-gcc
	@echo "==> bearssl ($(BEARSSLVER))"
	mkdir -p rootfs/lib $(TLS_INCLUDE)
	$(MAKE) -C build/bearssl-$(BEARSSLVER) CC=$(PLAT_CC) \
		CFLAGS="-std=c99 -Wall $(TLS_CFLAGS) -I src -I inc" build/libbearssl.a
	rm -rf $@.tmp && mkdir $@.tmp && (cd $@.tmp && ar x $(CURDIR)/build/bearssl-$(BEARSSLVER)/build/libbearssl.a)
	$(PLAT_CC) -shared -Wl,-soname,libbearssl.so.0 -o $@ $@.tmp/*.o -Wl,--gc-sections
	rm -rf $@.tmp && $(TOYBOX_STRIP) $@
	ln -sfn libbearssl.so.$(BEARSSLVER) rootfs/lib/libbearssl.so.0
	ln -sfn libbearssl.so.0 rootfs/lib/libbearssl.so
	cp -f build/bearssl-$(BEARSSLVER)/inc/*.h $(TLS_INCLUDE)/

$(ROOTFS_LIBTLS): build/libtls-bearssl/.git $(ROOTFS_LIBBEARSSL)
	@echo "==> libtls-bearssl"
	$(MAKE) -C build/libtls-bearssl clean >/dev/null 2>&1 || true
	rm -f build/libtls-bearssl/config.mk build/libtls-bearssl/*.o \
		build/libtls-bearssl/compat/*.o build/libtls-bearssl/libtls.a
	printf '%s\n' 'CC=$(PLAT_CC)' \
		'CFLAGS=-Wall $(TLS_CFLAGS) -I. -I$(TLS_INCLUDE) -D_GNU_SOURCE -DLIBRESSL_INTERNAL' \
		'LDFLAGS=-L$(CURDIR)/rootfs/lib' 'LDLIBS=-lbearssl' \
		> build/libtls-bearssl/config.mk
	$(MAKE) -C build/libtls-bearssl libtls.a
	mkdir -p rootfs/lib $(TLS_INCLUDE)
	rm -rf $@.tmp && mkdir $@.tmp && (cd $@.tmp && ar x $(CURDIR)/build/libtls-bearssl/libtls.a)
	$(PLAT_CC) -shared -Wl,-soname,libtls.so.$(LIBTLS_BEARSSL_MAJOR) -o $@ \
		$@.tmp/*.o -L$(CURDIR)/rootfs/lib -lbearssl -lpthread -Wl,--gc-sections
	rm -rf $@.tmp && $(TOYBOX_STRIP) $@
	ln -sfn libtls.so.$(LIBTLS_BEARSSL_MAJOR) rootfs/lib/libtls.so
	cp -f build/libtls-bearssl/tls.h $(TLS_INCLUDE)/
	strings $@ | grep -q '/etc/ssl/cert.pem'

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
	ln -sfn libc.so rootfs/lib/ld-linux-$(MUSL_ARCH).so.1
	ln -sf ../lib/libc.so rootfs/bin/ldd
	ln -sf ../lib/libc.so rootfs/bin/ld

# headers + boot image are real outputs of the platform kernel build
LINUX_HEADERS = rootfs/include/linux/version.h
BOOT_IMAGE = rootfs/boot/vmlinuz
BOOT_IMAGE_rpizero = rootfs/boot/kernel.img
BOOT_IMAGE_radxacm5io = rootfs/boot/Image
boot_image = $(or $(BOOT_IMAGE_$(PLATFORM)),$(BOOT_IMAGE))

rootfs/bin/toybox: configs/$(PLATFORM)-toybox.config build/toybox/.git \
		rootfs/bin/musl-gcc $(ROOTFS_MUSL_LD) $(LINUX_HEADERS) $(boot_image) \
		$(ROOTFS_TLS_LIBS)
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

rootfs/bin/ar:
	mkdir -p $(dir $@)
	printf '%s\n' '#!/bin/sh' 'cc -ar $$@' > $@
	chmod +x $@

rootfs/bin/cc: rootfs/bin/make rootfs/bin/sh build/tinycc/.git \
		$(LINUX_HEADERS) $(boot_image) rootfs/lib/libc.so
	@echo "==> tcc pass1"
	rm -f rootfs/lib/musl-gcc.specs rootfs/bin/musl-gcc
	cd build/tinycc && ./configure --prefix=/ \
		--sysincludepaths=$(CURDIR)/rootfs/include --libpaths=$(CURDIR)/rootfs/lib \
		--tccdir=/lib --crtprefix=$(CURDIR)/rootfs/lib --elfinterp=$(CURDIR)/rootfs/lib/libc.so \
		--config-static --config-bcheck=no --disable-rpath --config-musl
	CC="$(PLAT_CC) -static --no-pie" $(MAKE) -C build/tinycc
	$(MAKE) -C build/tinycc DESTDIR=$(CURDIR)/rootfs install
	printf '%s\n' '#!/bin/sh' 'tcc -ar $$@' > rootfs/bin/ar && chmod +x rootfs/bin/ar
	@echo "==> tcc pass2"
	rm -rf build/tinycc && git clone "$(TCCURL)" build/tinycc
	cd build/tinycc && ./configure --prefix=/ \
		--sysincludepaths=$(CURDIR)/rootfs/include:/include --libpaths=$(CURDIR)/rootfs/lib:/lib \
		--crtprefix=/lib --ar="$(CURDIR)/rootfs/bin/tcc -ar" --elfinterp=/lib/libc.so \
		--config-static --config-bcheck=no --disable-rpath --config-musl
	CC="$(CURDIR)/rootfs/bin/tcc -static" $(MAKE) -C build/tinycc
	$(MAKE) -C build/tinycc DESTDIR=$(CURDIR)/rootfs install
	mv rootfs/bin/tcc $@
	printf '%s\n' '#!/bin/sh' 'cc -ar $$@' > rootfs/bin/ar && chmod +x rootfs/bin/ar

rootfs/lib/libwolfssl.a: rootfs/bin/cc build/wolfssl-$(WOLFSSLVER)/configure
	@echo "==> wolfssl"
	cd build/wolfssl-$(WOLFSSLVER) && ./configure --prefix=$(CURDIR)/rootfs \
		--host=x86_64-linux-gnu --target=x86_64-linux-musl --enable-opensslextra
	$(MAKE) -C build/wolfssl-$(WOLFSSLVER) && $(MAKE) -C build/wolfssl-$(WOLFSSLVER) install

rootfs/lib/libcurl.so: rootfs/lib/libwolfssl.a build/tiny-curl-$(CURLVER)/configure
	@echo "==> tinycurl"
	cd build/tiny-curl-$(CURLVER) && ./configure --prefix=$(CURDIR)/rootfs \
		--host=x86_64-linux-gnu --target=x86_64-linux-musl \
		--with-wolfssl --disable-libcurl-option --disable-static
	$(MAKE) -C build/tiny-curl-$(CURLVER) && $(MAKE) -C build/tiny-curl-$(CURLVER) install

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
	mkdir -p build/dtbs build/kheaders build/kheaders-staging \
		rootfs/boot rootfs/usr/include rootfs/include/linux
	cd build/linux-src && cp $(CURDIR)/configs/radxacm5io-linux.config .config
	$(MAKE) -C build/linux-src ARCH=arm64 olddefconfig
	$(MAKE) -C build/linux-src ARCH=arm64 -j$$(nproc) Image modules dtbs
	INSTALL_MOD_PATH=$(CURDIR)/rootfs $(MAKE) -C build/linux-src ARCH=arm64 modules_install
	cp -f build/linux-src/arch/arm64/boot/Image rootfs/boot/Image
	cp -f build/linux-src/arch/arm64/boot/dts/rockchip/$(RADXA_DTB) rootfs/boot/$(RADXA_DTB)
	cp -f build/linux-src/arch/arm64/boot/dts/rockchip/$(RADXA_DTB) build/dtbs/
	$(MAKE) -C build/linux-src ARCH=arm64 headers_install
	cp -f build/linux-src/usr/include/linux/version.h rootfs/include/linux/version.h
	cd build/linux-src/usr/include && tar cf - . | tar xf - -C $(CURDIR)/rootfs/usr/include
	rm -rf build/kheaders && mkdir -p build/kheaders
	cd build/linux-src/usr/include && tar cf - . | tar xf - -C $(CURDIR)/build/kheaders
	strings rootfs/boot/$(RADXA_DTB) | grep -q haoyu,hym8563

else ifeq ($(PLATFORM),rpizero)
rootfs/boot/kernel.img $(LINUX_HEADERS): configs/rpizero-linux.config \
		rootfs/bin/musl-gcc build/linux-$(LINUXVER)/Makefile
	@echo "==> linux (rpizero)"
	mkdir -p rootfs/boot
	cp configs/rpizero-linux.config build/linux-$(LINUXVER)/.config
	CC=$(CURDIR)/rootfs/bin/musl-gcc ARCH=arm $(MAKE) -C build/linux-$(LINUXVER) olddefconfig
	CC=$(CURDIR)/rootfs/bin/musl-gcc ARCH=arm $(MAKE) -C build/linux-$(LINUXVER)
	CC=$(CURDIR)/rootfs/bin/musl-gcc ARCH=arm INSTALL_HDR_PATH=$(CURDIR)/rootfs \
		INSTALL_PATH=$(CURDIR)/rootfs/boot INSTALL_MOD_PATH=$(CURDIR)/rootfs \
		$(MAKE) -C build/linux-$(LINUXVER) zImage dtbs modules headers_install modules_install
	cp -f build/linux-$(LINUXVER)/arch/arm/boot/zImage rootfs/boot/kernel.img
	-cp -f build/linux-$(LINUXVER)/arch/arm/boot/dts/broadcom/bcm2835-rpi-zero*.dtb rootfs/boot/
	-cp -f build/linux-$(LINUXVER)/arch/arm/boot/dts/bcm2835-rpi-zero*.dtb rootfs/boot/

else
rootfs/boot/vmlinuz $(LINUX_HEADERS): configs/$(PLATFORM)-linux.config \
		rootfs/bin/musl-gcc build/linux-$(LINUXVER)/Makefile
	@echo "==> linux ($(PLATFORM))"
	cp configs/$(PLATFORM)-linux.config build/linux-$(LINUXVER)/.config
	CC=$(CURDIR)/rootfs/bin/musl-gcc $(MAKE) -C build/linux-$(LINUXVER) olddefconfig
	CC=$(CURDIR)/rootfs/bin/musl-gcc $(MAKE) -C build/linux-$(LINUXVER)
	CC=$(CURDIR)/rootfs/bin/musl-gcc INSTALL_HDR_PATH=$(CURDIR)/rootfs INSTALL_PATH=$(CURDIR)/rootfs/boot \
		INSTALL_MOD_PATH=$(CURDIR)/rootfs \
		$(MAKE) -C build/linux-$(LINUXVER) install headers_install modules_install
endif

# --- skeleton / post-install ------------------------------------------------

.PHONY: skeleton
skeleton: rootfs/bin/init $(init_deps)

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

# Platforms that run the in-rootfs tcc pass use skeleton-chroot; others use skeleton.
SKELETON_radxacm5io = skeleton
SKELETON_ = skeleton-chroot
skeleton_for = $(or $(SKELETON_$(1)),$(SKELETON_))

define POST_INSTALL_RULE
.PHONY: post-install-$(1)
post-install-$(1): $$(call skeleton_for,$(1)) $$(call post_extra,$(1))
	@echo "==> post-install ($(1))"
	$(if $(wildcard scripts/post-install-$(1).sh),cd build && export outdir=$(CURDIR)/rootfs PLATFORM=$(1) linuxver=$(LINUXVER) linux_src=$(CURDIR)/build/linux-$(LINUXVER) && . $(CURDIR)/scripts/post-install-$(1).sh)
	$(if $(POST_TARGET_$(1)),$$(MAKE) $(POST_TARGET_$(1)))
	-command -v sudo >/dev/null && sudo scripts/umounts.sh >/dev/null || true
endef
$(foreach p,$(PLATFORMS),$(eval $(call POST_INSTALL_RULE,$(p))))

# --- platform tarballs ------------------------------------------------------

# Cached arm64 Debian image for macOS builds (no separate Dockerfile).
RADXA_BUILDER_PKGS := build-essential gcc g++ make bison flex bc kmod cpio rsync \
	gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
	libncurses-dev libelf-dev dwarves \
	git curl ca-certificates xz-utils bzip2 \
	python3 python3-dev python3-setuptools python3-pyelftools \
	device-tree-compiler u-boot-tools swig libgnutls28-dev \
	dosfstools e2fsprogs fdisk util-linux parted gdisk musl-tools xxd

ifneq ($(HOST_OS),Linux)
define run_platform_radxacm5io
	@$(MAKE) radxacm5io-builder
	docker run --rm --platform linux/arm64 \
		-e RADXA_LINUXVER="$(RADXA_LINUXVER)" \
		-v "$(CURDIR):/work" -w /work \
		"$(RADXA_BUILDER)" \
		make PLATFORM=radxacm5io RADXA_LINUXVER="$(RADXA_LINUXVER)" post-install-radxacm5io
endef
endif

define PLAT_RULE
.PHONY: $(1)
$(1): rootfs-$(1).tar.xz

rootfs-$(1).tar.xz: force-platform-$(1) configs/$(1)-linux.config configs/$(1)-toybox.config \
		rootfs/bin/init $(ROOTFS_ETC)
	@echo "==> tar rootfs-$(1).tar.xz"
	cd rootfs && tar cfJ $(CURDIR)/rootfs-$(1).tar.xz .
	@echo "Build complete: rootfs-$(1).tar.xz"

.PHONY: force-platform-$(1)
force-platform-$(1):
	$(if $(run_platform_$(1)),$(run_platform_$(1)),@$(MAKE) PLATFORM=$(1) post-install-$(1))
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

.PHONY: radxacm5io-postinstall
radxacm5io-postinstall: skeleton radxacm5io-bootfiles
	@echo "==> [radxacm5io] post-install"
	@ls -lh rootfs/bin/toybox $(ROOTFS_TLS_LIBS)

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
radxacm5io-rootfs:
	$(run_platform_radxacm5io)
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
	python3 -c "p='lin0-radxacm5io.img';h=$$HEAD_BYTES;t=$$TOTAL_BYTES;f=open(p,'r+b');f.truncate(h);f.seek(t-1);f.write(b'\\0');f.close();print('image bytes',t)"; \
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
		'mkfs.ext4 -F -L "$$ROOT_LABEL" -U "$$ROOT_UUID" "$$LOOP"' \
		'mount "$$LOOP" "$$MNT"' \
		'rsync -aH "$$ROOTFS"/ "$$MNT"/' \
		'if [ -f "$$MNT/lib/libc.so" ]; then chmod 755 "$$MNT/lib/libc.so"; ln -sfn libc.so "$$MNT/lib/ld-musl-aarch64.so.1"; fi' \
		'mkdir -p "$$MNT/bin" "$$MNT/boot/extlinux" "$$MNT/proc" "$$MNT/sys" "$$MNT/dev" "$$MNT/tmp" "$$MNT/run"' \
		'install -m 0755 /work/init "$$MNT/bin/init"' \
		'install -m 0644 "$$ROOTFS/boot/Image" "$$MNT/boot/Image"' \
		'install -m 0644 "$$ROOTFS/boot/$(RADXA_DTB)" "$$MNT/boot/$(RADXA_DTB)"' \
		'printf "%s\n" "default emmc" "timeout 20" "menu title lin0 CM5 IO" "label emmc" "  menu label root=/dev/mmcblk0p3" "  linux /boot/Image" "  fdt /boot/$(RADXA_DTB)" "  append root=/dev/mmcblk0p3 $(RADXA_CMN) rootfstype=ext4" "label bylabel" "  menu label root=LABEL=$(RADXA_ROOT_LABEL)" "  linux /boot/Image" "  fdt /boot/$(RADXA_DTB)" "  append root=LABEL=$(RADXA_ROOT_LABEL) $(RADXA_CMN) rootfstype=ext4" > "$$MNT/boot/extlinux/extlinux.conf"' \
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

# --- aliases / meta ---------------------------------------------------------

.PHONY: all help list clean distclean umount-rootfs mount-rootfs
.PHONY: arm64 radxa radxa-cm5 radxa-cm5-io cm5io cm5-io
.PHONY: rpi-zero rpi-zero-w rpizero-w rpi0 rpi0w zerow rpizero-img

arm64: aarch64
radxa radxa-cm5 radxa-cm5-io cm5io cm5-io: radxacm5io
rpi-zero rpi-zero-w rpizero-w rpi0 rpi0w zerow: rpizero
rpizero-img: rootfs-rpizero.tar.xz
	scripts/mkimg-rpizero.sh

all: $(PLATFORM)

help:
	@echo "lin0 — literal path targets, pattern copies from etc/ and init."
	@echo "  make <platform>   one of: $(PLATFORMS)"
	@echo "  make radxacm5io   rootfs tarball + hybrid image"
	@echo "  Edit etc/*, init, configs/* — then rebuild."

list:
	@echo "Platforms: $(PLATFORMS)"

umount-rootfs:
	-sudo scripts/umounts.sh >/dev/null

mount-rootfs:
	sudo scripts/mounts.sh

clean: umount-rootfs
	rm -rf rootfs build/tls-include
	rm -f rootfs-*.tar.xz build/cacert.pem build/cacert.pem.tmp*

distclean: umount-rootfs
	rm -rf build rootfs
	rm -f rootfs-*.tar.xz lin0-*.img lin0-*.tar.xz

.DEFAULT_GOAL := all
