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

local function on_idle_event(loop, idle, revents)
    collectgarbage()
end

local idle_watcher = ev.Idle.new(on_idle_event)
idle_watcher:start(ev.Loop.default)

local zmq = require "lzmq"
local data_model = require "eiko.data_model"
local config = require "eiko.config"

local context = zmq.context{io_threads = 1}
local user = context:socket{zmq.PAIR, connect = config.client.ipc}


local function user_connection_request(loop, idle, revents)
    local event = data_model.user_connection_request.encode{
        host = config.server.host,
        port = config.server.port
    }
    user:send(event)
    idle_watcher:callback(on_idle_event)
end

local function user_login_response(loop, idle, revents)
    if user:has_event(zmq.POLLIN) then
        local incoming_event, err = user:recv(zmq.NOBLOCK)
        if incoming_event then
            data_model.user_login_request.decode(incoming_event)
            idle_watcher:callback(user_connection_request)
        end
    end
end

local function user_login_request(loop, idle, revents)
    local event = data_model.user_login_request.encode{
        login="jane@bloggs.co.uk",
        password="password"
    }
    user:send(event)
    idle_watcher:callback(user_login_response)
end

idle_watcher:callback(user_login_request)


ev.Loop.default:loop()
