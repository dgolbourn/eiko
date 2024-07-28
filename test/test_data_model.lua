local lu = require "luaunit"

Test = {}

function Test:test_ack()
    local data_model = require "eiko.data_model"
    local actual_ack = assert(data_model.event('[{"_kind":"ack","counter":1}]'))
    local expected_ack = {{_kind="ack",counter=1}}
    lu.assertEquals(actual_ack, expected_ack)
end

function Test:test_command()
    local data_model = require "eiko.data_model"
    local message1 = assert(data_model.command('[{"_kind":"command1","foo":"foo"}]'))
    local expected_message1 = {{_kind="command1",foo="foo"}}
    lu.assertEquals(message1, expected_message1)

    local data_model = require "eiko.data_model"
    local message2 = assert(data_model.command('[{"_kind":"command2","bar":"bar"}]'))
    local expected_message2 = {{_kind="command2",bar="bar"}}
    lu.assertEquals(message2, expected_message2)
end

os.exit(lu.LuaUnit.run())
