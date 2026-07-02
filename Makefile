# lin0 — Makefile-only builds (real file prerequisites, no stamps)
#
#   make                 # host arch -> rootfs-<arch>.tar.xz
#   make x86_64          # explicit platform
#   make list | help | clean | distclean
#
# Make rebuilds a target when it is missing or older than any prerequisite.
# Radxa: make radxacm5io  (RADXA_LINUXVER, RADXA_P3_MB, OFFICIAL_IMG / RADXA_OFFICIAL)

SHELL := /bin/sh
.SHELLFLAGS := -ec

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD     := $(REPO_ROOT)/build
ROOTFS    := $(REPO_ROOT)/rootfs
CONFIGS   := $(REPO_ROOT)/configs
SCRIPTS   := $(REPO_ROOT)/scripts

MUSLVER    := 1.2.5
LINUXVER   := 6.13.3
MAKEVER    := 4.4.1
MKSHVER    := R59c
WOLFSSLVER := 5.7.6
CURLVER    := 8.4.0

MUSLURL    := https://musl.libc.org/releases/musl-$(MUSLVER).tar.gz
LINUXURL   := https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$(LINUXVER).tar.xz
TCCURL     := https://repo.or.cz/tinycc.git
TOYBOXURL  := https://github.com/landley/toybox.git
MKSHURL    := http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-$(MKSHVER).tgz
MAKEURL    := https://ftp.gnu.org/gnu/make/make-$(MAKEVER).tar.gz
WOLFSSLURL := https://github.com/wolfSSL/wolfssl/archive/refs/tags/v$(WOLFSSLVER)-stable.tar.gz
CURLURL    := https://curl.se/tiny/tiny-curl-$(CURLVER).tar.gz
REGDBURL   := https://git.kernel.org/pub/scm/linux/kernel/git/wens/wireless-regdb.git/plain

PLATFORMS  := aarch64 x86_64 hpelitedesk pinebookpro rpi3bplus rpi5 rpizero radxacm5io
STD_PLATS  := $(filter-out radxacm5io,$(PLATFORMS))

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
  HOST_ARCH := aarch64
endif

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

export outdir := $(ROOTFS)
export PLATFORM

# --- source trees (prereq = configure/Makefile/.git marker files) ------------

MUSL_SRC    := $(BUILD)/musl-$(MUSLVER)
LINUX_SRC   := $(BUILD)/linux-$(LINUXVER)
LINUX_TAR   := $(BUILD)/linux-$(LINUXVER).tar.xz
TOYBOX_SRC  := $(BUILD)/toybox
MAKE_SRC    := $(BUILD)/make-$(MAKEVER)
MKSH_SRC    := $(BUILD)/mksh
TCC_SRC     := $(BUILD)/tinycc
WOLFSSL_SRC := $(BUILD)/wolfssl-$(WOLFSSLVER)
CURL_SRC    := $(BUILD)/tiny-curl-$(CURLVER)

$(BUILD):
	mkdir -p $@

$(MUSL_SRC)/configure: | $(BUILD)
	curl -fsSL "$(MUSLURL)" | tar xz -C $(BUILD)

$(LINUX_TAR): | $(BUILD)
	curl -fsSL -o $@ "$(LINUXURL)"

$(LINUX_SRC)/Makefile: $(LINUX_TAR)
	tar xf $(LINUX_TAR) -C $(BUILD)

$(TOYBOX_SRC)/.git: | $(BUILD)
	git clone "$(TOYBOXURL)" $(TOYBOX_SRC)

$(MAKE_SRC)/configure: | $(BUILD)
	curl -fsSL "$(MAKEURL)" | tar xz -C $(BUILD)

$(MKSH_SRC)/Build.sh: | $(BUILD)
	curl -fsSL "$(MKSHURL)" | tar xz -C $(BUILD)

$(TCC_SRC)/.git: | $(BUILD)
	rm -rf $(TCC_SRC)
	git clone "$(TCCURL)" $(TCC_SRC)

$(WOLFSSL_SRC)/configure: | $(BUILD)
	curl -fsSL "$(WOLFSSLURL)" | tar xz -C $(BUILD)

$(CURL_SRC)/configure: | $(BUILD)
	curl -fsSL "$(CURLURL)" | tar xz -C $(BUILD)

# --- installed artifacts in rootfs/ (what Make actually tracks) -------------

MUSL_GCC   := $(ROOTFS)/bin/musl-gcc
LINUX_HDR  := $(ROOTFS)/include/linux/version.h
TOYBOX_BIN := $(ROOTFS)/bin/toybox
HOST_MAKE  := $(ROOTFS)/bin/make
HOST_SH    := $(ROOTFS)/bin/sh
HOST_CC    := $(ROOTFS)/bin/cc
ROOT_INIT  := $(ROOTFS)/bin/init
WOLFSSL_A  := $(ROOTFS)/lib/libwolfssl.a
CURL_SO    := $(ROOTFS)/lib/libcurl.so
REGDB      := $(ROOTFS)/lib/firmware/regulatory.db

$(REGDB):
	mkdir -p $(dir $@)
	curl -fsSL -o $@ "$(REGDBURL)/regulatory.db"
	curl -fsSL -o $@.p7s "$(REGDBURL)/regulatory.db.p7s"

