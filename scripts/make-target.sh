echo "building target system"

# create missing links
cd /
ln -srv lib/libc.so bin/ldd
ln -srv lib/libc.so bin/ld

echo "building target tcc..."
cd /tmp/tinycc

./configure --prefix=/ --cc=cc --sysincludepaths=/include --config-musl --libpaths=/lib --elfinterp=/lib/libc.so --crtprefix=/lib --tccdir=/lib
make && make install
mv /bin/tcc /bin/cc
cd ..

# FIXME
# echo "building target musl..."
# cd "musl-$muslver"
# ./configure --prefix=/ --enable-static
# #rm -rf src/complex
# make && make install


# echo "installing target toybox..."
# cd toybox
# cp ../../configs/"$PLATFORM"-toybox.config .config
# make toybox
# make PREFIX=/bin install_flat
# cd ..
# 
# echo "building target mksh"
# cd mksh/
# chmod +x Build.sh 
# ./Build.sh
# install -c -s -m 555 mksh /bin/sh
# install -c -m 444 -D lksh.1 mksh.1 $outdir/share/man/man1/
# cd ..
# 
# echo "building target bmake"
# curl "$bmakeurl" | tar xz
# cd bmake
# ./configure --prefix=/
# make && make install
# cd ..
