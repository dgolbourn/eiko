local socket = require "socket"
local ev = require "ev"
local ssl = require "ssl"
local bit32 = require "bit32"
local action = require "eiko.client_action"

local server_state = nil

local client_states = {}

local handshake_timeout_period = 1./100

local function on_client_io_event(peername, loop, io, revents)
    print("on_client_io_event " .. peername)
    client_state = client_states[peername]

    local data, err, partial = client_state.client:receive('*l', client_state.buffer)
    client_state.buffer = partial
    print(data, err, partial)
    if data then
        action.consume(peername, data)
    elseif err == "wantread" or err == "wantwrite" then
    else
        client_state.client:close()
        client_state.io_watcher:stop(ev.Loop.default)
        client_states[peername] = nil
    end
end

local function on_handshake_io_event(peername, loop, io, revents)
    print("on_handshake_io_event " .. peername)
    client_state = client_states[peername]

    local success, err = client_state.client:dohandshake()
    print(succes, err)
    if success then
        local io_event = function(loop, io, revents)
            on_client_io_event(peername, loop, io, revents)
        end
        local io_watcher = ev.IO.new(io_event, client_state.client:getfd(), ev.READ)
        client_state.client:settimeout(0)
        client_state.io_watcher:stop(ev.Loop.default)
        client_state.io_watcher = io_watcher
        io_watcher:start(ev.Loop.default)
    elseif err == "wantread" or err == "wantwrite" then
    else
        client_state.client:close()
        client_state.io_watcher:stop(ev.Loop.default)
        client_states[peername] = nil
    end
end

local params = {
    mode = "server",
    protocol = "tlsv1_2",
    key = "test/ca-key.pem",
    certificate = "test/ca-cert.pem",
    verify = "none",
    options = "all"
}

local function on_server_io_event(loop, io, revents)
    print("on_server_io_event")
    local client = server_state.server:accept()
    local peername = client:getpeername()
    client = ssl.wrap(client, params)
    client:settimeout(handshake_timeout_period)

    local success, err = client:dohandshake()
    print(success, err)
    local io_watcher = nil
    if success then
        local io_event = function(loop, io, revents)
            on_client_io_event(peername, loop, io, revents)
        end
        io_watcher = ev.IO.new(io_event, client:getfd(), ev.READ)
    elseif err == "wantread" or err == "wantwrite" then
        local io_event = function(loop, io, revents)
            on_handshake_io_event(peername, loop, io, revents)
        end
        io_watcher = ev.IO.new(io_event, client:getfd(), bit32.bor(ev.READ, ev.WRITE))
    else
        client:close()
    end

    if io_watcher then
        io_watcher:start(ev.Loop.default)
        local client_state = {}
        client_state.client = client
        client_state.io_watcher = io_watcher
        client_states[peername] = client_state
    end
end

local function start(host, port)
    local server = socket.tcp()
    server:bind(host, port)
    local max_clients = 16
    server:listen(max_clients)
    server:settimeout(0)
    local _server_state = {}
    _server_state.server = server
    local io_watcher = ev.IO.new(on_server_io_event, server:getfd(), ev.READ)
    io_watcher:start(ev.Loop.default)
    _server_state.io_watcher = io_watcher
    server_state = _server_state
end

local function stop()
    for k, client_state in client_states do
        client_state.io_watcher:stop(ev.Loop.default)
        client_state.client:close()
    end
    client_states = {}
    server_state.io_watcher:stop(ev.Loop.default)
    server_state.server:close()
    server_state = nil
end

return {
    start = start,
    stop = stop
}