LINUX_CFG  = $(CONFIGS)/$(1)-linux.config
TOYBOX_CFG = $(CONFIGS)/$(1)-toybox.config
POST_SH    = $(SCRIPTS)/post-install-$(1).sh
LINUX_OK   = $(BUILD)/$(1)/linux.ok
POST_OK    = $(BUILD)/$(1)/post.ok

# musl -> rootfs (shared)
$(MUSL_GCC): $(MUSL_SRC)/configure
	@echo "==> musl"
	mkdir -p $(ROOTFS)
	cd $(MUSL_SRC) && ./configure --prefix=$(ROOTFS) --enable-static
	$(MAKE) -C $(MUSL_SRC)
	$(MAKE) -C $(MUSL_SRC) install

# Per-platform kernel/headers install; $(BUILD)/<plat>/linux.ok records done+config used
# Kernel arch: Pi Zero is 32-bit arm; everything else in-tree is arm64/x86_64 host configs
LINUX_ARCH_rpizero := arm
LINUX_ARCH_DEFAULT :=

define LINUX_RULE
$$(call LINUX_OK,$(1)): $$(call LINUX_CFG,$(1)) $$(LINUX_SRC)/Makefile $$(MUSL_GCC)
	@echo "==> linux ($(1))"
	@mkdir -p $$(dir $$@)
	cp $$(call LINUX_CFG,$(1)) $$(LINUX_SRC)/.config
	@KARCH="$$(LINUX_ARCH_$(1))"; \
	if [ "$(1)" = "rpizero" ]; then KARCH=arm; fi; \
	if [ -n "$$KARCH" ]; then \
		CC=$$(MUSL_GCC) ARCH=$$KARCH $$(MAKE) -C $$(LINUX_SRC) olddefconfig; \
		CC=$$(MUSL_GCC) ARCH=$$KARCH $$(MAKE) -C $$(LINUX_SRC); \
		CC=$$(MUSL_GCC) ARCH=$$KARCH INSTALL_HDR_PATH=$$(ROOTFS) INSTALL_PATH=$$(ROOTFS)/boot \
			INSTALL_MOD_PATH=$$(ROOTFS) $$(MAKE) -C $$(LINUX_SRC) zImage dtbs modules; \
		CC=$$(MUSL_GCC) ARCH=$$KARCH INSTALL_HDR_PATH=$$(ROOTFS) INSTALL_PATH=$$(ROOTFS)/boot \
			INSTALL_MOD_PATH=$$(ROOTFS) $$(MAKE) -C $$(LINUX_SRC) headers_install modules_install; \
		mkdir -p $$(ROOTFS)/boot; \
		cp -f $$(LINUX_SRC)/arch/arm/boot/zImage $$(ROOTFS)/boot/kernel.img 2>/dev/null || true; \
		cp -f $$(LINUX_SRC)/arch/arm/boot/dts/broadcom/bcm2835-rpi-zero*.dtb $$(ROOTFS)/boot/ 2>/dev/null || \
			cp -f $$(LINUX_SRC)/arch/arm/boot/dts/bcm2835-rpi-zero*.dtb $$(ROOTFS)/boot/ 2>/dev/null || true; \
	else \
		CC=$$(MUSL_GCC) $$(MAKE) -C $$(LINUX_SRC); \
		CC=$$(MUSL_GCC) INSTALL_HDR_PATH=$$(ROOTFS) INSTALL_PATH=$$(ROOTFS)/boot \
			INSTALL_MOD_PATH=$$(ROOTFS) $$(MAKE) -C $$(LINUX_SRC) install headers_install modules_install; \
	fi
	@touch $$(LINUX_HDR) $$@
endef
$(foreach p,$(STD_PLATS),$(eval $(call LINUX_RULE,$(p))))

# toybox: depends on active platform linux.ok (set via recursive make PLATFORM=)
$(TOYBOX_BIN): $(call LINUX_OK,$(PLATFORM)) $(TOYBOX_SRC)/.git $(call TOYBOX_CFG,$(PLATFORM)) $(MUSL_GCC)
	@echo "==> toybox ($(PLATFORM))"
	cp $(call TOYBOX_CFG,$(PLATFORM)) $(TOYBOX_SRC)/.config
	CC=$(MUSL_GCC) $(MAKE) -C $(TOYBOX_SRC) LDFLAGS='-static --no-pie' toybox
	$(MAKE) -C $(TOYBOX_SRC) PREFIX=$(ROOTFS)/bin install_flat

$(HOST_MAKE): $(MUSL_GCC) $(MAKE_SRC)/configure
	@echo "==> make"
	CC=$(MUSL_GCC) && cd $(MAKE_SRC) && ./configure --prefix=$(ROOTFS) \
		--host=x86_64-linux-gnu --target=x86_64-linux-musl
	$(MAKE) -C $(MAKE_SRC)
	$(MAKE) -C $(MAKE_SRC) install

