local lu = require "luaunit"

Test = {}

function Test:test_signal()
    local signal = require "signal"
    print(signal.SIGUSR1)
    signal.signal(signal.SIGUSR1, function() end)
    signal.raise(signal.SIGUSR1)
end

os.exit(lu.LuaUnit.run())
