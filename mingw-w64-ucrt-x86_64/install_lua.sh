#!/bin/bash
UCRT=ucrt64/mingw-w64-ucrt-x86_64-
pacman -S ${UCRT}luajit ${UCRT}lua-luarocks
ln -s /ucrt64/bin/luajit.exe /ucrt64/bin/lua5.1.exe
ln -s /ucrt64/include/luajit-2.1 /ucrt64/include/lua5.1
