#!/bin/sh

set -e
arch="$(uname -m)"

muslver="1.2.5"
linuxver="6.11"

muslurl="https://musl.libc.org/releases/musl-$muslver.tar.gz"
tccurl="https://repo.or.cz/tinycc.git"
linuxurl="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$linuxver.tar.xz"
toyboxurl="https://github.com/landley/toybox.git"
mkshurl="http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R59c.tgz"

[ -d build ] || mkdir build
cd build

[ -d "musl-$muslver" ] || {
	echo "building musl..."
	curl "$muslurl" | tar xz
	musl="$(basename "$muslurl")"
	cd "musl-$muslver"
	./configure --prefix=../../rootfs --disable-static
	make && make install
	make obj/musl-gcc
	sed -i "s@ld-musl-$arch.so.1@libc.so@" ../../rootfs/lib/musl-gcc.specs

	# create missing links
	ln -srv ../../rootfs/lib/libc.so ../../rootfs/bin/ldd
	ln -srv ../../rootfs/lib/libc.so ../../rootfs/bin/ld

	cd ..
}

export CC="$(realpath ../rootfs/bin/musl-gcc)"

[ -d "tinycc" ] || {
	echo "building tcc..."
	git clone "$tccurl"
	cd "tinycc"
	
	echo "applying patch"
	git apply ../../patches/tcc-*.patch

	./configure --prefix=/ --cc="$CC" --config-musl --elfinterp=/lib/libc.so --sysincludepaths=/include --libpaths=/lib --crtprefix=/lib --disable-static --disable-rpath
	make && make DESTDIR=../../rootfs install
	cat <<- EOF > ../../rootfs/bin/ar
	#!/bin/sh
	cc -ar $@
	EOF
	chmod +x ../../rootfs/bin/ar
	cd ..
}

# TODO: test
# echo "testing tcc..."

[ -d "linux-$linuxver" ] || {
	echo "installing linux headers..."
	case "$platform" in
		"rpi"*) linuxurl="$rpilinuxurl" ;;
	esac
	curl -O "$linuxurl"
	linux="$(basename "$linuxurl")"
	tar xf "$linux"
	case "$platform" in
		"rpi"*) cd "${linux-rpi%%\.*}" ;;
		*) cd "linux-$linuxver" ;;
	esac
	cp ../../configs/"$platform"-linux.config .config
	make INSTALL_HDR_PATH=../../rootfs headers_install
	cd ..
}

[ -d "toybox" ] || {
	echo "installing toybox..."
	git clone "$toyboxurl"
	cd toybox
	cp ../../configs/"$platform"-toybox.config .config
	make toybox
	make PREFIX=../../rootfs/bin install_flat
	cd ..
}


[ -d "mksh" ] || {
	echo "building mksh"
	curl "$mkshurl" | tar xz
	cd mksh/
	chmod +x Build.sh 
	./Build.sh
	install -c -s -m 555 mksh ../../rootfs/bin/sh
	install -c -m 444 -D lksh.1 mksh.1 ../../rootfs/share/man/man1/
	cd ..
}

echo "runnning specific platform commands"
postinstall="../scripts/post-install-$platform.sh"
[ -f "$postinstall" ] && . "$postinstall"
cd ../

echo "copying files"
mkdir -p rootfs/etc rootfs/sbin rootfs/dev rootfs/sys rootfs/proc rootfs/var/run rootfs/home/root
cp -r etc rootfs/etc
cp init rootfs/sbin

echo "copying extra packages"
[ -f pkgs/* ] && {
	mkdir -p rootfs/share/pkg
	for pkg in $(find pkgs)
	do
		cp pkgs/"$pkg" rootfs/share/pkg
	done
}

echo "cleaning up some files"
rm rootfs/lib/musl-gcc.specs
rm rootfs/bin/musl-gcc

echo "compressing rootfs..."
tar cfJ "rootfs-$platform.tar.xz" rootfs/*
