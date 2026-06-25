#!/bin/sh

set -e

arch="$(uname -m)"
show_help=0
show_list=0

# Canonical platform ids. Aliases (radxa, radxa-cm5, …) normalize below.
platforms="aarch64 x86_64 hpelitedesk pinebookpro rpi3bplus rpi5 radxacm5io"

muslver="1.2.5"
linuxver="6.13.3"

muslurl="https://musl.libc.org/releases/musl-$muslver.tar.gz"
tccurl="https://repo.or.cz/tinycc.git"
linuxurl="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$linuxver.tar.xz"
toyboxurl="https://github.com/landley/toybox.git"
mkshurl="http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R59c.tgz"
bashurl="https://ftp.gnu.org/gnu/bash/bash-5.2.37.tar.gz"
makeurl="https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz"
wolfsslurl="https://github.com/wolfSSL/wolfssl/archive/refs/tags/v5.7.6-stable.tar.gz"
curlurl="https://curl.se/tiny/tiny-curl-8.4.0.tar.gz"
dashurl="http://gondor.apana.org.au/~herbert/dash/files/dash-0.5.12.tar.gz"

repo_root="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
cd "$repo_root"

stamps_dir="build/.stamps"

cleanup() {
	echo "[cleanup] Unmounting..."
	if mountpoint -q rootfs/dev/pts 2>/dev/null; then sudo umount rootfs/dev/pts || true; fi
	if mountpoint -q rootfs/proc 2>/dev/null; then sudo umount rootfs/proc || true; fi
	if mountpoint -q rootfs/sys 2>/dev/null; then sudo umount rootfs/sys || true; fi
	if mountpoint -q rootfs/dev 2>/dev/null; then sudo umount rootfs/dev || true; fi
}

check_stamp() { [ -f "$stamps_dir/$1" ]; }
stage_done() { mkdir -p "$stamps_dir"; touch "$stamps_dir/$1"; }
stage_start() { echo "
==> Stage: $1"; }

normalize_platform() {
	# stdout: canonical PLATFORM name
	case "$1" in
		aarch64|arm64) echo aarch64 ;;
		radxacm5io|radxa|radxa-cm5|radxa-cm5-io|radxa_cm5|cm5io|cm5-io)
			echo radxacm5io ;;
		*) echo "$1" ;;
	esac
}

while [ $# -gt 0 ]; do
	case "$1" in
		-p|--platform)
			if [ -n "$2" ]; then PLATFORM="$2"; shift 2; else echo "Error: --platform requires an argument"; exit 1; fi;;
		-l|--list)
			show_list=1; shift;;
		-h|--help)
			show_help=1; shift;;
		*)
			echo "Unknown option: $1"; exit 1;;
	esac
done

if [ "$show_help" -eq 1 ]; then
	echo "Usage: $0 [options]"
	echo "Build lin0 for a platform (rootfs tarball; some platforms also emit a disk image)."
	echo ""
	echo "Options:"
	echo "  -p, --platform PLATFORM   Build for specified platform"
	echo "  -l, --list                List available platforms"
	echo "  -h, --help                Show this help message"
	echo ""
	echo "Environment variables:"
	echo "  PLATFORM                  Same as --platform"
	echo ""
	echo "Examples:"
	echo "  $0 --platform x86_64"
	echo "  PLATFORM=pinebookpro $0"
	echo "  PLATFORM=radxacm5io $0          # CM5+IO hybrid img (Docker; needs official donor img)"
	echo "  PLATFORM=radxa $0               # alias for radxacm5io"
	echo "  $0 (auto-detects architecture)"
	echo ""
	echo "Radxa: LINUXVER, OFFICIAL_IMG, P3_SIZE_MB (see scripts/build-radxacm5io-docker.sh)."
	exit 0
fi

if [ "$show_list" -eq 1 ]; then
	echo "Available platforms:"
	echo "  $(echo "$platforms" | tr ' ' '\n' | sort)"
	echo ""
	echo "Aliases: radxa, radxa-cm5, radxa-cm5-io, cm5io -> radxacm5io (official-hybrid .img via Docker)"
	exit 0
