local socket = require "socket"
local ev = require "ev"
local ssl = require "ssl"
local bit32 = require "bit32"
local config = require "config"
local log = require "eiko.logs".defaultLogger()
local signal = require "signals"
local context = require "context"
local event = require "eiko.event"
local data_model = require "eiko.data_model"
local encdec = require "eiko.encdec"
local zmq = require "lzmq"

local state = nil

local function on_authentication_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    local data, err, partial = client_state.client:receive('*l', client_state.buffer)
    client_state.buffer = partial
    if err == "timeout" then
        return
    else
        client_state.io_watcher:stop(ev.Loop.default)
        local incoming_event, err = data_model.client_authentication_response.decode(data)
        if incoming_event then
            log:info("verifying " .. peername)
            local event = data_model.authenticator_verify_request.encode{
                peername = peername,
                server_authentication_token = client_state.authentication_token,
                client_authentication_token = incoming_event.authentication_token
            }
            context:send(nil, config.authenticator.itc_channel, event)
            signal.raise(signal.realtime(config.authenticator.itc_channel))
            return
        else
            log:warn("\"" .. err .. "\" when expecting authentication of " .. peername)
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
        local incoming_event, err = data_model.client_command.decode(data)
        if incoming_event then
            if data_model.client_example_command.kindof(incoming_event) then
                local event = data_model.game_command.encode{
                    id = verified.id,
                    command = incoming_event.command
                }
                state.publisher:send(event)
            else
                log:error("unimplemented command kind " .. incoming_event._kind .. " received from " .. client_state.id)
            end
        else
            log:error("\"" .. err .. "\" when decoding data from " .. client_state.id)
        end
    elseif err == "timeout" then
    else
        client_state.client:close()
        client_state.io_watcher:stop(ev.Loop.default)
        state.clients[peername] = nil
        state.clients[client_state.id] = nil
        log:warn("\"" .. err .. "\" while receiving from " .. client_state.id)
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
    if success then
        log:info("successful tls handshake with " .. peername)
        local io_event = function(loop, io, revents)
            on_authentication_io_event(peername, loop, io, revents)
        end
        client_state.io_watcher:callback(io_event)
        local timer_event = function(loop, io, revents)
            on_authentication_timeout_event(peername, loop, io, revents)
        end
        local timer_watcher = ev.Timer.new(timer_event, config.command.authentication_period, 0)
        if client_state.timer_watcher then
            client_state.timer_watcher:stop(ev.Loop.default)
        end
        client_state.timer_watcher = timer_watcher
        timer_watcher:start(ev.Loop.default)
        client_state.authentication_token = encdec.authentication_token()
        local event = data_model.client_authentication_request.encode{
            authentication_token = client_state.authentication_token
        }
        client_state.client:send(event)
        log:info("sent authentication token to " .. peername)
    elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
    else
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
        client_state.client:close()
        client_state.io_watcher:stop(ev.Loop.default)
        state.clients[peername] = nil
    end
end

local function on_server_signal_event(loop, sig, revents)
    local _, incoming_event = context:receive(nil, config.command.itc_channel)
    local incoming_event, err = data_model.command_itc_event.decode(incoming_event)
    if err then
        log:error("\"" .. err .. "\" when decoding data from " .. config.command.itc_channel)
    else
        if data_model.authenticator_verify_response.kindof(incoming_event) then
            local client_state = state.clients[incoming_event.peername]
            if client_state then
                log:info("verified " .. incoming_event.id .. " at " .. incoming_event.peername)
                client_state.id = incoming_event.id
                client_state.timer_watcher:stop(ev.Loop.default)
                local io_event = function(loop, io, revents)
                    on_client_io_event(peername, loop, io, revents)
                end
                client_state.io_watcher:callback(io_event)
                client_state.io_watcher:start(ev.Loop.default)
                local event = data_model.event_connection_request.encode{
                    id = client_state.id
                }
                context:send(nil, config.event.itc_channel, event)
                signal.raise(signal.realtime(config.event.itc_channel))
            else
                log:warn("no pending verification for " .. incoming_event.peername)
            end
        elseif data_model.event_connection_response.kindof(incoming_event) then
            local client_state = state.clients[incoming_event.id]
            if client_state then
                local event = data_model.event_authentication_request.encode{
                    authentication_token = incoming_event.authentication_token,
                    traffic_key = incoming_event.traffic_key
                }
                client_state.client:send(event)
                log:info("sent authentication token and traffic key to " .. incoming_event.id)
            else
                log:warn("no pending verification for " .. incoming_event.id)
            end
        end
    end
end

local function on_server_io_event(loop, io, revents)
    local client = state.server:accept()
    local peername = client:getpeername()
    log:info("connection from unverified " .. peername)
    local client, err = ssl.wrap(client, config.command.ssl_params)
    if not client and err then
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
        return
    end
    client:settimeout(0)
    local io_event = function(loop, io, revents)
        on_handshake_io_event(peername, loop, io, revents)
    end
    local io_watcher = ev.IO.new(io_event, client:getfd(), ev.READ)
    local client_state = {}
    client_state.client = client
    client_state.io_watcher = io_watcher
    state.clients[peername] = client_state
    io_watcher:start(ev.Loop.default)
end

local function start()
    log:info("starting client command")
    local server = socket.tcp()
    server:bind(config.command.host, config.command.port)
    server:listen(config.command.max_clients)
    server:settimeout(0)
    state = {}
    state.server = server
    local io_watcher = ev.IO.new(on_server_io_event, server:getfd(), ev.READ)
    io_watcher:start(ev.Loop.default)
    state.io_watcher = io_watcher
    local signal_watcher = ev.Signal.new(on_server_signal_event, signal.realtime(config.command.itc_channel))
    state.signal_watcher = signal_watcher
    signal_watcher:start(ev.Loop.default)
    state.ipc_context = zmq.context{io_threads = 1}
    state.publisher = state.ipc_context:socket{zmq.PUB,
        bind = config.game.ipc_command_channel
    }
    state.clients = {}
end

local function stop()
    log:info("stopping client command")
    for k, client_state in pairs(state.clients) do
        if client_state.timer_watcher then
            client_state.timer_watcher:stop(ev.Loop.default)
        end
        if client_state.io_watcher then
            client_state.io_watcher:stop(ev.Loop.default)
        end
        if client_state.client then
            client_state.client:close()
        end
    end
    if state.io_watcher then
        state.io_watcher:stop(ev.Loop.default)
    end
    if state.signal_watcher then
        state.signal_watcher:stop(ev.Loop.default)
    end
    if state.publisher then
        state.publisher:close()
    end    
    if state.ipc_context then
        state.ipc_context:shutdown()
    end    
    if state.server then
        state.server:close()
    end
    state = nil
end

return {
    start = start,
    stop = stop
}
