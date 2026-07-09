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
	--extra-ldflags='-Wl,-dynamic-linker,/lib/ld-musl-aarch64.so.1' \
	--sysincludepaths=/include \
	--config-musl \
	--libpaths='{B}:/lib' \
	--elfinterp=/lib/ld-musl-aarch64.so.1 \
	--crtprefix=/lib \
	--tccdir=/lib/tcc \
	--config-bcheck=no
# Ensure dynamic musl link (configure may default LDFLAGS=-static for *gcc* names).
sed -i 's|^LDFLAGS=.*|LDFLAGS=-Wl,-dynamic-linker,/lib/ld-musl-aarch64.so.1|' config.mak
# Drop a previous flat tccdir=/lib install if present.
rm -f /lib/libtcc1.a /lib/runmain.o /lib/bt-exe.o /lib/bt-log.o /lib/bt-dll.o /lib/bcheck.o
rm -rf /lib/include
make && make install
# Keep argv0 as tcc so libtool matches tcc*); POSIX cc is a symlink.
ln -sfn tcc /bin/cc
ln -sfn libc.so /lib/ld-musl-aarch64.so.1
printf '%s\n' '#!/bin/sh' 'tcc -ar "$@"' > /bin/ar
printf '%s\n' '#!/bin/sh' 'exec true' > /bin/ranlib
chmod +x /bin/ar /bin/ranlib
cd ..