$(HOST_SH): $(MUSL_GCC) $(MKSH_SRC)/Build.sh
	@echo "==> mksh"
	CC="$(MUSL_GCC) -static --no-pie" && cd $(MKSH_SRC) && chmod +x Build.sh && ./Build.sh
	install -c -s -m 555 $(MKSH_SRC)/mksh $(HOST_SH)
	mkdir -p $(ROOTFS)/share/man/man1
	-install -c -m 444 $(MKSH_SRC)/mksh.1 $(ROOTFS)/share/man/man1/

# tcc pass1+2 -> final $(HOST_CC); also needs headers from linux step
$(HOST_CC): $(HOST_MAKE) $(HOST_SH) $(call LINUX_OK,$(PLATFORM)) $(TCC_SRC)/.git
	@echo "==> tcc pass1"
	rm -f $(ROOTFS)/lib/musl-gcc.specs $(MUSL_GCC)
	cd $(TCC_SRC) && ./configure --prefix=/ \
		--sysincludepaths=$(ROOTFS)/include --libpaths=$(ROOTFS)/lib \
		--tccdir=/lib --crtprefix=$(ROOTFS)/lib --elfinterp=$(ROOTFS)/lib/libc.so \
		--config-static --config-bcheck=no --disable-rpath --config-musl
	CC="$(MUSL_GCC) -static --no-pie" $(MAKE) -C $(TCC_SRC)
	$(MAKE) -C $(TCC_SRC) DESTDIR=$(ROOTFS) install
	printf '%s\n' '#!/bin/sh' 'tcc -ar $$@' > $(ROOTFS)/bin/ar && chmod +x $(ROOTFS)/bin/ar
	@echo "==> tcc pass2"
	rm -rf $(TCC_SRC) && git clone "$(TCCURL)" $(TCC_SRC)
	cd $(TCC_SRC) && ./configure --prefix=/ \
		--sysincludepaths=$(ROOTFS)/include:/include --libpaths=$(ROOTFS)/lib:/lib \
		--crtprefix=/lib --ar="$(ROOTFS)/bin/tcc -ar" --elfinterp=/lib/libc.so \
		--config-static --config-bcheck=no --disable-rpath --config-musl
	CC="$(ROOTFS)/bin/tcc -static" $(MAKE) -C $(TCC_SRC)
	$(MAKE) -C $(TCC_SRC) DESTDIR=$(ROOTFS) install
	mv $(ROOTFS)/bin/tcc $(HOST_CC)
	printf '%s\n' '#!/bin/sh' 'cc -ar $$@' > $(ROOTFS)/bin/ar && chmod +x $(ROOTFS)/bin/ar

# skeleton + chroot target-tcc
$(ROOT_INIT): $(HOST_CC) $(TOYBOX_BIN) $(REPO_ROOT)/init $(SCRIPTS)/make-target.sh
	@echo "==> skeleton + chroot tcc"
	mkdir -p $(ROOTFS)/bin $(ROOTFS)/etc $(ROOTFS)/home/root $(ROOTFS)/dev/pts \
		$(ROOTFS)/proc $(ROOTFS)/sys $(ROOTFS)/tmp $(ROOTFS)/var/run $(ROOTFS)/run
	cp -a $(REPO_ROOT)/etc/. $(ROOTFS)/etc/
	cp $(REPO_ROOT)/init $(ROOTFS)/bin/init
	mkdir -p $(ROOTFS)/tmp
	cp $(SCRIPTS)/make-target.sh $(ROOTFS)/tmp/make-target.sh
	test -d $(TCC_SRC)/.git || git clone "$(TCCURL)" $(TCC_SRC)
	rm -rf $(ROOTFS)/tmp/tinycc && cp -a $(TCC_SRC) $(ROOTFS)/tmp/tinycc
	sudo mount -v --bind /dev $(ROOTFS)/dev
	sudo mount -vt devpts devpts -o gid=5,mode=0620 $(ROOTFS)/dev/pts
	sudo mount -vt proc proc $(ROOTFS)/proc
	sudo mount -vt sysfs sysfs $(ROOTFS)/sys
	sudo chroot $(ROOTFS) /bin/env -i HOME=/home/root PATH=/bin /tmp/make-target.sh \
		|| ( sudo $(SCRIPTS)/umounts.sh 2>/dev/null; exit 1 )
	sudo $(SCRIPTS)/umounts.sh 2>/dev/null || true

$(WOLFSSL_A): $(HOST_CC) $(WOLFSSL_SRC)/configure
	@echo "==> wolfssl"
	cd $(WOLFSSL_SRC) && ./configure --prefix=$(ROOTFS) \
		--host=x86_64-linux-gnu --target=x86_64-linux-musl --enable-opensslextra
	$(MAKE) -C $(WOLFSSL_SRC) && $(MAKE) -C $(WOLFSSL_SRC) install

$(CURL_SO): $(WOLFSSL_A) $(CURL_SRC)/configure
	@echo "==> tinycurl"
	cd $(CURL_SRC) && ./configure --prefix=$(ROOTFS) \
		--host=x86_64-linux-gnu --target=x86_64-linux-musl \
		--with-wolfssl --disable-libcurl-option --disable-static
	$(MAKE) -C $(CURL_SRC) && $(MAKE) -C $(CURL_SRC) install

