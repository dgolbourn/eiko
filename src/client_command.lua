local socket = require "socket"
local ev = require "ev"
local ssl = require "ssl"
local bit32 = require "bit32"
local config = require "config".client_command
local log = require "eiko.logs".defaultLogger()
local signal = require "signals"
local context = require "context"
local server_event = require "eiko.server_event"

local state = nil

local function on_authentication_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    local data, err, partial = client_state.client:receive('*l', client_state.buffer)
    client_state.buffer = partial
    if err == "wantread" or err == "wantwrite" then
        return
    else
        client_state.io_watcher:stop(ev.Loop.default)
        if data then
            if client_state.authentication_token == string.sub(data, 1, string.len(client_state.authentication_token)) then
                log:info("verifying " .. peername)
                remote_authentication(data)
                return
            else
                log:warn("incorrect authentication token received from " .. peername)
            end
        else
            log:warn("\"" .. err .. "\" while attempting authentication of " .. peername)
        end
    end
    client_state.timer_watcher:stop(ev.Loop.default)
    client_state.client:close()
    state.clients[peername] = nil
end

local function on_client_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    local data, err, partial = client_state.client:receive('*l', client_state.buffer)
    client_state.buffer = partial
    print(data, err, partial)
    if data then
        consume(peername, data)
    elseif err == "wantread" or err == "wantwrite" then
    else
        client_state.client:close()
        client_state.io_watcher:stop(ev.Loop.default)
        state.clients[peername] = nil
        log:warn("\"" .. err .. "\" while receiving from " .. peername)
    end
end

local function on_authentication_timeout_event(peername, loop, io, revents)
    log:warn("authentication period has elapsed for " .. peername)
    local client_state = state.clients[peername]
    client_state.io_watcher:stop(ev.Loop.default)
    client_state.timer_watcher:stop(ev.Loop.default)
    client_state.client:close()
    state.clients[peername] = nil
end

local function on_handshake_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    local success, err = client_state.client:dohandshake()
    print(succes, err)
    if success then
        log:info("successful tls handshake with " .. peername)
        client_state.client:settimeout(0)
        local io_event = function(loop, io, revents)
            on_authentication_io_event(peername, loop, io, revents)
        end
        local io_watcher = ev.IO.new(io_event, client_state.client:getfd(), ev.READ)
        client_state.io_watcher:stop(ev.Loop.default)
        client_state.io_watcher = io_watcher
        io_watcher:start(ev.Loop.default)
        local timer_event = function(loop, io, revents)
            on_authentication_timeout_event(peername, loop, io, revents)
        end
        local timer_watcher = ev.Timer.new(timer_event, config.authentication_period, 0)
        client_state.timer_watcher:stop(ev.Loop.default)
        client_state.timer_watcher = timer_watcher
        timer_watcher:start(ev.Loop.default)
        client_state.authentication_token = encdec.authentication_token()
        client_state.client:send(client_state.authentication_token)
    elseif err == "wantread" or err == "wantwrite" then
    else
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
        client_state.client:close()
        client_state.io_watcher:stop(ev.Loop.default)
        state.clients[peername] = nil
    end
end

local function on_server_signal_event(loop, sig, revents)
    local key, message = context.receive(0, "client_command/authentication")
    if key then
        local client_state = state.clients[message.peername]
        if client_state then
            log:info("authenticated " .. message.id .. " at " .. message.peername)
            client_state.id = message.id
            client_state.timer_watcher:stop(ev.Loop.default)
            client_state.io_watcher:start(ev.Loop.default)
            authentication_token, traffic_key = server_event.connect(id)
            client_state.client.send(authentication_token)
            client_state.client.send(traffic_key)
        else
            log:warn("no pending verification for " .. message.peername)
        end
    else
        log:error("no message received after corresponding signal")
    end
end

local function on_server_io_event(loop, io, revents)
    local client = state.server:accept()
    local peername = client:getpeername()
    log:info("connection from unverified " .. peername)
    client = ssl.wrap(client, config.ssl_params)
    client:settimeout(config.handshake_timeout_period)
    local success, err = client:dohandshake()
    local io_watcher = nil
    if success then
        log:info("successful tls handshake with " .. peername)
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
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
        client:close()
        return
    end
    io_watcher:start(ev.Loop.default)
    local client_state = {}
    client_state.client = client
    client_state.io_watcher = io_watcher
    state.clients[peername] = client_state
end

local function start()
    local server = socket.tcp()
    server:bind(config.host, config.port)
    server:listen(config.max_clients)
    server:settimeout(0)
    state = {}
    state.server = server
    local io_watcher = ev.IO.new(on_server_io_event, server:getfd(), ev.READ)
    io_watcher:start(ev.Loop.default)
    state.io_watcher = io_watcher
    local signal_watcher = ev.Signal.new(on_server_signal_event, signal.realtime(1))
    state.signal_watcher = signal_watcher
    signal_watcher:start(ev.Loop.default)
    state.clients = {}
end

local function stop()
    for k, client_state in state.clients do
        client_state.io_watcher:stop(ev.Loop.default)
        client_state.client:close()
    end
    state.io_watcher:stop(ev.Loop.default)
    state.server:close()
    state = nil
end

return {
    start = start,
    stop = stop
}
