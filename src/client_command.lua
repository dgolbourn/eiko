local socket = require "socket"
local ev = require "ev"
local ssl = require "ssl"

local server_state = nil

local client_states = {}

local function on_client_io_event(peername, loop, io, revents)
    print("on_client_io_event " .. peername)
    client_state = client_states[peername]
    local data, err, partial = client_state.client:receive('*a', client_state.buffer)
    client_state.buffer = partial
    print(data)
    print(err)
    print(partial)
    if data or err == "timeout" or err == "wantread" then
    else
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
    local success, msg = client:dohandshake()
    print(success)
    print(msg)
    if success then
        client:settimeout(0) 
        local client_state = {}
        local io_event = function(loop, io, revents)
            on_client_io_event(peername, loop, io, revents)
        end
        local io_watcher = ev.IO.new(io_event, client:getfd(), ev.READ)
        io_watcher:start(ev.Loop.default)
        client_state.client = client
        client_state.io_watcher = io_watcher
        client_states[peername] = client_state
    end
end

local function start(host, port)
    local server = socket.tcp()
    server:bind(host, port)
    local max_client = 16
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
