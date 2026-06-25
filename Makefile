# lin0 — Makefile-only builds (real file prerequisites, no stamps)
#
#   make                 # host arch -> rootfs-<arch>.tar.xz
#   make x86_64          # explicit platform
#   make list | help | clean | distclean
#
# Make rebuilds a target when it is missing or older than any prerequisite.
# Env (radxacm5io only): LINUXVER, OFFICIAL_IMG, P3_SIZE_MB

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
ROOT_INIT  := $(ROOTFS)/sbin/init
WOLFSSL_A  := $(ROOTFS)/lib/libwolfssl.a
CURL_SO    := $(ROOTFS)/lib/libcurl.so

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
	mkdir -p $(ROOTFS)/sbin $(ROOTFS)/etc $(ROOTFS)/home/root $(ROOTFS)/dev/pts \
		$(ROOTFS)/proc $(ROOTFS)/sys $(ROOTFS)/tmp $(ROOTFS)/var/run $(ROOTFS)/run
	cp -a $(REPO_ROOT)/etc/. $(ROOTFS)/etc/
	cp $(REPO_ROOT)/init $(ROOTFS)/sbin/init
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

.PHONY: radxacm5io arm64 radxa radxa-cm5 radxa-cm5-io cm5io cm5-io
.PHONY: rpi-zero rpi-zero-w rpizero-w rpi0 rpi0w zerow rpizero-img

radxacm5io:
	@echo "Building platform: radxacm5io (Docker official-hybrid)"
	PLATFORM=radxacm5io $(SCRIPTS)/build-radxacm5io-docker.sh

arm64: aarch64
radxa radxa-cm5 radxa-cm5-io cm5io cm5-io: radxacm5io
rpi-zero rpi-zero-w rpizero-w rpi0 rpi0w zerow: rpizero

# SD card image from rootfs-rpizero.tar.xz (needs Linux: losetup, sfdisk, mkfs)
rpizero-img: rootfs-rpizero.tar.xz
	$(SCRIPTS)/mkimg-rpizero.sh

# --- meta -------------------------------------------------------------------

.PHONY: all help list clean distclean umount-rootfs mount-rootfs

all: $(PLATFORM)

help:
	@echo "lin0 — each platform is a Make target; deps are real files."
	@echo ""
	@echo "  make <platform>   one of: $(PLATFORMS)"
	@echo "  make              host arch ($(HOST_ARCH))"
	@echo "  make list | clean | distclean"
	@echo ""
	@echo "Tracked outputs include:"
	@echo "  $(MUSL_GCC), $(TOYBOX_BIN), $(HOST_CC), $(ROOT_INIT)"
	@echo "  $(BUILD)/<platform>/linux.ok, $(BUILD)/<platform>/post.ok"
	@echo "  rootfs-<platform>.tar.xz"
	@echo ""
	@echo "Edit configs/<platform>-{linux,toybox}.config or init/etc -> rebuild deps."

list:
	@echo "Platforms: $(PLATFORMS)"
	@echo "Aliases: arm64->aarch64; radxa|radxa-cm5|cm5io->radxacm5io;"
	@echo "         rpi-zero|rpi0|zerow->rpizero;  make rpizero-img -> lin0-rpizero.img"

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
