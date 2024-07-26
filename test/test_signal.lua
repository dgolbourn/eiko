local lu = require "luaunit"

Test = {}

function Test:test_signal()
    local signal = require "signal"
    print(signal.SIGUSR1)
    signal.raise(signal.SIGUSR1)
end

os.exit(lu.LuaUnit.run())
