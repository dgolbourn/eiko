#!/bin/bash
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y build-essential libreadline-dev unzip rlwrap

git clone https://luajit.org/git/luajit.git
cd luajit
make
sudo make install
cd ../

git clone https://github.com/luarocks/luarocks.git
cd luarocks
./configure --force-config --with-lua-interpreter=luajit --lua-version=5.1
make
sudo make install
cd ../
eval $(luarocks path --bin)
sudo bash -c 'echo "eval \"\$(luarocks path --bin)\"" >> /etc/profile'
sudo ln -s /usr/local/bin/luajit /usr/local/bin/lua

sudo apt install -y libssl-dev libsodium-dev libsnappy-dev libpcre3-dev libmongoc-dev libbson-dev

luarocks make --server rocks --local
