local lu = require "luaunit"

Test = {}

function Test:test_config()
    local config = require "eiko.config"
    local yaml = require "yaml"
    yaml.dump(config.load("res/server.yaml"))
    yaml.dump(config.load("res/authenticator.yaml"))
    yaml.dump(config.load("res/client1.yaml"))
    yaml.dump(config.load("res/client2.yaml"))
    yaml.dump(config.load("res/client3.yaml"))
end

os.exit(lu.LuaUnit.run())