# platform post-install (optional); marker under build/<plat>/
define POST_RULE
$$(call POST_OK,$(1)): $$(call LINUX_OK,$(1)) $$(ROOT_INIT) $$(WOLFSSL_A) $$(CURL_SO)
	@echo "==> post-install ($(1))"
	@mkdir -p $$(dir $$@)
	@if [ -f "$$(call POST_SH,$(1))" ]; then \
		cd $$(BUILD) && export outdir=$$(ROOTFS) PLATFORM=$(1) linuxver=$$(LINUXVER) \
			linux_src=$$(LINUX_SRC) && \
			. $$(call POST_SH,$(1)); \
	fi
	@sudo $$(SCRIPTS)/umounts.sh 2>/dev/null || true
	@touch $$@
endef
$(foreach p,$(STD_PLATS),$(eval $(call POST_RULE,$(p))))

# --- platform entry: phony name -> tarball ----------------------------------

define PLAT_RULE
.PHONY: $(1)
$(1): rootfs-$(1).tar.xz

# Tarball is newer only when post-install (and thus whole chain) is current
rootfs-$(1).tar.xz: $$(call POST_OK,$(1)) $$(call LINUX_CFG,$(1)) $$(call TOYBOX_CFG,$(1))
	@echo "==> tar rootfs-$(1).tar.xz"
	cd $$(ROOTFS) && tar cfJ $$(REPO_ROOT)/rootfs-$(1).tar.xz .
	@echo "Build complete: rootfs-$(1).tar.xz"
endef
$(foreach p,$(STD_PLATS),$(eval $(call PLAT_RULE,$(p))))

# Build each platform with PLATFORM= set so shared targets pick the right configs
define PLAT_RECURSE
rootfs-$(1).tar.xz: force-platform-$(1)

.PHONY: force-platform-$(1)
force-platform-$(1):
	@$$(MAKE) PLATFORM=$(1) $$(call POST_OK,$(1))
endef
$(foreach p,$(STD_PLATS),$(eval $(call PLAT_RECURSE,$(p))))

# --- aliases ----------------------------------------------------------------

.PHONY: arm64 radxa radxa-cm5 radxa-cm5-io cm5io cm5-io
.PHONY: rpi-zero rpi-zero-w rpizero-w rpi0 rpi0w zerow rpizero-img

arm64: aarch64
radxa radxa-cm5 radxa-cm5-io cm5io cm5-io: radxacm5io
rpi-zero rpi-zero-w rpizero-w rpi0 rpi0w zerow: rpizero

rpizero-img: rootfs-rpizero.tar.xz
	$(SCRIPTS)/mkimg-rpizero.sh

# =============================================================================
# Radxa CM5 + IO — all logic in this Makefile (Docker only when host needs it)
# =============================================================================
#   make radxacm5io              # rootfs+kernel + hybrid image
#   make radxacm5io-rootfs       # kernel/userspace only (Linux, or inside Docker)
#   make radxacm5io-img          # pack lin0-radxacm5io.img from existing rootfs
#
# Env: RADXA_LINUXVER (default master), RADXA_P3_MB (default 128), OFFICIAL_IMG
# =============================================================================

HOST_OS          := $(shell uname -s)
RADXA_LINUXVER   ?= master
RADXA_P3_MB      ?= 128
RADXA_P3_LBA     := 679936
RADXA_DTB        := rk3588s-radxa-cm5-io.dtb
RADXA_IMG        := $(REPO_ROOT)/lin0-radxacm5io.img
RADXA_OFFICIAL   ?= $(BUILD)/official-radxa-inspect/radxa-cm5-io_bookworm_cli_b3.output.img
RADXA_BUILDER    := lin0-radxacm5io-builder:latest
RADXA_ROOT_LABEL := lin0root
RADXA_ROOT_UUID  := a1ce5ba1-b0fe-43c3-b85c-eca170319b83
RADXA_CMN        := console=tty0 rootwait rw init=/bin/init

.PHONY: radxacm5io radxacm5io-builder radxacm5io-rootfs radxacm5io-img radxacm5io-bootfiles

radxacm5io: ## full Radxa hybrid image
	@echo "lin0 radxacm5io  host=$(HOST_OS)  linux=$(RADXA_LINUXVER)  -> $(RADXA_IMG)"
	@test -f "$(RADXA_OFFICIAL)" || { echo "missing official donor: $(RADXA_OFFICIAL)" >&2; exit 1; }
ifneq ($(HOST_OS),Linux)
	@$(MAKE) radxacm5io-builder
	docker run --rm --platform linux/arm64 \
		-e RADXA_LINUXVER="$(RADXA_LINUXVER)" \
		-v "$(REPO_ROOT):/work" -w /work \
		"$(RADXA_BUILDER)" \
		make radxacm5io-rootfs RADXA_LINUXVER="$(RADXA_LINUXVER)"
else
	@$(MAKE) radxacm5io-rootfs RADXA_LINUXVER="$(RADXA_LINUXVER)"
endif
	@$(MAKE) radxacm5io-img

