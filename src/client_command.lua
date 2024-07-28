local socket = require "socket"
local ev = require "ev"
local ssl = require "ssl"
local bit32 = require "bit32"
local game_config = require "config".game
local client_command_config = require "config".client_command
local remote_authenticator_config = require "config".remote_authenticator
local itc_events = require "config".itc_events
local log = require "eiko.logs".defaultLogger()
local signal = require "signals"
local context = require "context"
local server_event = require "eiko.server_event"
local data_model = require "eiko.data_model"

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
                local event = {
                    kind = itc_events.remote_authenticator_verify_request,
                    message = {
                        peername = peername,
                        authentication_token = data
                    }
                }
                context:send(nil, remote_authenticator_config.itc_channel, event)
                signal.raise(signal.realtime(remote_authenticator_config.itc_channel))
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
    if data then
        local commands = data_model.command(data)
        for _, command in ipairs(commands)
            if command then
                log:debug("command received from " .. verified.id)
                local event = {
                    kind = itc_events.game_command_request,
                    message = command
                }
                context:send(nil, game_config.itc_channel, event)
                signal.raise(signal.realtime(game_config.itc_channel))
            else
                log:error("invalid format for data from " .. verified.id)
            end
        end
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
        local timer_watcher = ev.Timer.new(timer_event, client_command_config.authentication_period, 0)
        client_state.timer_watcher:stop(ev.Loop.default)
        client_state.timer_watcher = timer_watcher
        timer_watcher:start(ev.Loop.default)
        client_state.authentication_token = encdec.authentication_token()
        client_state.client:send(client_state.authentication_token)
        log:info("sent authentication token to " .. peername)
    elseif err == "wantread" or err == "wantwrite" then
    else
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
        client_state.client:close()
        client_state.io_watcher:stop(ev.Loop.default)
        state.clients[peername] = nil
    end
end

local function on_server_signal_event(loop, sig, revents)
    local key, event = context:receive(nil, client_command_config.itc_channel)
    if event.kind == itc_events.remote_authenticator_verify_response then
        local message = event.message
        local client_state = state.clients[message.peername]
        if client_state then
            log:info("verified " .. message.id .. " at " .. message.peername)
            client_state.id = message.id
            client_state.timer_watcher:stop(ev.Loop.default)
            client_state.io_watcher:start(ev.Loop.default)
            local event = {
                kind = itc_events.server_event_connection_request,
                message = {
                    id = client_state.id
                }
            }
            context:send(nil, server_event_config.itc_channel, event)
            signal.raise(signal.realtime(server_event_config.itc_channel))
        else
            log:warn("no pending verification for " .. message.peername)
        end
    elseif event.kind == itc_events.server_event_connection_response then
        local message = event.message
        local client_state = state.clients[message.peername]
        if client_state then
            client_state.client.send(message.authentication_token)
            client_state.client.send(message.traffic_key)
            log:info("sent authentication token and traffic key to " .. client_state.id)
        else
            log:warn("no pending verification for " .. message.peername)
        end
    else
        log:error("unknown event kind \"" .. event.kind .. "\" received on " .. client_command_config.itc_channel)
    end
end

local function on_server_io_event(loop, io, revents)
    local client = state.server:accept()
    local peername = client:getpeername()
    log:info("connection from unverified " .. peername)
    client = ssl.wrap(client, client_command_config.ssl_params)
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
    log:info("starting client command")
    local server = socket.tcp()
    server:bind(client_command_config.host, client_command_config.port)
    server:listen(client_command_config.max_clients)
    server:settimeout(0)
    state = {}
    state.server = server
    local io_watcher = ev.IO.new(on_server_io_event, server:getfd(), ev.READ)
    io_watcher:start(ev.Loop.default)
    state.io_watcher = io_watcher
    local signal_watcher = ev.Signal.new(on_server_signal_event, signal.realtime(client_command_config.itc_channel))
    state.signal_watcher = signal_watcher
    signal_watcher:start(ev.Loop.default)
    state.clients = {}
end

local function stop()
    log:info("stopping client command")
    for k, client_state in pairs(state.clients) do
        client_state.timer_watcher:stop(ev.Loop.default)
        client_state.io_watcher:stop(ev.Loop.default)
        client_state.client:close()
    end
    state.io_watcher:stop(ev.Loop.default)
    state.signal_watcher:stop(ev.Loop.default)
    state.server:close()
    state = nil
end

return {
    start = start,
    stop = stop
}
