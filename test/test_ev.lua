local lu = require "luaunit"

Test = {}

local function callback(loop, timer_event)
    timer_event:stop(loop)
end

function Test:test_ev()
    ev = require "ev"
    local timer = ev.Timer.new(callback, 1, 1)
    timer:start(ev.Loop.default)
    ev.Loop.default:loop()
end

os.exit(lu.LuaUnit.run())