local lu = require('luaunit')

TestEiko = {}

function TestEiko:test_smoke()
    lu.assertTrue(false)
    require('eiko')
end

os.exit(lu.LuaUnit.run())