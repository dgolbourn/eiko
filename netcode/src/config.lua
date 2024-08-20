local yaml = require "tinyyaml"


local function load(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*all")
    file:close()
    local config = yaml.parse(data)
    return config
end

return {
    load = load
}
