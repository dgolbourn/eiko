local ev = require "ev"
local signal = require "signal"

local server = require "eiko.server"
server.start(ev.Loop.default)

local authenticator = require "eiko.authenticator"
authenticator.start(ev.Loop.default)

local client = require "eiko.client"
client.start(ev.Loop.default)

local function on_sigint_event(loop, sig, revents)
    server.stop(loop)
    authenticator.stop(loop)
    client.stop(loop)
    loop:unloop()
end
local signal_watcher = ev.Signal.new(on_sigint_event, signal.SIGINT)
signal_watcher:start(ev.Loop.default)

-- local function on_idle_event(loop, idle, revents)
--     print("idle")
--     collectgarbage()
-- end
-- local idle_watcher = ev.Idle.new(on_idle_event)
-- idle_watcher:start(ev.Loop.default)

local zmq = require "lzmq"
local data_model = require "eiko.data_model"
local config = require "eiko.config"

local context = zmq.context{io_threads = 1}
local user = context:socket{zmq.PAIR, connect = config.client.ipc}

local event = data_model.user_login_request.encode{
    login="jane@bloggs.co.uk",
    password="password"
}

user:send(event)

ev.Loop.default:loop()
