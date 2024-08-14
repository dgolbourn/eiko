#!/bin/bash
UCRT=ucrt64/mingw-w64-ucrt-x86_64-
pacman -S ${UCRT}openssl ${UCRT}libsodium ${UCRT}snappy ${UCRT}libyaml ${UCRT}zeromq
pacman -S pcre-devel
