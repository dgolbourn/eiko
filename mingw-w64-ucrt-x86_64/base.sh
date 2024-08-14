#!/bin/bash
pacman -Syuu
UCRT=ucrt64/mingw-w64-ucrt-x86_64-
pacman -S ${UCRT}toolchain libtool automake autoconf-wrapper make git
