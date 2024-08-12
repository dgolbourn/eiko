local lu = require "luaunit"

Test = {}

function Test:test_config()
    local config = require "eiko.config"
    local lyaml = require "lyaml"
    print(lyaml.dump{config.load("res/server.yaml")})
    print(lyaml.dump{config.load("res/authenticator.yaml")})
    print(lyaml.dump{config.load("res/client.yaml")})
end

os.exit(lu.LuaUnit.run())
