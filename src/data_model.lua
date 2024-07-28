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
    local validator, err = jsonschema.generate_validator(schema, {external_resolver = resolver})
    if validator then
        local message_validator = function(text)
            local json = cjson.decode(text)
            local valid, err = validator(json)
            if valid then
                return json
            end
            return nil, err
        end
        return message_validator
    end
    return nil, err
end

return {
    command = assert(json_schema_validator("root:command")),
    event = assert(json_schema_validator("root:event")),
}