fi

if [ -z "$PLATFORM" ]; then
	PLATFORM="$arch"
fi

PLATFORM="$(normalize_platform "$PLATFORM")"

case " $platforms " in
	*" $PLATFORM "*) ;;
	*)
		echo "platform '$PLATFORM' is not supported. Options: $platforms"
		echo "Use --list to see all available platforms"
		exit 2
		;;
esac

echo "Building for platform: $PLATFORM"

# --- Radxa CM5 + IO: full image path (kernel + U-Boot + GPT image via Docker) ---
# Host make.sh cannot build arm64 RK3588 U-Boot/loader sanely on every host; the
# platform entrypoint still is PLATFORM=… ./make.sh like every other target.
if [ "$PLATFORM" = "radxacm5io" ]; then
	exec sh "$repo_root/scripts/build-radxacm5io-docker.sh"
fi

trap cleanup EXIT

export outdir="$(pwd)/rootfs"

mkdir -p build rootfs
cd build

stage_start "musl-toolchain"
if ! check_stamp "musl-toolchain"; then
	echo "Downloading and building musl..."
	curl "$muslurl" | tar xz
	cd "musl-$muslver"
	./configure --prefix=$outdir --enable-static
	make && make install
	cd ..
	stage_done "musl-toolchain"
fi

export CC="$outdir/bin/musl-gcc"

stage_start "linux-headers"
if ! check_stamp "linux-headers"; then
	echo "Installing Linux headers..."
	curl -O "$linuxurl"
	linux="$(basename "$linuxurl")"
	tar xf "$linux"
	cd "linux-$linuxver"
	cp ../../configs/"$PLATFORM"-linux.config .config
	make
	INSTALL_HDR_PATH=$outdir INSTALL_PATH=$outdir/boot INSTALL_MOD_PATH=$outdir make install headers_install modules_install
	cd ..
	stage_done "linux-headers"
fi

stage_start "toybox"
if ! check_stamp "toybox"; then
	echo "Installing toybox..."
	git clone "$toyboxurl"
	cd toybox
	cp ../../configs/"$PLATFORM"-toybox.config .config
	make LDFLAGS='-static --no-pie' toybox
	make PREFIX=$outdir/bin install_flat
	cd ..
	stage_done "toybox"
fi

export CC="$CC -static --no-pie"

stage_start "host-make"
if ! check_stamp "host-make"; then
	echo "Building host make..."
	curl "$makeurl" | tar xz
	cd make-4.4.1/
	./configure --prefix=$outdir --host=x86_64-linux-gnu --target=x86_64-linux-musl
	make && make install
	cd ..
	stage_done "host-make"
fi

stage_start "host-mksh"
if ! check_stamp "host-mksh"; then
	echo "Building host mksh..."
	curl "$mkshurl" | tar xz
	cd mksh/
	chmod +x Build.sh
	./Build.sh
	install -c -s -m 555 mksh ../../rootfs/bin/sh
	install -c -m 444 -D lksh.1 mksh.1 ../../rootfs/share/man/man1/
	cd ..
	stage_done "host-mksh"
fi

stage_start "tcc-pass1"
if ! check_stamp "tcc-pass1"; then
	echo "Building tcc pass 1..."
	git clone "$tccurl"
	cd tinycc
	./configure --prefix=/ \
		--sysincludepaths=$outdir/include \
		--libpaths=$outdir/lib \
		--tccdir=/lib \
		--crtprefix=$outdir/lib \
		--elfinterp=$outdir/lib/libc.so \
		--config-static \
		--config-bcheck=no \
		--disable-rpath \
		--config-musl
	make && make DESTDIR=$outdir install
	cat <<- EOF > $outdir/bin/ar
	#!/bin/sh
	tcc -ar \$@
	EOF
	chmod +x $outdir/bin/ar
	cd ..
	rm -rf tinycc
	stage_done "tcc-pass1"
