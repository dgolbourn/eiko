local cjson = require "cjson"
local jsonschema = require "jsonschema"

local function json_schema_validator(schema_path)
    local f = assert(io.open(schema_path, "rb"))
    local data = f:read("*all")
    local schema = cjson.decode(data)
    local validator = jsonschema.generate_validator(schema)
    f:close()
    local message_validator = function(text)
        local json = cjson.decode(text)
        if validator(json) then
            return json
        end
    end
    return message_validator
end

return {
    ack = json_schema_validator("res/ack.json")
}