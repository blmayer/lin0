#!/bin/sh
# Runs inside the Docker builder (linux/arm64 Debian).
# Builds lin0 rootfs + mainline kernel, then official-hybrid image (stock loader/GPT/p1/p2 + lin0 on p3).
# Does NOT build U-Boot — bootloader comes from the official Radxa image head.
set -e

cd /work
export PLATFORM="${PLATFORM:-radxacm5io}"
export LINUXVER="${LINUXVER:-master}"
export outdir="/work/rootfs"
export DTB_NAME="${DTB_NAME:-rk3588s-radxa-cm5-io.dtb}"
# Official Debian image used as loader+GPT+p1+p2 donor (required for hybrid)
export OFFICIAL_IMG="${OFFICIAL_IMG:-/work/build/official-radxa-inspect/radxa-cm5-io_bookworm_cli_b3.output.img}"
export P3_SIZE_MB="${P3_SIZE_MB:-128}"


MUSLVER="1.2.5"
STAMPS="build/.stamps-radxacm5io"
mkdir -p build rootfs "$STAMPS"

check_stamp() { [ -f "$STAMPS/$1" ]; }
stage_done() { touch "$STAMPS/$1"; }
stage() { echo ""; echo "==> [$PLATFORM] $1"; }

linux_tarball_url() {
	v="$1"
	echo "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$v.tar.xz"
}

# Prefer tarball for versioned releases; use git for master/main/rc tags.
linux_needs_git() {
	case "$1" in
		master|main|linux-*|*-rc*) return 0 ;;
		*) return 1 ;;
	esac
}

# ---------------------------------------------------------------------------
# 1. musl toolchain (static-capable host toolchain via system gcc + musl)
# ---------------------------------------------------------------------------
stage "musl $MUSLVER"
if ! check_stamp musl; then
	cd build
	[ -d "musl-$MUSLVER" ] || curl -fsSL "https://musl.libc.org/releases/musl-$MUSLVER.tar.gz" | tar xz
	cd "musl-$MUSLVER"
	./configure --prefix="$outdir" --enable-static
	make -j"$(nproc)"
	make install
	cd /work
	stage_done musl
fi
export CC="$outdir/bin/musl-gcc"
export PATH="$outdir/bin:$PATH"

