#!/bin/bash
TEST_DIR=$1
shift
export LUATEST_OPTIONS=$*
echo "Searching for test fixtures in $TEST_DIR"
echo "Running luatest with options: $LUATEST_OPTIONS"
echo
run_tests(){
    echo "Test file: $1"
    luajit $1 $LUATEST_OPTIONS
    echo
    return 0
}
export -f run_tests
find $TEST_DIR -type f -name "test_*.lua" | xargs -l bash -c 'run_tests "$@"' _
