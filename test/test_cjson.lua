local lu = require "luaunit"

Test = {}

function Test:test_cjson()
    local cjson = require "cjson"
    text = cjson.encode({a={"blah"}})
    value = cjson.decode(text)
end

os.exit(lu.LuaUnit.run())
