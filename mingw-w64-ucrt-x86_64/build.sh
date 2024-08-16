#!/bin/bash
pacman --noconfirm -Syuu
UCRT=ucrt64/mingw-w64-ucrt-x86_64-
pacman --noconfirm -S ${UCRT}toolchain libtool automake autoconf-wrapper make git

pacman --noconfirm -S ${UCRT}luajit ${UCRT}lua-luarocks
ln -s /ucrt64/bin/luajit.exe /ucrt64/bin/lua5.1.exe
ln -s /ucrt64/include/luajit-2.1 /ucrt64/include/lua5.1

pacman --noconfirm -S ${UCRT}openssl ${UCRT}libsodium ${UCRT}snappy ${UCRT}pcre

luarocks --lua-version 5.1 make mingw-w64-ucrt-x86_64/eiko-win-1.rockspec --local PCRE_DIR=/usr

cp libatomic-1.dll ~/.luarocks/bin
cp libcrypto-3-x64.dll ~/.luarocks/bin
cp libgcc_s_seh-1.dll ~/.luarocks/bin
cp libgomp-1.dll ~/.luarocks/bin
cp libquadmath-0.dll ~/.luarocks/bin
cp libsnappy.dll ~/.luarocks/bin
cp libssl-3-x64.dll ~/.luarocks/bin
cp libstdc++-6.dll ~/.luarocks/bin
cp libsodium-26.dll ~/.luarocks/bin/sodium.dll
cp libpcre-1.dll ~/.luarocks/bin
cp libpcre16-0.dll ~/.luarocks/bin
cp libpcre32-0.dll ~/.luarocks/bin
cp libpcrecpp-0.dll ~/.luarocks/bin
cp libpcreposix-0.dll ~/.luarocks/bin
