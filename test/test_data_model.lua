local lu = require "luaunit"

Test = {}

function Test:test_command()
    local data_model = require "eiko.data_model"
    local message1 = assert(data_model.command1.decode('{"_kind":"command1","foo":"foo"}'))
    local expected_message1 = {_kind="command1",foo="foo"}
    lu.assertEquals(message1, expected_message1)
end

os.exit(lu.LuaUnit.run())
