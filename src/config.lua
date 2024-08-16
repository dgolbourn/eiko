local yaml = require "yaml"


local function load(path)
    local file = assert(io.open(path, "rb"))
    local data = file:read("*all")
    local config = yaml.eval(data)
    file:close()
    return config
end

return {
    load = load
}
