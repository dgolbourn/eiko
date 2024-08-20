local lu = require "luaunit"

Test = {}

function Test:test_snappy()
    local snappy = require "resty.snappy"
    local data = "testtest"
    local uncomp, err = snappy.uncompress(snappy.compress(data))
    lu.assertEquals(uncomp, data)
end

os.exit(lu.LuaUnit.run())
