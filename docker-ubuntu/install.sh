#!/bin/bash -e
apt update -y
apt upgrade -y
apt install -y build-essential libreadline-dev unzip rlwrap git wget curl

git clone https://luajit.org/git/luajit.git
cd luajit
make
make install
cd ../

git clone https://github.com/luarocks/luarocks.git
cd luarocks
./configure --force-config --with-lua-interpreter=luajit --lua-version=5.1
make
make install
cd ../
eval $(luarocks path --bin)
bash -c 'echo "eval \"\$(luarocks path --bin)\"" >> /etc/profile'
ln -s /usr/local/bin/luajit /usr/local/bin/lua

apt install -y libssl-dev libsodium-dev libsnappy-dev libpcre3-dev libmongoc-dev libbson-dev

luarocks make --server rocks
