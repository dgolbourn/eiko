local context = require "context"

local cc = require "eiko.command"
cc.start()

local se = require "eiko.event"
se.start()

local ra = require "eiko.authenticator"
ra.start()

local game = require "eiko.game"
game.start()

local ev = require "ev"

local function on_sigint_event(loop, sig, revents)
    ra.stop()
    se.stop()
    cc.stop()
    game.stop()
    ev.Loop.default:unloop()
end
local signal_watcher = ev.Signal.new(on_sigint_event, signal.SIGINT)
signal_watcher:start(ev.Loop.default)

-- local function on_idle_event(loop, idle, revents)
--     print("idle")
--     collectgarbage()
-- end
-- local idle_watcher = ev.Idle.new(on_idle_event)
-- idle_watcher:start(ev.Loop.default)

ev.Loop.default:loop()
