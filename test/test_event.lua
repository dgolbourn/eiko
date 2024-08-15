local lu = require "luaunit"

Test = {}

function Test:test_event()
    local event = require "eiko.event".event()
    local function timer_watcher()
        event.unloop()
    end
    local watcher = event.timer(0.1, timer_watcher)
    watcher.start()
    event.loop()
end

os.exit(lu.LuaUnit.run())
