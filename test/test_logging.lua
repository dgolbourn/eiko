local lu = require "luaunit"

Test = {}

function Test:test_logging()
    local log = require "eiko.logs".defaultLogger()
    log:debug("debug")
    log:info("info")
    log:warn("warn")
    log:error("error")
    log:fatal("fatal")
end

os.exit(lu.LuaUnit.run())
