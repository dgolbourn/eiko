local cjson = require "cjson.safe"
local jsonschema = require "jsonschema"
local log = require "eiko.logs".defaultLogger()
local lfs = require "lfs"

local function resolver(url)
    local id = string.sub(url, 6,-1)
    local schema_path = "res/schemas/" .. id .. ".json"
    local f = assert(io.open(schema_path, "rb"))
    local data = f:read("*all")
    f:close()
    local schema = cjson.decode(data)
    return schema
end

local function kind(schema)
    if schema.properties then
        return schema.properties._kind.const
    end
end

local function schema_validator(url)
    local schema = resolver(url)
    local validator, err = jsonschema.generate_validator(schema, {external_resolver = resolver})
    if validator then
        local _decode = function(obj) return obj end
        local _encode = function(obj) return obj end
        if schema["$comment"] == "string" then
            _decode = cjson.decode
            _encode = cjson.encode
        end
        local decode = function(message)
            local json, err = _decode(message)
            if json then
                local valid, err = validator(json)
                if valid then
                    return json
                end
                return nil, err
            else 
                return nil, err                
            end
        end
        local kind = kind(schema)
        log:debug("resolved " .. url)
        return {decode = decode, encode = _encode, kind = kind}
    end
    return nil, err
end

function build()
    local data_model = {}
    for file in lfs.dir("res/schemas") do
        if file ~= "." and file ~= ".." then
            local id = string.sub(file, 1,-6)
            data_model[id] = assert(schema_validator("root:" .. id))
        end
    end
    return data_model
end

return build()
