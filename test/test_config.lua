local lu = require "luaunit"

Test = {}

function Test:test_config()
    local config = require "eiko.config"
    local yaml = require "tinyyaml"
    local json = require "cjson.safe"
    print(json.encode(config.load("res/server.yaml")))
    print(json.encode(config.load("res/authenticator.yaml")))
    print(json.encode(config.load("res/client1.yaml")))
    print(json.encode(config.load("res/client2.yaml")))
    print(json.encode(config.load("res/client3.yaml")))
end

os.exit(lu.LuaUnit.run())