radxacm5io-builder:
	@docker info >/dev/null 2>&1 || { echo "start Docker first" >&2; exit 1; }
	@echo "==> docker builder $(RADXA_BUILDER)"
	@mkdir -p "$(BUILD)"
	@printf '%s\n' \
		'FROM debian:bookworm-slim' \
		'ENV DEBIAN_FRONTEND=noninteractive' \
		'RUN apt-get update && apt-get install -y --no-install-recommends \' \
		' build-essential gcc g++ make bison flex bc kmod cpio rsync \' \
		' gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \' \
		' libncurses-dev libssl-dev libelf-dev dwarves \' \
		' git curl ca-certificates xz-utils bzip2 \' \
		' python3 python3-dev python3-setuptools python3-pyelftools \' \
		' device-tree-compiler u-boot-tools swig libgnutls28-dev \' \
		' dosfstools e2fsprogs fdisk util-linux parted gdisk musl-tools xxd \' \
		' && rm -rf /var/lib/apt/lists/*' \
		'WORKDIR /work' \
		> "$(BUILD)/Dockerfile.radxa"
	docker build --platform linux/arm64 -t "$(RADXA_BUILDER)" -f "$(BUILD)/Dockerfile.radxa" "$(REPO_ROOT)"

# Linux-only recipe: musl + kernel + toybox + mksh + tcc + skeleton + boot files
radxacm5io-rootfs:
	@test "$$(uname -s)" = Linux || { echo "radxacm5io-rootfs needs Linux (use: make radxacm5io)" >&2; exit 1; }
	@echo "==> [radxacm5io] musl $(MUSLVER)"
	mkdir -p "$(BUILD)" "$(ROOTFS)"
	@if [ ! -d "$(MUSL_SRC)" ]; then curl -fsSL "$(MUSLURL)" | tar xz -C "$(BUILD)"; fi
	cd "$(MUSL_SRC)" && ./configure --prefix="$(ROOTFS)" --enable-static && \
		$(MAKE) -j$$(nproc) && $(MAKE) install
	@echo "==> [radxacm5io] linux $(RADXA_LINUXVER)"
	@# build tree on /tmp (case-sensitive; safe under Docker bind mounts)
	LINUX_BUILD="/tmp/lin0-build/linux-$(RADXA_LINUXVER)"; \
	mkdir -p /tmp/lin0-build "$(BUILD)/dtbs" "$(BUILD)/kheaders"; \
	if [ ! -f "$$LINUX_BUILD/Makefile" ]; then \
		rm -rf "$$LINUX_BUILD"; \
		case "$(RADXA_LINUXVER)" in \
			master|main) git clone --depth=1 https://github.com/torvalds/linux.git "$$LINUX_BUILD" ;; \
			*) git clone --depth=1 --branch "$(RADXA_LINUXVER)" https://github.com/torvalds/linux.git "$$LINUX_BUILD" \
				|| git clone --depth=1 https://github.com/torvalds/linux.git "$$LINUX_BUILD" ;; \
		esac; \
	fi; \
	cd "$$LINUX_BUILD"; \
	test -f arch/arm64/boot/dts/rockchip/$(RADXA_DTB:.dtb=.dts) || { \
		echo "missing $(RADXA_DTB:.dtb=.dts) — use RADXA_LINUXVER=master" >&2; exit 1; }; \
	if [ ! -f "$(CONFIGS)/radxacm5io-linux.config" ] || \
	   [ "$(CONFIGS)/radxacm5io-kernel.fragment" -nt "$(CONFIGS)/radxacm5io-linux.config" ]; then \
		sh "$(SCRIPTS)/gen-radxacm5io-linux-config.sh" "$$LINUX_BUILD"; \
	fi; \
	cp "$(CONFIGS)/radxacm5io-linux.config" .config; \
	$(MAKE) ARCH=arm64 olddefconfig; \
	if grep -q '^CONFIG_MODULES=y' .config; then \
		$(MAKE) ARCH=arm64 -j$$(nproc) Image modules dtbs; \
		INSTALL_MOD_PATH="$(ROOTFS)" $(MAKE) ARCH=arm64 modules_install; \
	else \
		$(MAKE) ARCH=arm64 -j$$(nproc) Image dtbs; \
	fi; \
	mkdir -p "$(ROOTFS)/boot"; \
	cp -f arch/arm64/boot/Image "$(ROOTFS)/boot/Image"; \
	cp -f arch/arm64/boot/dts/rockchip/$(RADXA_DTB) "$(ROOTFS)/boot/$(RADXA_DTB)"; \
	cp -f arch/arm64/boot/dts/rockchip/$(RADXA_DTB) "$(BUILD)/dtbs/"; \
	rm -rf /tmp/lin0-kheaders && mkdir -p /tmp/lin0-kheaders; \
	INSTALL_HDR_PATH=/tmp/lin0-kheaders $(MAKE) ARCH=arm64 headers_install; \
	KHDR=""; \
	for c in /tmp/lin0-kheaders/include /tmp/lin0-kheaders/usr/include \
		"$$LINUX_BUILD/usr/include"; do \
		[ -f "$$c/linux/version.h" ] && KHDR=$$c && break; \
	done; \
	test -n "$$KHDR"; \
	cp -a "$$KHDR/." "$(BUILD)/kheaders/"; \
	mkdir -p "$(ROOTFS)/usr/include" && cp -a "$$KHDR/." "$(ROOTFS)/usr/include/"
	@echo "==> [radxacm5io] toybox"
	@if [ ! -d "$(TOYBOX_SRC)/.git" ]; then git clone --depth=1 "$(TOYBOXURL)" "$(TOYBOX_SRC)"; fi
	cd "$(TOYBOX_SRC)" && git fetch origin && git checkout master && git pull --ff-only origin master || true
	cd "$(TOYBOX_SRC)" && $(MAKE) distclean 2>/dev/null || true
	# Use our config as KCONFIG_ALLCONFIG seed: kconfig keeps our selections
	# and fills new symbols with defaults.  This handles toys/pending (default n)
	# correctly because our config explicitly sets CONFIG_MODPROBE=y etc.
	cd "$(TOYBOX_SRC)" && \
		KCONFIG_ALLCONFIG="$(CONFIGS)/radxacm5io-toybox.config" $(MAKE) allnoconfig && \
		$(MAKE) CC=gcc CFLAGS="-static -Os" LDFLAGS="-static --no-pie" -j$$(nproc) toybox && \
		./toybox modprobe --help >/dev/null && \
		$(MAKE) PREFIX="$(ROOTFS)/bin" install_flat
	@echo "==> [radxacm5io] mksh"
	@if [ ! -f "$(MKSH_SRC)/Build.sh" ]; then curl -fsSL "$(MKSHURL)" | tar xz -C "$(BUILD)"; fi
	cd "$(MKSH_SRC)" && chmod +x Build.sh && CC="gcc -static" ./Build.sh \
		&& install -c -s -m 555 mksh "$(ROOTFS)/bin/sh"
	@echo "==> [radxacm5io] tcc"
	rm -rf "$(TCC_SRC)" && git clone --depth=1 "$(TCCURL)" "$(TCC_SRC)"
	cd "$(TCC_SRC)" && ./configure --prefix=/ \
		--sysincludepaths="$(ROOTFS)/include" --libpaths="$(ROOTFS)/lib" \
		--tccdir=/lib --crtprefix="$(ROOTFS)/lib" --elfinterp="$(ROOTFS)/lib/libc.so" \
		--config-static --config-bcheck=no --disable-rpath --config-musl \
		&& $(MAKE) -j$$(nproc) && $(MAKE) DESTDIR="$(ROOTFS)" install
	printf '%s\n' '#!/bin/sh' 'tcc -ar "$$@"' > "$(ROOTFS)/bin/ar" && chmod +x "$(ROOTFS)/bin/ar"
	cd "$(TCC_SRC)" && ./configure --prefix=/ \
		--sysincludepaths="$(ROOTFS)/include:/include" --libpaths="$(ROOTFS)/lib:/lib" \
		--crtprefix=/lib --ar="$(ROOTFS)/bin/tcc -ar" --elfinterp=/lib/libc.so \
		--config-static --config-bcheck=no --disable-rpath --config-musl \
		&& $(MAKE) clean && $(MAKE) -j$$(nproc) && $(MAKE) DESTDIR="$(ROOTFS)" install
	mv "$(ROOTFS)/bin/tcc" "$(ROOTFS)/bin/cc"
	printf '%s\n' '#!/bin/sh' 'cc -ar "$$@"' > "$(ROOTFS)/bin/ar" && chmod +x "$(ROOTFS)/bin/ar"
	rm -f "$(ROOTFS)/lib/musl-gcc.specs" "$(ROOTFS)/bin/musl-gcc" 2>/dev/null || true
	@echo "==> [radxacm5io] skeleton + boot files"
	mkdir -p "$(ROOTFS)/bin" "$(ROOTFS)/etc" "$(ROOTFS)/home/root" \
		"$(ROOTFS)/dev/pts" "$(ROOTFS)/proc" "$(ROOTFS)/sys" "$(ROOTFS)/tmp" \
		"$(ROOTFS)/var/run" "$(ROOTFS)/run" "$(ROOTFS)/boot/extlinux" \
		"$(ROOTFS)/lib/firmware/rtlwifi"
	cp -a "$(REPO_ROOT)/etc/." "$(ROOTFS)/etc/"
	cp -f "$(REPO_ROOT)/init" "$(ROOTFS)/bin/init" && chmod +x "$(ROOTFS)/bin/init"
	@if [ -f "$(ROOTFS)/lib/libc.so" ]; then \
		ln -sfn libc.so "$(ROOTFS)/lib/ld-musl-aarch64.so.1"; \
		ln -sfn libc.so "$(ROOTFS)/lib/ld-linux-aarch64.so.1" 2>/dev/null || true; \
		ln -sf ../lib/libc.so "$(ROOTFS)/bin/ldd" 2>/dev/null || true; \
		ln -sf ../lib/libc.so "$(ROOTFS)/bin/ld" 2>/dev/null || true; \
	fi
	@grep -q '^root:' "$(ROOTFS)/etc/passwd" 2>/dev/null || \
		echo 'root:x:0:0:root:/home/root:/bin/sh' >> "$(ROOTFS)/etc/passwd"
	echo "nameserver 1.1.1.1" > "$(ROOTFS)/etc/resolv.conf"
	echo "lin0-cm5" > "$(ROOTFS)/etc/hostname"
	@$(MAKE) radxacm5io-bootfiles
	@# drop stale module trees
	@if [ -d "$(ROOTFS)/lib/modules" ]; then \
		newest=""; for d in "$(ROOTFS)/lib/modules"/*; do \
			[ -f "$$d/modules.dep" ] || continue; \
			[ -z "$$newest" ] || [ "$$d" -nt "$$newest" ] && newest=$$d; \
		done; \
		for d in "$(ROOTFS)/lib/modules"/*; do \
			[ -d "$$d" ] || continue; [ "$$d" = "$$newest" ] && continue; \
			rm -rf "$$d"; \
		done; \
	fi
	@test -f "$(ROOTFS)/boot/Image" && test -f "$(ROOTFS)/bin/init"
	@echo "radxacm5io-rootfs done"

radxacm5io-bootfiles: $(REGDB) ## extlinux + wifi firmware into rootfs/
	mkdir -p "$(ROOTFS)/boot/extlinux" "$(ROOTFS)/boot/fat-extlinux" "$(ROOTFS)/lib/firmware/rtlwifi" "$(ROOTFS)/bin"
	@if [ -f "$(REPO_ROOT)/linux-firmware/rtlwifi/rtl8188eufw.bin" ]; then \
		cp -f "$(REPO_ROOT)/linux-firmware/rtlwifi/rtl8188eufw.bin" \
			"$(ROOTFS)/lib/firmware/rtlwifi/rtl8188eufw.bin"; \
	fi
	printf '%s\n' \
		'DEFAULT lin0' 'TIMEOUT 10' 'MENU TITLE lin0 CM5 IO' \
		'LABEL lin0' '	MENU LABEL lin0 root=LABEL=$(RADXA_ROOT_LABEL)' \
		'	LINUX /boot/Image' '	FDT /boot/$(RADXA_DTB)' \
		'	APPEND $(RADXA_CMN) root=LABEL=$(RADXA_ROOT_LABEL) rootfstype=ext4' \
		'LABEL lin0-mmc0' '	MENU LABEL lin0 root=/dev/mmcblk0p3' \
		'	LINUX /boot/Image' '	FDT /boot/$(RADXA_DTB)' \
		'	APPEND $(RADXA_CMN) root=/dev/mmcblk0p3 rootfstype=ext4' \
		> "$(ROOTFS)/boot/extlinux/extlinux.conf"
	printf '%s\n' \
		'DEFAULT lin0' 'TIMEOUT 10' 'MENU TITLE lin0 CM5 IO FAT' \
		'LABEL lin0' '	MENU LABEL lin0' \
		'	LINUX /Image' '	FDT /$(RADXA_DTB)' \
		'	APPEND $(RADXA_CMN) root=LABEL=$(RADXA_ROOT_LABEL) rootfstype=ext4' \
		> "$(ROOTFS)/boot/fat-extlinux/extlinux.conf"
	printf 'lin0 radxa-cm5-io\n' > "$(ROOTFS)/boot/lin0.id"
	@if ! grep -q 'HDMI/tty0 console' "$(ROOTFS)/etc/issue" 2>/dev/null; then \
		printf '\nlin0 on Radxa CM5 IO (HDMI/tty0 console)\n' >> "$(ROOTFS)/etc/issue"; \
	fi

# Pack hybrid image from existing rootfs (dd head + GPT fix + docker/losetup p3)
radxacm5io-img:
	@test -f "$(RADXA_OFFICIAL)" || { echo "missing $(RADXA_OFFICIAL)" >&2; exit 1; }
	@test -f "$(ROOTFS)/boot/Image" || { echo "missing kernel; run make radxacm5io first" >&2; exit 1; }
	@test -f "$(ROOTFS)/bin/init" || { echo "missing $(ROOTFS)/bin/init" >&2; exit 1; }
	@cp -f "$(REPO_ROOT)/init" "$(ROOTFS)/bin/init" && chmod +x "$(ROOTFS)/bin/init"
	@$(MAKE) radxacm5io-bootfiles
	@echo "==> hybrid image $(RADXA_IMG) (p3=$(RADXA_P3_MB)MiB @ LBA $(RADXA_P3_LBA))"
	@mkdir -p "$(BUILD)"
	@P3_SECTS=$$(($(RADXA_P3_MB)*1024*1024/512)); \
	HEAD_BYTES=$$(($(RADXA_P3_LBA)*512)); \
	TOTAL_BYTES=$$((($(RADXA_P3_LBA)+P3_SECTS)*512)); \
	rm -f "$(RADXA_IMG)"; \
	dd if="$(RADXA_OFFICIAL)" of="$(RADXA_IMG)" bs=4M \
		count=$$(((HEAD_BYTES+4194303)/4194304)) status=none; \
	python3 -c "p=r'$(RADXA_IMG)';h=$$HEAD_BYTES;t=$$TOTAL_BYTES;f=open(p,'r+b');f.truncate(h);f.seek(t-1);f.write(b'\\0');f.close();print('image bytes',t)"; \
	python3 "$(SCRIPTS)/gpt-resize-p3.py" "$(RADXA_IMG)" "$(RADXA_P3_LBA)" "$$P3_SECTS"; \
	printf '%s\n' \
		'#!/bin/bash' 'set -euo pipefail' 'export DEBIAN_FRONTEND=noninteractive' \
		'apt-get update -qq && apt-get install -y -qq util-linux e2fsprogs rsync >/dev/null' \
		'IMG=/work/lin0-radxacm5io.img; ROOTFS=/work/rootfs; MNT=/mnt/p3; mkdir -p "$$MNT"' \
		'OFF=$$((P3_START_LBA*512)); SZ=$$((P3_SECTS*512))' \
		'LOOP=$$(losetup --find --show -o "$$OFF" --sizelimit "$$SZ" "$$IMG")' \
		'mkfs.ext4 -F -L "$$ROOT_LABEL" -U "$$ROOT_UUID" "$$LOOP"' \
		'mount "$$LOOP" "$$MNT"; rsync -aH "$$ROOTFS"/ "$$MNT"/' \
		'if [ -f "$$MNT/lib/libc.so" ]; then chmod 755 "$$MNT/lib/libc.so"; ln -sfn libc.so "$$MNT/lib/ld-musl-aarch64.so.1"; fi' \
		'mkdir -p "$$MNT/bin" "$$MNT/boot/extlinux" "$$MNT/proc" "$$MNT/sys" "$$MNT/dev" "$$MNT/tmp" "$$MNT/run"' \
		'install -m 0755 /work/init "$$MNT/bin/init"' \
		'install -m 0644 "$$ROOTFS/boot/Image" "$$MNT/boot/Image"' \
		'install -m 0644 "$$ROOTFS/boot/'"$(RADXA_DTB)"'" "$$MNT/boot/'"$(RADXA_DTB)"'"' \
		'cat > "$$MNT/boot/extlinux/extlinux.conf" << EOF' \
		'default emmc' 'timeout 20' 'menu title lin0 CM5 IO' \
		'label emmc' '  menu label root=/dev/mmcblk0p3' \
		'  linux /boot/Image' '  fdt /boot/'"$(RADXA_DTB)" \
		'  append root=/dev/mmcblk0p3 '"$(RADXA_CMN)"' rootfstype=ext4' \
		'label bylabel' '  menu label root=LABEL='"$(RADXA_ROOT_LABEL)" \
		'  linux /boot/Image' '  fdt /boot/'"$(RADXA_DTB)" \
		'  append root=LABEL='"$(RADXA_ROOT_LABEL)"' '"$(RADXA_CMN)"' rootfstype=ext4' \
		'EOF' \
		'sync; umount "$$MNT"; losetup -d "$$LOOP"; echo p3 done' \
		> "$(BUILD)/radxa-p3.sh"; \
	docker run --rm --privileged \
		-e P3_START_LBA="$(RADXA_P3_LBA)" -e P3_SECTS="$$P3_SECTS" \
		-e ROOT_UUID="$(RADXA_ROOT_UUID)" -e ROOT_LABEL="$(RADXA_ROOT_LABEL)" \
		-v "$(REPO_ROOT):/work" debian:bookworm-slim \
		bash /work/build/radxa-p3.sh
	@ls -lh "$(RADXA_IMG)"
	@echo "Flash: rkdeveloptool wl 0 lin0-radxacm5io.img"

# --- meta -------------------------------------------------------------------

.PHONY: all help list clean distclean umount-rootfs mount-rootfs

all: $(PLATFORM)

help:
	@echo "lin0 — Make targets (real file deps where possible)."
	@echo ""
	@echo "  make <platform>     one of: $(PLATFORMS)"
	@echo "  make radxacm5io     Radxa CM5 IO hybrid image (Docker on macOS)"
	@echo "  make radxacm5io-img re-pack image from existing rootfs/"
	@echo "  make list | clean | distclean"
	@echo ""
	@echo "Radxa env: RADXA_LINUXVER=$(RADXA_LINUXVER)  RADXA_P3_MB=$(RADXA_P3_MB)"
	@echo "Edit configs/radxacm5io-* , init, etc/ — then rebuild."

list:
	@echo "Platforms: $(PLATFORMS)"
	@echo "Aliases: arm64->aarch64; radxa|cm5io->radxacm5io; rpi-zero->rpizero"

umount-rootfs:
	@sudo $(SCRIPTS)/umounts.sh 2>/dev/null || true

mount-rootfs:
	@sudo $(SCRIPTS)/mounts.sh

clean: umount-rootfs
	rm -rf $(ROOTFS) $(foreach p,$(STD_PLATS),$(BUILD)/$(p))
	rm -f $(REPO_ROOT)/rootfs-*.tar.xz

distclean: umount-rootfs
	rm -rf $(BUILD) $(ROOTFS)
	rm -f $(REPO_ROOT)/rootfs-*.tar.xz $(REPO_ROOT)/lin0-*.img $(REPO_ROOT)/lin0-*.tar.xz

.DEFAULT_GOAL := all
