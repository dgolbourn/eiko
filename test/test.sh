#!/bin/bash
echo
find $(dirname "$0") -type f -name "test_*.lua" | xargs -l bash -c 'luajit "$@" --verbose && echo' dummy
