#!/bin/bash
.devcontainer/scripts/generate_key_cert.sh

luarocks make --local --server rocks

.devcontainer/scripts/create_db.lua

luarocks test --local 

luacheck src || true
