#!/bin/bash
TEST_DIR=$1
shift
export LUATEST_OPTIONS=$*
echo "Test fixture search path: $TEST_DIR"
echo "Luatest options: $LUATEST_OPTIONS"
echo
run_tests(){
    echo "Test file: $1"
    luajit $1 $LUATEST_OPTIONS
    echo
    return 0
}
export -f run_tests
find $TEST_DIR -type f -name "test_*.lua" | xargs -l bash -c 'run_tests "$@"' _
