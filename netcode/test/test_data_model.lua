local lu = require "luaunit"

Test = {}

function Test:test_command()
    local data_model = require "eiko.data_model"
    local message1 = assert(data_model.server_stream_response.decode('{"_kind":"server_stream_response"}'))
    local expected_message1 = {_kind="server_stream_response"}
    lu.assertEquals(message1, expected_message1)
end

os.exit(lu.LuaUnit.run())
