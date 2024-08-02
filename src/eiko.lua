local ev = require "ev"
local signal = require "signal"

local command = require "eiko.command"
command.start(ev.Loop.default)

local event = require "eiko.event"
event.start(ev.Loop.default)

local authenticator = require "eiko.authenticator"
authenticator.start(ev.Loop.default)

local function on_sigint_event(loop, sig, revents)
    authenticator.stop()
    event.stop()
    command.stop()
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
