#!/bin/bash -xe
.devcontainer/scripts/generate_key_cert.sh
luarocks make --local --server rocks
luarocks test --local
luacheck src || true
