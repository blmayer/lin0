#!/bin/sh

# running inside chroot
echo "building target system"

ARCH=$(uname -m)
case "$ARCH" in
arm64) ARCH=aarch64 ;;
esac
LDSO="${MUSL_LDSONAME:-ld-musl-${ARCH}.so.1}"
LDSO_PATH="/lib/$LDSO"

# create missing links
cd /
ln -srv lib/libc.so bin/ldd
ln -srv lib/libc.so bin/ld

echo "building target tcc (interp $LDSO_PATH)..."
cd /tmp/tinycc

./configure --prefix=/ \
	--cc=tcc \
	--extra-ldflags="-Wl,-dynamic-linker,${LDSO_PATH}" \
	--sysincludepaths=/include \
	--config-musl \
	--libpaths='{B}:/lib' \
	--elfinterp="${LDSO_PATH}" \
	--crtprefix=/lib \
	--tccdir=/lib/tcc \
	--config-bcheck=no
# Ensure dynamic musl link (configure may default LDFLAGS=-static for *gcc* names).
sed -i "s|^LDFLAGS=.*|LDFLAGS=-Wl,-dynamic-linker,${LDSO_PATH}|" config.mak
# Drop a previous flat tccdir=/lib install if present.
rm -f /lib/libtcc1.a /lib/runmain.o /lib/bt-exe.o /lib/bt-log.o /lib/bt-dll.o /lib/bcheck.o
rm -rf /lib/include
make && make install
# Keep argv0 as tcc so libtool matches tcc*); POSIX cc is a symlink.
ln -sfn tcc /bin/cc
ln -sfn libc.so "$LDSO_PATH"
printf '%s\n' '#!/bin/sh' 'tcc -ar "$@"' > /bin/ar
printf '%s\n' '#!/bin/sh' 'exec true' > /bin/ranlib
chmod +x /bin/ar /bin/ranlib
cd ..
