local lu = require "luaunit"

Test = {}

function Test:test_context()
    local context = require "eiko.context"
    local old_var = 1
	context:send( 0, "var", old_var)
	local key, new_var = context:receive( 0, "var")
    lu.assertEquals(old_var, new_var)
end

os.exit(lu.LuaUnit.run())
