#!/bin/sh

# running inside chroot
echo "building target system"

# PT_INTERP is /lib/libc.so. --config-musl would otherwise default to
# ld-musl-$ARCH.so.1, and only when --elfinterp was left empty.
# create missing links
cd /
ln -srv lib/libc.so bin/ldd
ln -srv lib/libc.so bin/ld

echo "building target tcc (interp /lib/libc.so)..."
cd /tmp/tinycc

./configure --prefix=/ \
	--cc=tcc \
	--extra-ldflags="-Wl,-dynamic-linker,/lib/libc.so" \
	--sysincludepaths=/include \
	--config-musl \
	--libpaths='{B}:/lib' \
	--elfinterp=/lib/libc.so \
	--crtprefix=/lib \
	--tccdir=/lib/tcc \
	--config-bcheck=no
# Ensure dynamic musl link (configure may default LDFLAGS=-static for *gcc* names).
sed -i 's|^LDFLAGS=.*|LDFLAGS=-Wl,-dynamic-linker,/lib/libc.so|' config.mak
# Drop a previous flat tccdir=/lib install if present.
rm -f /lib/libtcc1.a /lib/runmain.o /lib/bt-exe.o /lib/bt-log.o /lib/bt-dll.o /lib/bcheck.o
rm -rf /lib/include
make && make install
# Keep argv0 as tcc so libtool matches tcc*); POSIX cc is a symlink.
ln -sfn tcc /bin/cc
printf '%s\n' '#!/bin/sh' 'tcc -ar "$@"' > /bin/ar
printf '%s\n' '#!/bin/sh' 'exec true' > /bin/ranlib
chmod +x /bin/ar /bin/ranlib
cd ..
