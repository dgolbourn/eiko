#!/bin/bash
sudo apt update -y
sudo apt install -y build-essential libreadline-dev unzip libssl-dev rlwrap libsodium-dev libsnappy-dev

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

sudo bash -c 'echo "eval \"\$(luarocks path --bin)\"" >> /etc/profile'
sudo ln -s /usr/local/bin/luajit /usr/local/bin/lua
