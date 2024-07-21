local lu = require "luaunit"

Test = {}

function Test:test_snappy()
    local snappy = require "resty.snappy"
    local uncomp, err = snappy.uncompress(snappy.compress("test"))
end

os.exit(lu.LuaUnit.run())
