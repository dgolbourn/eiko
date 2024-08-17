#!/bin/bash -e
pacman --noconfirm -Syuu
UCRT=ucrt64/mingw-w64-ucrt-x86_64-
pacman --noconfirm -S ${UCRT}toolchain libtool automake autoconf-wrapper make git

pacman --noconfirm -S ${UCRT}luajit ${UCRT}lua-luarocks
ln -s /ucrt64/bin/luajit.exe /ucrt64/bin/lua5.1.exe
ln -s /ucrt64/include/luajit-2.1 /ucrt64/include/lua5.1

pacman --noconfirm -S ${UCRT}openssl ${UCRT}libsodium ${UCRT}snappy ${UCRT}pcre

luarocks --lua-version 5.1 make mingw-w64-ucrt-x86_64/eiko-win-1.rockspec --local --server rocks PCRE_DIR=/ucrt64 

cp -r ~/.luarocks eiko
cp /ucrt64/bin/luajit.exe eiko/bin
cp /ucrt64/bin/lua51.dll eiko/bin
cp /ucrt64/bin/libatomic-1.dll eiko/bin
cp /ucrt64/bin/libcrypto-3-x64.dll eiko/bin
cp /ucrt64/bin/libgcc_s_seh-1.dll eiko/bin
cp /ucrt64/bin/libgomp-1.dll eiko/bin
cp /ucrt64/bin/libquadmath-0.dll eiko/bin
cp /ucrt64/bin/libsnappy.dll eiko/bin
cp /ucrt64/bin/libssl-3-x64.dll eiko/bin
cp /ucrt64/bin/libstdc++-6.dll eiko/bin
cp /ucrt64/bin/libsodium-26.dll eiko/bin
cp /ucrt64/bin/libpcre-1.dll eiko/bin
cp /ucrt64/bin/libpcre16-0.dll eiko/bin
cp /ucrt64/bin/libpcre32-0.dll eiko/bin
cp /ucrt64/bin/libpcrecpp-0.dll eiko/bin
cp /ucrt64/bin/libpcreposix-0.dll eiko/bin
cp /ucrt64/bin/libwinpthread-1.dll eiko/bin
mv eiko/bin/libsodium-26.dll eiko/bin/sodium.dll
cp -r res eiko

zip -r eiko.zip eiko
