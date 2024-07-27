local lu = require "luaunit"

Test = {}

function Test:test_signal()
    local signal = require "signal"
    print(signal.SIGUSR1)
    signal.signal(signal.SIGUSR2, function() end)
    signal.raise(signal.SIGUSR2)
end

function Test:test_signals()
    local signals = require "signals"
    print(signals.realtime(5))
    signals.signal(signals.realtime(5), "ignore")
    signals.raise(signals.realtime(5))
end

os.exit(lu.LuaUnit.run())
