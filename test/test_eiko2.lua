local lu = require('luaunit')

TestEiko2 = {}

function TestEiko2:test_smoke()
    lu.assertTrue(true)
    require('eiko')
end

os.exit(lu.LuaUnit.run())