# ---------------------------------------------------------------------------
# 2. mainline Linux kernel (headers + Image + modules + DTB)
# ---------------------------------------------------------------------------
stage "linux $LINUXVER"
# Build on container-local disk (/tmp) — macOS bind mounts are case-insensitive
# and can fail mid-extract with "Directory renamed before its status could be extracted".
LINUX_BUILD="${LINUX_BUILD:-/tmp/lin0-build/linux-$LINUXVER}"
if ! check_stamp linux; then
	# Kernel must use host gcc/binutils, not musl-gcc / rootfs ld from $PATH.
	_SAVE_PATH="$PATH"
	_SAVE_CC="${CC:-}"
	export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
	unset CC CXX CFLAGS LDFLAGS CPPFLAGS C_INCLUDE_PATH CPLUS_INCLUDE_PATH LD
	export CC=gcc HOSTCC=gcc

	mkdir -p /tmp/lin0-build /work/build
	if [ ! -f "$LINUX_BUILD/Makefile" ]; then
		if linux_needs_git "$LINUXVER"; then
			echo "cloning torvalds/linux ($LINUXVER) — shallow clone to $LINUX_BUILD"
			rm -rf "$LINUX_BUILD"
			if [ "$LINUXVER" = "master" ] || [ "$LINUXVER" = "main" ]; then
				git clone --depth=1 https://github.com/torvalds/linux.git "$LINUX_BUILD"
			else
				git clone --depth=1 --branch "$LINUXVER" https://github.com/torvalds/linux.git "$LINUX_BUILD" || \
				git clone --depth=1 https://github.com/torvalds/linux.git "$LINUX_BUILD"
			fi
		else
			TARBALL="/tmp/lin0-build/linux-$LINUXVER.tar.xz"
			URL="$(linux_tarball_url "$LINUXVER")"
			if [ ! -f "$TARBALL" ]; then
				if [ -f "/work/build/linux-$LINUXVER.tar.xz" ]; then
					cp "/work/build/linux-$LINUXVER.tar.xz" "$TARBALL"
				elif curl -fsSL "$URL" -o "$TARBALL"; then
					cp "$TARBALL" "/work/build/linux-$LINUXVER.tar.xz" || true
				else
					echo "tarball unavailable; falling back to git clone v$LINUXVER / master"
					rm -rf "$LINUX_BUILD"
					git clone --depth=1 --branch "v$LINUXVER" https://github.com/torvalds/linux.git "$LINUX_BUILD" 2>/dev/null || \
					git clone --depth=1 https://github.com/torvalds/linux.git "$LINUX_BUILD"
				fi
			fi
			if [ -f "$TARBALL" ] && [ ! -f "$LINUX_BUILD/Makefile" ]; then
				echo "extracting kernel to $LINUX_BUILD ..."
				rm -rf "$LINUX_BUILD"
				tar -C /tmp/lin0-build -xf "$TARBALL"
			fi
		fi
	fi
	cd "$LINUX_BUILD"
	echo "kernel tree: $(pwd) ($(git describe --always --tags 2>/dev/null || echo "$LINUXVER"))"

	# Require CM5 IO DTS (on mainline master; not in stable tarballs yet as of 6.19.x)
	if [ ! -f arch/arm64/boot/dts/rockchip/rk3588s-radxa-cm5-io.dts ]; then
		echo "error: rk3588s-radxa-cm5-io.dts missing from this kernel tree."
		echo " Use mainline git: LINUXVER=master ./scripts/build-radxacm5io-docker.sh"
		exit 1
	fi

	# Generate / refresh platform kernel config from fragment
	if [ ! -f /work/configs/radxacm5io-linux.config ] || [ /work/configs/radxacm5io-kernel.fragment -nt /work/configs/radxacm5io-linux.config ]; then
		sh /work/scripts/gen-radxacm5io-linux-config.sh "$(pwd)"
	fi
	cp /work/configs/radxacm5io-linux.config .config
	make ARCH=arm64 olddefconfig

	# modules target only if CONFIG_MODULES=y (minimal allnoconfig build disables it)
	if grep -q '^CONFIG_MODULES=y' .config; then
		make ARCH=arm64 -j"$(nproc)" Image modules dtbs
		INSTALL_MOD_PATH="$outdir" make ARCH=arm64 modules_install
	else
		make ARCH=arm64 -j"$(nproc)" Image dtbs
		rm -rf "$outdir/lib/modules"
	fi
	mkdir -p "$outdir/boot" /work/build/dtbs
	cp -f arch/arm64/boot/Image "$outdir/boot/Image"
	ls -lh arch/arm64/boot/Image
	echo "Image size: $(wc -c < arch/arm64/boot/Image) bytes"

	DTB_SRC="arch/arm64/boot/dts/rockchip/$DTB_NAME"
	if [ ! -f "$DTB_SRC" ]; then
		echo "error: DTB not built: $DTB_SRC"
		echo "available radxa/rk3588s dtbs:"
		ls arch/arm64/boot/dts/rockchip/*radxa* arch/arm64/boot/dts/rockchip/rk3588s* 2>/dev/null | head -40 || true
		exit 1
	fi
	cp -f "$DTB_SRC" "$outdir/boot/$DTB_NAME"
	cp -f "$DTB_SRC" /work/build/dtbs/
	# headers_install emits into $INSTALL_HDR_PATH/include (or ./usr/include with default)
	rm -rf /tmp/lin0-kheaders
	mkdir -p /tmp/lin0-kheaders
	INSTALL_HDR_PATH=/tmp/lin0-kheaders make ARCH=arm64 headers_install
	KHDR=""
	for cand in /tmp/lin0-kheaders/include /tmp/lin0-kheaders/usr/include \
		"$LINUX_BUILD/usr/include" ./usr/include; do
		if [ -f "$cand/linux/rfkill.h" ] || [ -f "$cand/linux/version.h" ]; then
			KHDR="$cand"
			break
		fi
	done
	[ -n "$KHDR" ] || { echo "error: headers_install produced no usable tree"; exit 1; }
	echo "kernel headers from $KHDR"
	# Keep musl's $outdir/include pristine; stash kernel uapi separately.
	mkdir -p /work/build/kheaders "$outdir/usr/include"
	cp -a "$KHDR/." /work/build/kheaders/
	cp -a "$KHDR/." "$outdir/usr/include/"

	cd /work
	export PATH="$_SAVE_PATH"
	if [ -n "$_SAVE_CC" ]; then export CC="$_SAVE_CC"; else export CC="$outdir/bin/musl-gcc"; fi
	unset _SAVE_PATH _SAVE_CC
	stage_done linux
fi

# ---------------------------------------------------------------------------
# 3. toybox (static)
# ---------------------------------------------------------------------------
stage "toybox"
if ! check_stamp toybox; then
	# Install kernel uapi into a *separate* tree — do NOT merge into musl's $outdir/include
	# (that poisons libc headers and breaks static builds).
	if [ ! -f /work/build/kheaders/linux/rfkill.h ]; then
		KHDR=""
		for cand in /tmp/lin0-kheaders/include /tmp/lin0-kheaders/usr/include \
			/tmp/lin0-build/linux-master/usr/include /usr/include; do
			if [ -f "$cand/linux/rfkill.h" ]; then KHDR="$cand"; break; fi
		done
		if [ -n "$KHDR" ]; then
			mkdir -p /work/build/kheaders
			cp -a "$KHDR/." /work/build/kheaders/
		fi
	fi
	# also expose kheaders under rootfs for on-target compiles (alongside musl)
	if [ -d /work/build/kheaders/linux ] && [ ! -d "$outdir/usr/include/linux" ]; then
		mkdir -p "$outdir/usr/include"
		cp -a /work/build/kheaders/. "$outdir/usr/include/"
	fi

	cd build
	[ -d toybox ] || git clone --depth=1 https://github.com/landley/toybox.git
	cd toybox
	# clean partial build from failed runs
	make distclean 2>/dev/null || rm -f toybox generated/* 2>/dev/null || true
	cp /work/configs/radxacm5io-toybox.config .config
	# Build with builder's normal toolchain (glibc headers + linux-libc-dev), statically linked.
	# Do not pass musl include paths here.
	make CC="gcc" CFLAGS="-static -Os" LDFLAGS='-static --no-pie' -j"$(nproc)" toybox
	make PREFIX="$outdir/bin" install_flat
	cd /work
	stage_done toybox
fi

# ---------------------------------------------------------------------------
# 4. mksh as /bin/sh
# ---------------------------------------------------------------------------
stage "mksh"
if ! check_stamp mksh; then
	cd build
	[ -d mksh ] || { curl -fsSL http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R59c.tgz | tar xz; }
	cd mksh
	chmod +x Build.sh
	CC="${CC:-gcc} -static" ./Build.sh
	install -c -s -m 555 mksh "$outdir/bin/sh"
	cd /work
	stage_done mksh
fi

# ---------------------------------------------------------------------------
# 5. tcc (tinycc) — pass1 with musl-gcc, pass2 self-host style
# ---------------------------------------------------------------------------
stage "tcc"
if ! check_stamp tcc; then
	cd build
	rm -rf tinycc
	git clone --depth=1 https://repo.or.cz/tinycc.git
	cd tinycc
	./configure --prefix=/ \
		--sysincludepaths="$outdir/include" \
		--libpaths="$outdir/lib" \
		--tccdir=/lib \
		--crtprefix="$outdir/lib" \
		--elfinterp="$outdir/lib/libc.so" \
		--config-static \
		--config-bcheck=no \
		--disable-rpath \
		--config-musl
	make -j"$(nproc)"
	make DESTDIR="$outdir" install
	cat > "$outdir/bin/ar" << 'EOF'
#!/bin/sh
tcc -ar "$@"
EOF
	chmod +x "$outdir/bin/ar"
	# second pass: install as /bin/cc
	./configure --prefix=/ \
		--sysincludepaths="$outdir/include:/include" \
		--libpaths="$outdir/lib:/lib" \
		--crtprefix=/lib \
		--ar="$outdir/bin/tcc -ar" \
		--elfinterp=/lib/libc.so \
		--config-static \
		--config-bcheck=no \
		--disable-rpath \
		--config-musl
	make clean
	make -j"$(nproc)"
	make DESTDIR="$outdir" install
	mv "$outdir/bin/tcc" "$outdir/bin/cc"
	cat > "$outdir/bin/ar" << 'EOF'
#!/bin/sh
cc -ar "$@"
EOF
	chmod +x "$outdir/bin/ar"
	rm -f "$outdir/lib/musl-gcc.specs" "$outdir/bin/musl-gcc" 2>/dev/null || true
	cd /work
	stage_done tcc
fi

# ---------------------------------------------------------------------------
# 6. rootfs skeleton + init
# ---------------------------------------------------------------------------
stage "rootfs skeleton"
if ! check_stamp skeleton; then
	mkdir -p "$outdir/sbin" "$outdir/etc" "$outdir/home/root" \
		"$outdir/dev/pts" "$outdir/proc" "$outdir/sys" "$outdir/tmp" \
		"$outdir/var/run" "$outdir/run" "$outdir/boot/extlinux"
	cp -a /work/etc/. "$outdir/etc/"
	# Platform PID1 (never exit — missing /bin/sh → panic "Attempted to kill init")
	cp -f /work/scripts/radxacm5io-init.sh "$outdir/sbin/init"
	chmod +x "$outdir/sbin/init"
	# musl: libc.so is the loader; ld-musl-* must resolve to it
	if [ -f "$outdir/lib/libc.so" ]; then
		ln -sfn libc.so "$outdir/lib/ld-musl-aarch64.so.1"
		ln -sfn libc.so "$outdir/lib/ld-linux-aarch64.so.1" 2>/dev/null || true
	fi
	[ -f "$outdir/etc/profile" ] || cat > "$outdir/etc/profile" << 'PROF'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export TERM="${TERM:-linux}"
export HOME="${HOME:-/home/root}"
umask 022
PROF
	# ensure passwd has root
	grep -q '^root:' "$outdir/etc/passwd" 2>/dev/null || \
		echo 'root:x:0:0:root:/home/root:/bin/sh' >> "$outdir/etc/passwd"
	# set simple resolv
	echo "nameserver 1.1.1.1" > "$outdir/etc/resolv.conf"
	echo "lin0-cm5" > "$outdir/etc/hostname"
	# ldd/ld convenience links
	ln -sf ../lib/libc.so "$outdir/bin/ldd" 2>/dev/null || true
	ln -sf ../lib/libc.so "$outdir/bin/ld" 2>/dev/null || true
	stage_done skeleton
fi

# ---------------------------------------------------------------------------
# 7. platform post-install (extlinux, firmware)
# ---------------------------------------------------------------------------
stage "post-install"
if ! check_stamp postinstall; then
	# ensure DTB/Image in boot
	[ -f "$outdir/boot/$DTB_NAME" ] || \
		cp -f "/work/build/dtbs/$DTB_NAME" "$outdir/boot/" 2>/dev/null || true
	outdir="$outdir" DTB_NAME="$DTB_NAME" sh /work/scripts/post-install-radxacm5io.sh
	stage_done postinstall
fi

# ---------------------------------------------------------------------------
# 8. sanity — hybrid assembly on host uses ./rootfs (no tar.xz)
# ---------------------------------------------------------------------------
[ -f "$outdir/boot/Image" ] || [ -f "$outdir/boot/vmlinuz-lin0" ] || {
	echo "error: no kernel Image under $outdir/boot" >&2
	exit 1
}
[ -f "$outdir/boot/$DTB_NAME" ] || cp -f "/work/build/dtbs/$DTB_NAME" "$outdir/boot/" 2>/dev/null || true

echo ""
echo "inner done: rootfs + kernel ready for hybrid assembly on host"
ls -lh "$outdir/boot/Image" "$outdir/boot/$DTB_NAME" 2>/dev/null || true
