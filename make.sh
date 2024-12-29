#!/bin/sh

set -e
arch="$(uname -m)"

muslver="1.2.5"
linuxver="6.12.7"

muslurl="https://musl.libc.org/releases/musl-$muslver.tar.gz"
tccurl="https://repo.or.cz/tinycc.git"
linuxurl="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$linuxver.tar.xz"
toyboxurl="https://github.com/landley/toybox.git"
mkshurl="http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R59c.tgz"
bashurl="https://ftp.gnu.org/gnu/bash/bash-5.2.37.tar.gz"
makeurl="https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz"
bmakeurl="https://www.crufty.net/ftp/pub/sjg/bmake.tar.gz"
curlurl="https://curl.se/tiny/tiny-curl-8.11.0.tar.xz"
dashurl="http://gondor.apana.org.au/~herbert/dash/files/dash-0.5.12.tar.gz"

[ -z "$PLATFORM" ] && PLATFORM="generic-$(uname -m)"

export outdir="$(pwd)/rootfs"

[ -d build ] || mkdir build
[ -d rootfs ] || mkdir -p rootfs
cd build

[ -d "musl-$muslver" ] || {
	echo "building host musl..."
	curl "$muslurl" | tar xz
	musl="$(basename "$muslurl")"
	cd "musl-$muslver"
	./configure --prefix=$outdir --enable-static
	make && make install

	cd ..
}

export CC="$outdir/bin/musl-gcc" 

[ -d "linux-$linuxver" ] || {
	echo "installing linux headers..."
	case "$PLATFORM" in
		"rpi"*) linuxurl="$rpilinuxurl" ;;
	esac
	curl -O "$linuxurl"
	linux="$(basename "$linuxurl")"
	tar xf "$linux"
	case "$PLATFORM" in
		"rpi"*) cd "${linux-rpi%%\.*}" ;;
		*) cd "linux-$linuxver" ;;
	esac
	cp ../configs/"$PLATFORM"-linux.config .config
	make bzImage INSTALL_HDR_PATH=$outdir $INSTALL_PATH=$outdir/boot INSTALL_MOD_PATH=$outdir install headers_install modules_install
	cd ..
}

[ -d "toybox" ] || {
	echo "installing host toybox..."
	git clone "$toyboxurl"
	cp ../configs/"$PLATFORM"-toybox.config toybox/.config
	cd toybox
	make LDFLAGS='-static --no-pie' toybox
	make PREFIX=$outdir/bin install_flat
	cd ..
}

export CC="$CC -static --no-pie" 

[ -d "make-4.4.1" ] || {
	echo "building host make"
	curl "$makeurl" | tar xz
	cd make-4.4.1/
	./configure --prefix=$outdir --host=x86_64-linux-gnu --target=x86_64-linux-musl
	make && make install
	cd ..
}

[ -d "mksh" ] || {
       echo "building host shell"
       curl "$mkshurl" | tar xz
       cd mksh/
       chmod +x Build.sh 
       ./Build.sh
       install -c -s -m 555 mksh ../../rootfs/bin/sh
       install -c -m 444 -D lksh.1 mksh.1 ../../rootfs/share/man/man1/
       cd ..
}

[ -d "tinycc" ] || {
	echo "building host tcc..."
	git clone "$tccurl"
	cd "tinycc"
	
	# --config-static is needed because it is compiled for musl
	./configure --prefix=/ \
		--sysincludepaths=$outdir/include \
		--libpaths=$outdir/lib \
		--crtprefix=$outdir/lib \
		--elfinterp=$outdir/lib/libc.so \
		--config-static --config-bcheck=no --disable-rpath --config-musl
	make && make DESTDIR=$outdir install
	cat <<- EOF > $outdir/bin/ar
	#!/bin/sh
	tcc -ar \$@
	EOF
	chmod +x $outdir/bin/ar
	cd ..
	rm -rf tinycc
}

export CC="$outdir/bin/tcc -static"

[ -d "tinycc" ] || {
	echo "building host tcc - pass 2"
	git clone "$tccurl"
	cd "tinycc"
	
	#echo "applying patch"
	#git apply ../../patches/tcc-*.patch
	
	./configure --prefix=/ \
		--sysincludepaths=$outdir/include:/include \
		--libpaths=$outdir/lib:/lib \
		--crtprefix=/lib \
		--ar="$outdir/bin/tcc -ar" \
		--elfinterp=/lib/libc.so \
		--config-static --config-bcheck=no --disable-rpath --config-musl
	make && make DESTDIR=$outdir install
	mv $outdir/bin/tcc $outdir/bin/cc
	cd ..
}

cd ..  # back to lin0 dir

echo ""
echo "creating directories" 
echo ""
mkdir -p rootfs/sbin rootfs/etc rootfs/home/root rootfs/dev/pts rootfs/proc rootfs/sys rootfs/tmp

echo ""
echo "extracting sources to target" 
echo ""
cp script/make-target.sh rootfs/tmp
cd rootfs/tmp
git clone "$tccurl"
curl "$muslurl" | tar xz
git clone "$toyboxurl"
curl "$mkshurl" | tar xz
curl "$bmakeurl" | tar xz
curl "$curlurl" | tar xz
curl "$linuxurl" | tar xz
cd ../../ # back to lin0 dir
$(./scripts/chroot.sh)

echo ""
echo "runnning specific platform commands"
echo ""
postinstall="scripts/post-install-$PLATFORM.sh"
[ -f "$postinstall" ] && . "$postinstall"

echo ""
echo "copying files"
echo ""
cp -r etc rootfs/etc
cp init rootfs/sbin


echo ""
echo "cleaning up some files"
echo ""
rm rootfs/lib/musl-gcc.specs
rm rootfs/bin/musl-gcc
rm -rf rootfs/tmp/*

echo ""
echo "compressing rootfs..."
echo ""
tar cfJ "rootfs-$PLATFORM.tar.xz" rootfs/*
