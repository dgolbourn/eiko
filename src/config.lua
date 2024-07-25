local lyaml = require "lyaml"
local f = assert(io.open("res/config.yaml", "rb"))
local data = f:read("*all")
local config = lyaml.load(data)
f:close()

return config
