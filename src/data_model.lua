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
        local kind = kind(schema)        
        local encode = function(obj)
            obj._kind = kind
            return _encode(obj) .. '\n'
        end
        local decode = function(message)
            local obj, err = _decode(message)
            if obj then
                local valid, err = validator(obj)
                if valid then
                    return obj
                end
                return nil, err
            else 
                return nil, err                
            end
        end
        local kindof = function(obj)
            return obj._kind == kind
        end
        log:debug("resolved " .. url)
        return {decode = decode, encode = encode, kindof = kindof}
    end
    return nil, err
end

local function build()
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
