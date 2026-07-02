#!/bin/sh

# running inside chroot
echo "building target system"

# create missing links
cd /
ln -srv lib/libc.so bin/ldd
ln -srv lib/libc.so bin/ld

echo "building target tcc..."
cd /tmp/tinycc

./configure --prefix=/ \
	--cc=tcc \
	--sysincludepaths=/include \
	--config-musl \
	--libpaths=/lib \
	--elfinterp=/lib/libc.so \
	--crtprefix=/lib \
	--tccdir=/lib \
	--config-bcheck=no
make && make install
mv /bin/tcc /bin/cc
cd ..
