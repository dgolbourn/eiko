#!/bin/bash

echo "eval \"\$(luarocks path)\"" >> ~/.bashrc
source ~/.bashrc

luarocks make --local
