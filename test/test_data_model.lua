local lu = require "luaunit"

Test = {}

function Test:test_data_model()
    local data_model = require "eiko.data_model"
    local actual_ack = data_model.ack("[{\"ack\":1},{\"ack\":2}]")
    local expected_ack = {{ack=1},{ack=2}}
    lu.assertEquals(actual_ack, expected_ack)
end

os.exit(lu.LuaUnit.run())
