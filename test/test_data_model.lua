local lu = require "luaunit"

Test = {}

function Test:test_command()
    local data_model = require "eiko.data_model"
    local message1 = assert(data_model.client_ack_action.decode('{"_kind":"client_ack_action"}'))
    local expected_message1 = {_kind="client_ack_action"}
    lu.assertEquals(message1, expected_message1)
end

os.exit(lu.LuaUnit.run())
