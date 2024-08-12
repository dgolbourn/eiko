local lyaml = require "lyaml"


local function load(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*all")
    local config = lyaml.load(data)
    file:close()
    return config
end

return {
    load = load
}
