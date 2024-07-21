local lu = require('luaunit')

TestEiko3 = {}

function TestEiko3:test_snappy()
    local snappy = require "resty.snappy"
    local uncomp, err = snappy.uncompress(snappy.compress("test"))
end

os.exit(lu.LuaUnit.run())
