#!/bin/bash
TEST_DIR=$1
shift
export LUATEST_OPTIONS=$*
eval "\$(luarocks path --bin)"
echo
echo "Test fixture search path: $TEST_DIR"
echo "Luatest options: $LUATEST_OPTIONS"
echo
mkdir reports
run_tests(){
    echo "Test file: $1"
    lua $1 $LUATEST_OPTIONS
    STATUS=$?
    TEST_FILE=${1////_}
    mv *.xml reports/$TEST_FILE.xml
    echo
    return $STATUS
}
export -f run_tests
find $TEST_DIR -type f -name "test_*.lua" | xargs -l bash -c 'run_tests "$@"' _
