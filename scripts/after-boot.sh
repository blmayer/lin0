#!/bin/sh


[ -d "wolfssl-5.7.6" ] || {
	echo "building wolfssl"
	curl "$wolfsslurl" | tar xz
	cd wolfssl-5.7.6/
	./configure --prefix=$outdir --host=x86_64-linux-gnu --target=x86_64-linux-musl --enable-opensslextra
	make && make install
	cd ..
}

[ -d "tiny-curl-8.4.0" ] || {
	echo "building tinycurl"
	curl "$curlurl" | tar xz
	cd tiny-curl-8.4.0/
	./configure --prefix=$outdir --host=x86_64-linux-gnu --target=x86_64-linux-musl --with-wolfssl --disable-libcurl-option --disable-static
	make && make install
	cd ..
}

