local lu = require "luaunit"
local lanes = require "lanes"

Test = {}

function Test:test_linda()
    local linda = lanes.linda()
    local old_var = 1
	linda:send( 3.0, "var", old_var)
	local key, new_var = linda:receive( 3.0, "var")
    lu.assertEquals(old_var, new_var)
end

function Test:test_lanes()
    local f = lanes.gen( function( n) return 2 * n end)
	local a = f( 1)
	local b = f( 2)
	print( a[1], b[1] )
    print(a.status)
end

os.exit(lu.LuaUnit.run())
