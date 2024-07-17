local lu = require('luaunit')
local lu = require('socket')

TestEiko3 = {}

function TestEiko3:test_smoke()
    lu.assertTrue(true)
    require('eiko')
end

os.exit(lu.LuaUnit.run())