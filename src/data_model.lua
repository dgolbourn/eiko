local cjson = require "cjson"
local jsonschema = require "jsonschema"
local log = require "eiko.logs".defaultLogger()

local function resolver(url)
    local id = string.sub(url, 6,-1)
    local schema_path = "res/" .. id .. ".json"
    local f = assert(io.open(schema_path, "rb"))
    local data = f:read("*all")
    f:close()
    local schema = cjson.decode(data)
    log:debug("resolved schema " .. id)
    return schema
end

local function json_schema_validator(url)
    local schema = resolver(url)
    local validator = jsonschema.generate_validator(schema, {external_resolver = resolver})
    local message_validator = function(text)
        local json = cjson.decode(text)
        if validator(json) then
            return json
        end
    end
    return message_validator
end

return {
    command = json_schema_validator("root:command"),
    event = json_schema_validator("root:event"),
}
