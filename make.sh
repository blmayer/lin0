#!/bin/sh

set -e

muslurl="https://musl.libc.org/releases/musl-1.2.5.tar.gz"
tccurl="https://download.savannah.gnu.org/releases/tinycc/tcc-0.9.27.tar.bz2"
linuxurl="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.9.4.tar.xz"
librelslurl="https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/libressl-3.9.2.tar.gz"
toyboxurl="https://github.com/landley/toybox/archive/refs/heads/master.zip"
mkshurl="http://www.mirbsd.org/MirOS/dist/mir/mksh/mksh-R59c.tgz"

mkdir build
cd build

echo "building musl..."
curl -O "$muslurl"
musl="$(basename "$muslurl")"
tar xf "$musl"
cd "${musl%%\.*}"
./configure --prefix ../../rootfs
make && make install
make obj/musl-gcc
sed -i "s/ld-musl-$arch.so.1/libc.so/" lib/musl-gcc.specs
CC="$PWD/obj/musl-gcc"
ln -sv ../../rootfs/lib/libc.so ../../rootfs/bin/ldd
ln -sv ../../rootfs/lib/libc.so ../../rootfs/bin/ld
cd ..

echo "building tcc..."
curl -O "$tccurl"
tar xf "$(basename "$tccurl")"
cd tinycc-mob
CC="$CC -static -no-pie" ./configure --prefix=/home/lord/distro/rootfs --enable-static --config-musl --elfinterp=/lib/libc.so --sysincludepaths=/include --libpaths=/lib --crtprefix=/lib
make && make install
cat << EOF > ../../rootfs/bin/ar
#!/bin/sh
cc -ar $@
EOF
cd ..

# TODO: test
# echo "testing tcc..."

echo "installing linux headers..."
case "$platform" in
	"rpi"*) linuxurl="$rpilinuxurl" ;;
esac
curl -O "$linuxurl"
linux="$(basename "$linuxurl")"
tar xf "$linux"
cd "${linux-rpi%%\.*}"
cp ../../configs/"$platform"-linux .config
make INSTALL_HDR_PATH=../../rootfs headers_install
cd ..

echo "building libressl"
curl -O "$libretlsurl"
tar xf "$(basename "$libretlsurl")"
libretls="$(basename "$libretlsurl")"
cd "$libretls/"
./configure --prefix /home/lord/distro/rootfs
make
cd ..

echo "installing toybox..."
curl -O "$toyboxurl"
toybox="$(basename "$toyboxurl")"
cd "$toybox"
cp ../../configs/"$platform"-toybox .config
make CC="$CC -L ../$libretls" toybox
make PREFIX=../../rootfs/bin install_flat
cd ..

echo "building mksh"
curl -O "$mkshurl"
tar xf "$(basename "$mkshurl")"
cd mksh/
chmod +x Build.sh 
./Build.sh
install -c -s -g bin -m 555 mksh ../rootfs/bin/sh
cd ..

echo "runnning specific platform commands"
../scripts/"post-install-$platform.sh"

echo "copying files"
cp ../files/{passwd,issue,profile,shells,login.defs} ../rootfs/etc
cp ../files/init ../rootfs/sbin


echo "compressing rootfs..."
cd ../
tar cf rootfs.tar.gz rootfs/*
