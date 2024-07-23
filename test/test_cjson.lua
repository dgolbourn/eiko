local lu = require "luaunit"

Test = {}

function Test:test_cjson()
    local cjson = require "cjson"
    data = {a={"blah"}}
    text = cjson.encode(data)
    decoded_data = cjson.decode(text)
    lu.assertEquals(data, decoded_data)
end

os.exit(lu.LuaUnit.run())
