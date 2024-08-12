local lu = require "luaunit"

Test = {}

local function signal_watcher(loop, sig, revents)
    sig:stop(ev.Loop.default)
    print("received")
end

local function timer_watcher(loop, timer, revents)
    local signal = require "signal"
    timer:stop(ev.Loop.default)
    local watcher = ev.Signal.new(signal_watcher, 37)
    watcher:start(ev.Loop.default)
    signal.raise(37)
end

function Test:test_ev()
    local ev = require "ev"
    local watcher = ev.Timer.new(timer_watcher, 0.1, 0.1)
    watcher:start(ev.Loop.default)
    ev.Loop.default:loop()
end

os.exit(lu.LuaUnit.run())
