local lu = require "luaunit"

Test = {}

function Test:test_ack()
    local data_model = require "eiko.data_model"
    local actual_ack = data_model.ack('{"ack":1}')
    local expected_ack = {ack=1}
    lu.assertEquals(actual_ack, expected_ack)
end

function Test:test_command()
    local data_model = require "eiko.data_model"
    local message1 = data_model.command('{"_kind":"message1","foo":"foo"}')
    local expected_message1 = {_kind="message1",foo="foo"}
    lu.assertEquals(actual_ack, expected_ack)

    local data_model = require "eiko.data_model"
    local message1 = data_model.command('{"_kind":"message2","bar":"bar"}')
    local expected_message1 = {_kind="message1",bar="bar"}
    lu.assertEquals(actual_ack, expected_ack)
end

os.exit(lu.LuaUnit.run())
