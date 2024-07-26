local lu = require "luaunit"

Test = {}

function Test:test_lanes()
    local lanes = require "lanes"
    local linda = lanes.linda()
    local old_var = 1
	linda:send( 3.0, "var", old_var)
	local key, new_var = linda:receive( 3.0, "var")
    lu.assertEquals(old_var, new_var)
end

os.exit(lu.LuaUnit.run())
