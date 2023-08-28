#!/bin/bash
sudo apt update -y
sudo apt install build-essential libreadline-dev unzip libssl-dev rlwrap

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
sudo bash -c 'echo "eval \"\$(luarocks path)\"" >> /etc/profile'
cd ../
