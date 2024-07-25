local lu = require "luaunit"

Test = {}

function Test:test_cjson()
    local cjson = require "cjson"
    data = {a={"blah"}}
    text = cjson.encode(data)
    decoded_data = cjson.decode(text)
    lu.assertEquals(data, decoded_data)
end

function Test:test_jsonschema()
    local jsonschema = require 'jsonschema'
    local schema = {
        type = 'object',
        properties = {
            foo = { type = 'string' },
            bar = { type = 'number' },
        },
    }
    local validator = jsonschema.generate_validator(schema)
    data = { foo='hello', bar=42 }
    valid = validator(data)
    lu.assertEquals(valid, true)
end

os.exit(lu.LuaUnit.run())