fi

export CC="$outdir/bin/tcc -static"
rm -f ../rootfs/lib/musl-gcc.specs ../rootfs/bin/musl-gcc

stage_start "tcc-pass2"
if ! check_stamp "tcc-pass2"; then
	echo "Building tcc pass 2..."
	git clone "$tccurl"
	cd tinycc
	./configure --prefix=/ \
		--sysincludepaths=$outdir/include:/include \
		--libpaths=$outdir/lib:/lib \
		--crtprefix=/lib \
		--ar="$outdir/bin/tcc -ar" \
		--elfinterp=/lib/libc.so \
		--config-static \
		--config-bcheck=no \
		--disable-rpath \
		--config-musl
	make && make DESTDIR=$outdir install
	mv $outdir/bin/tcc $outdir/bin/cc
	cat <<- EOF > $outdir/bin/ar
	#!/bin/sh
	cc -ar \$@
	EOF
	chmod +x $outdir/bin/ar
	cd ..
	stage_done "tcc-pass2"
fi

cd ..

stage_start "rootfs-skeleton"
if ! check_stamp "rootfs-skeleton"; then
	echo "Creating rootfs skeleton and copying files..."
	mkdir -p rootfs/sbin rootfs/etc rootfs/home/root rootfs/dev/pts rootfs/proc rootfs/sys rootfs/tmp rootfs/var/run rootfs/run
	cp -r etc rootfs/etc
	cp init rootfs/sbin/
	stage_done "rootfs-skeleton"
fi

stage_start "chroot-tcc-build"
if ! check_stamp "chroot-tcc-build"; then
	echo "Entering chroot to build target tcc..."
	sudo mount -v --bind /dev rootfs/dev
	sudo mount -vt devpts devpts -o gid=5,mode=0620 rootfs/dev/pts
	sudo mount -vt proc proc rootfs/proc
	sudo mount -vt sysfs sysfs rootfs/sys
	[ -f scripts/make-target.sh ] || cp scripts/make-target.sh rootfs/tmp/
	sudo chroot rootfs /bin/env -i HOME=/home/root PATH=/bin /tmp/make-target.sh
	stage_done "chroot-tcc-build"
fi

stage_start "after-boot-packages"
if ! check_stamp "after-boot-packages"; then
	echo "Building wolfssl and tinycurl..."
	[ -d wolfssl-5.7.6 ] || {
		echo "building wolfssl"
		curl "$wolfsslurl" | tar xz
		cd wolfssl-5.7.6/
		./configure --prefix=$outdir --host=x86_64-linux-gnu --target=x86_64-linux-musl --enable-opensslextra
		make && make install
		cd ..
	}
	[ -d tiny-curl-8.4.0 ] || {
		echo "building tinycurl"
		curl "$curlurl" | tar xz
		cd tiny-curl-8.4.0/
		./configure --prefix=$outdir --host=x86_64-linux-gnu --target=x86_64-linux-musl --with-wolfssl --disable-libcurl-option --disable-static
		make && make install
		cd ..
	}
	stage_done "after-boot-packages"
fi

stage_start "platform-post"
if ! check_stamp "platform-post"; then
	echo "Running platform-specific post-install for $PLATFORM"
	postinstall="scripts/post-install-$PLATFORM.sh"
	if [ -f "$postinstall" ]; then
		# shellcheck disable=SC1090
		. "$postinstall"
	else
		echo "No platform-specific post-install script for $PLATFORM"
	fi
	sudo scripts/umounts.sh
	stage_done "platform-post"
fi

stage_start "archive"
if ! check_stamp "archive"; then
	echo "Compressing rootfs..."
	(
		cd rootfs
		tar cfJ "../rootfs-$PLATFORM.tar.xz" .
	)
	stage_done "archive"
fi

echo ""
echo "Build complete: rootfs-$PLATFORM.tar.xz"
echo "done"
echo ""
