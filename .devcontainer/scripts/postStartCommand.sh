#!/bin/bash
.devcontainer/scripts/generate_key_cert.sh

luarocks make --local --server rocks

