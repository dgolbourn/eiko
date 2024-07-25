local lu = require "luaunit"

Test = {}

function Test:test_config()
    local config = require "eiko.config"
    lyaml = require "lyaml"
    print(lyaml.dump{config})
end

os.exit(lu.LuaUnit.run())
