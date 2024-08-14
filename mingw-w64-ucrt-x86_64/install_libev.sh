#!/bin/bash
wget -O /tmp/libev.zip http://dist.schmorp.de/libev/libev-4.33.tar.gz
tar -xvzf /tmp/libev.zip -C /tmp
cd /tmp/libev-4.33
./autogen.sh
./configure --enable-static=no LIBS=-lws2_32
make LDFLAGS=-no-undefined
make install
cd -
