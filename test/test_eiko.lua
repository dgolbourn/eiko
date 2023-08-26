local lu = require('luaunit')

TestEiko = {}
TestEiko.__class__ = 'TestEiko'

function TestEiko:test_smoke()
    lu.assertTrue(true)
    require('eiko')
end

os.exit(lu.LuaUnit.run())