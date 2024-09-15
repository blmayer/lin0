#!/bin/sh

set -e
arch="$(uname -m)"

muslver="1.2.5"
tccver="0.9.27"
linuxver="6.11"
sslver="3.9.2"

muslurl="https://musl.libc.org/releases/musl-$muslver.tar.gz"
tccurl="https://mirror.marwan.ma/savannah/tinycc/tcc-$tccver.tar.bz2"
linuxurl="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$linuxver.tar.xz"
toyboxurl="https://codeload.github.com/landley/toybox/zip/refs/heads/master"
mkshurl="http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R59c.tgz"

[ -d build ] || mkdir build
cd build

[ -d "musl-$muslver" ] || {
	echo "building musl..."
	curl "$muslurl" | tar xz
	musl="$(basename "$muslurl")"
	cd "musl-$muslver"
	./configure --prefix=../../rootfs
	make && make install
	make obj/musl-gcc
	sed -i "s@ld-musl-$arch.so.1@libc.so@" ../../rootfs/lib/musl-gcc.specs
	cd ..
}

export CC="$(realpath ../rootfs/bin/musl-gcc)"

[ -d "tcc-$tccver" ] || {
	echo "building tcc..."
	curl "$tccurl" | tar xj
	cd "tcc-$tccver"
	./configure --prefix=/home/lord/git/lin0/rootfs --cc="$CC -static -no-pie" --enable-static --config-musl --elfinterp=/lib/libc.so --sysincludepaths=/include --libpaths=/lib --crtprefix=/lib
	make && make install
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

[ -d "toybox-master" ] || {
	echo "installing toybox..."
	curl "$toyboxurl" > toybox.zip
	unzip toybox.zip
	cd toybox-master
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
	install -c -m 444 lksh.1 mksh.1 ../../rootfs/share/man/man1/
	cd ..
}

# create missing links
ln -sv ../rootfs/lib/libc.so ../rootfs/bin/ldd
ln -sv ../rootfs/lib/libc.so ../rootfs/bin/ld

echo "runnning specific platform commands"
postinstall="../scripts/post-install-$platform.sh"
[ -f "$postinstall" ] && . "$postinstall"
cd ../

echo "copying files"
mkdir rootfs/etc rootfs/sbin
cp -r etc rootfs/etc
cp init rootfs/sbin

echo "copying extra packages"
mkdir -p rootfs/share/pkg
for pkg in $(find pkgs)
do
	cp pkgs/"$pkg" rootfs/share/pkg
done

echo "compressing rootfs..."
tar cfJ "rootfs-$arch.tar.xz" rootfs/*
