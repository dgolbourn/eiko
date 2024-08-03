local ev = require "ev"
local signal = require "signal"

local command = require "eiko.command"
command.start(ev.Loop.default)

local function on_sigint_event(loop, sig, revents)
    command.stop()
    ev.Loop.default:unloop()
end
local signal_watcher = ev.Signal.new(on_sigint_event, signal.SIGINT)
signal_watcher:start(ev.Loop.default)

ev.Loop.default:loop()
