local socket = require "socket"
local ev = require "ev"
local ssl = require "ssl"
local config = require "config"
local log = require "eiko.logs".defaultLogger()
local event = require "eiko.event"
local data_model = require "eiko.data_model"
local codec = require "eiko.codec"
local zmq = require "lzmq"


local state = nil

local function client_state_close(client_state, loop)
    if client_state.client then
        client_state.client:close()
    end
    if client_state.client_io_watcher then
        client_state.client_io_watcher:stop(loop)
    end
    if client_state.authenticator_io_watcher then
        client_state.authenticator_io_watcher:stop(loop)
    end
    if client_state.timer_watcher then
        client_state.timer_watcher:stop(loop)
    end
    if client_state.peername then
        state.clients[client_state.peername] = nil
    end
    if client_state.id then
        state.clients[client_state.id] = nil
    end
end

local function on_verify_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
        local data, err, partial = client_state.authenticator:receive('*l', client_state.buffer)
        client_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" when expecting verification of " .. peername)
            client_state_close(client_state, loop)
        else
            local incoming_event, err = data_model.authenticator_verify_response.decode(data)
            if incoming_event then
                local authenticator_peername = config.authenticator.host .. ":" .. config.authenticator.port
                log:info(authenticator_peername .. " verified authentication token as " .. incoming_event.id .. " at " .. peername)
                client_state.authenticator:close()
                client_state.authenticator_io_watcher:stop(loop)
                client_state.timer_watcher:stop(loop)
                client_state.id = incoming_event.id
                state.clients[client_state.id] = client_state
                local event = data_model.event_connection_request.encode{
                    id = client_state.id
                }
                local _, err = state.event:send(event)
                if err then
                    log:warn("\"" .. err:msg() .. "\" while attempting authentication of " .. peername)
                    client_state_close(client_state, loop)
                end
            else
                log:warn("\"" .. err .. "\" when expecting verification of " .. peername)
                client_state_close(client_state, loop)
            end
        end
    else
        log:warn("no pending authentication for " .. peername)
    end
end

local function on_authenticator_handshake_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
        local success, err = client_state.authenticator:dohandshake()
        local authenticator_peername = config.authenticator.host .. ":" .. config.authenticator.port
        if success then
            log:info("successful tls handshake with " .. authenticator_peername)
            local io_event = function(loop, io, revents)
                on_verify_io_event(peername, loop, io, revents)
            end
            client_state.authenticator_io_watcher:callback(io_event)
            local event = data_model.authenticator_verify_request.encode{
                server_authentication_token = client_state.authentication_token,
                client_authentication_token = incoming_event.authentication_token
            }
            local _, err = client_state.authenticator:send(event)
            if err then
                log:warn("\"" .. err .. "\" while attempting authentication of " .. peername)
                client_state_close(client_state, loop)
            else
                log:info("sent verification request to " .. authenticator_peername .. " for " .. peername)
            end
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator_peername)
            client_state_close(client_state, loop)
        end
    else
        log:warn("no pending authentication for " .. peername)
    end
end

local function on_authentication_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
        local data, err, partial = client_state.client:receive('*l', client_state.buffer)
        client_state.buffer = partial
        if err == "timeout" then
        else if err then
            log:warn("\"" .. err .. "\" when expecting authentication of " .. peername)
            client_state_close(client_state, loop)
        else
            client_state.client_io_watcher:stop(loop)
            local incoming_event, err = data_model.client_authentication_response.decode(data)
            if incoming_event then
                log:info("verifying " .. peername)
                local authenticator = socket.tcp()
                authenticator:connect(config.authenticator.host, config.authenticator.port)
                local authenticator, err = ssl.wrap(authenticator, config.authenticator.ssl_params)
                if err then
                    local authenticator_peername = config.authenticator.host .. ":" .. config.authenticator.port
                    log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator_peername)
                    client_state_close(client_state, loop)
                else
                    authenticator:settimeout(0)
                    local io_event = function(loop, io, revents)
                        on_authenticator_handshake_io_event(peername, loop, io, revents)
                    end
                    client_state.authenticator = authenticator
                    client_state.authenticator_io_watcher = ev.IO.new(io_event, authenticator:getfd(), ev.READ)
                    client_state.authenticator_io_watcher:start(loop)
                    io_event(loop, io, revents)
                end
            else
                log:warn("\"" .. err .. "\" when expecting authentication of " .. peername)
                client_state_close(client_state, loop)
            end
        end
    else
        log:warn("no pending authentication for " .. peername)
    end
end

local function on_client_command_io_event(id, loop, io, revents)
    local client_state = state.clients[id]
    if client_state then
        local data, err, partial = client_state.client:receive('*l', client_state.buffer)
        client_state.buffer = partial
        if data then
            local incoming_event, err = data_model.client_command.decode(data)
            if incoming_event then
                if data_model.client_example_command.kindof(incoming_event) then
                    local event = data_model.game_command.encode{
                        id = id,
                        command = incoming_event.command
                    }
                    state.event:send(event)
                else
                    log:error("unimplemented command kind " .. incoming_event._kind .. " received from " .. id)
                end
            else
                log:error("\"" .. err .. "\" when decoding data from " .. id)
            end
        elseif err == "timeout" then
        else
            log:warn("\"" .. err .. "\" while receiving from " .. id)
            client_state_close(client_state, loop)
        end
    else
        log:warn("no verified client " .. id)
    end
end

local function on_authentication_timeout_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state
        log:warn("authentication period has elapsed for " .. peername)
        client_state_close(client_state, loop)
    else
        log:warn("no pending authentication for " .. peername)
    end
end

local function on_handshake_io_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
        local success, err = client_state.client:dohandshake()
        if success then
            log:info("successful tls handshake with " .. peername)
            local io_event = function(loop, io, revents)
                on_authentication_io_event(peername, loop, io, revents)
            end
            client_state.client_io_watcher:callback(io_event)
            client_state.authentication_token = codec.authentication_token()
            local event = data_model.client_authentication_request.encode{
                authentication_token = client_state.authentication_token
            }
            local _, err = client_state.client:send(event)
            if err then
                log:warn("\"" .. err .. "\" while attempting authentication of " .. peername)
                client_state_close(client_state, loop)
            else
                log:info("sent authentication token to " .. peername)
            end
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
            client_state_close(client_state, loop)
        end
    else
        log:warn("no pending authentication for " .. peername)
    end
end

local function on_event_io_event(loop, io, revents)
    state.event_idle_watcher:start(loop)
    state.event_io_watcher:stop(loop)
end

local function on_event_idle_event(loop, idle, revents)
    if state.event:has_event(zmq.POLLIN) then
        local incoming_event, err = state.event:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.event_connection_response.decode(incoming_event)
            if err then
                log:error("\"" .. err .. "\" when decoding data from " .. config.event.pair.command)
            else
                local client_state = state.clients[incoming_event.id]
                if client_state then
                    local event = data_model.event_authentication_request.encode{
                        authentication_token = incoming_event.authentication_token,
                        traffic_key = incoming_event.traffic_key
                    }
                    local _, err = client_state.client:send(event)
                    if err then
                        log:warn("\"" .. err .. "\" while attempting authentication of " .. peername)
                        client_state_close(client_state, loop)
                    else
                        local id = incoming_event.id
                        local io_event = function(loop, io, revents)
                            on_client_command_io_event(id, loop, io, revents)
                        end
                        client_state.client_io_watcher:callback(io_event)
                        client_state.client_io_watcher:start(loop)
                        log:info("sent authentication token and traffic key to " .. incoming_event.id)
                    end
                else
                    log:warn("no pending authentication for " .. incoming_event.id)
                end
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:error("\"" .. err:msg() .. "\" when decoding data from " .. config.event.pair.command)
        end
    else
        state.event_idle_watcher:stop(loop)
        state.event_io_watcher:start(loop)
    end
end

local function on_game_io_event(loop, io, revents)
    state.game_idle_watcher:start(loop)
    state.game_io_watcher:stop(loop)
end

local function on_game_idle_event(loop, idle, revents)
    if state.game:has_event(zmq.POLLIN) then
        local incoming_event, err = state.game:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.game_status.decode(incoming_event)
            if err then
                log:error("\"" .. err .. "\" when decoding data from " .. config.game.pair.command)
            else
                local client_state = state.clients[incoming_event.id]
                if client_state then
                    local event = data_model.user_status.encode{
                        status = incoming_event.status
                    }
                    local _, err = client_state.client:send(event)
                    if err then
                        log:warn("\"" .. err .. "\" while attempting to send to " .. client_state.id)
                        client_state_close(client_state, loop)
                    end
                else
                    log:debug("no verified client for " .. incoming_event.id)
                end
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:error("\"" .. err:msg() .. "\" when decoding data from " .. config.event.pair.command)
        end
    else
        state.game_idle_watcher:stop(loop)
        state.game_io_watcher:start(loop)
    end
end

local function on_new_client_io_event(loop, io, revents)
    local client_state = {}
    local client = state.tcp:accept()
    local peername = client:getpeername()
    log:info("connection from unverified " .. peername)
    local client, err = ssl.wrap(client, config.command.ssl_params)
    if err then
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
    else
        client:settimeout(0)
        local io_event = function(loop, io, revents)
            on_handshake_io_event(peername, loop, io, revents)
        end
        client_state.client = client
        client_state.peername = peername
        client_state.client_io_watcher = ev.IO.new(io_event, client:getfd(), ev.READ)
        client_state.client_io_watcher:start(loop)
        local timer_event = function(loop, io, revents)
            on_authentication_timeout_event(peername, loop, io, revents)
        end        
        client_state.timer_watcher = ev.Timer.new(timer_event, config.command.authentication_period, 0)
        client_state.timer_watcher:start(loop)        
        state.clients[peername] = client_state
    end
end

local function start(loop)
    log:info("starting command")
    loop = loop or ev.Loop.default
    state = {}
    state.tcp = socket.tcp()
    state.tcp:bind(config.command.host, config.command.port)
    state.tcp:listen(config.command.max_clients)
    state.tcp:settimeout(0)
    state.new_client_io_watcher = ev.IO.new(on_new_client_io_event, state.tcp:getfd(), ev.READ)
    state.new_client_io_watcher:start(loop)
    state.ipc_context = zmq.context{io_threads = 1}
    state.game = state.ipc_context:socket{zmq.PAIR,
        connect = config.game.pair.command
    }
    state.game_io_watcher = ev.IO.new(on_game_io_event, state.game:get_fd(), ev.READ)
    state.game_idle_watcher = ev.Idle.new(on_game_idle_event)
    state.game_io_watcher:start(loop)
    state.event = state.ipc_context:socket{zmq.PAIR,
        connect = config.event.pair.command
    }
    state.event_io_watcher = ev.IO.new(on_event_io_event, state.event:get_fd(), ev.READ)
    state.event_idle_watcher = ev.Idle.new(on_event_idle_event)
    state.event_io_watcher:start(loop)
    state.clients = {}
end

local function stop(loop)
    log:info("stopping command")
    loop = loop or ev.Loop.default
    for _, client_state in pairs(state.clients) do
        client_state_close(client_state, loop)
    end
    if state.new_client_io_watcher then
        state.new_client_io_watcher:stop(loop)
    end
    if state.tcp then
        state.tcp:close()
    end
    if state.game_io_watcher then
        state.game_io_watcher:stop(loop)
    end
    if state.game_idle_watcher then
        state.game_idle_watcher:stop(loop)
    end
    if state.game then
        state.game:close()
    end
    if state.event_io_watcher then
        state.event_io_watcher:stop(loop)
    end
    if state.event_idle_watcher then
        state.event_idle_watcher:stop(loop)
    end
    if state.event then
        state.event:close()
    end
    if state.ipc_context then
        state.ipc_context:shutdown()
    end
    state = nil
end

return {
    start = start,
    stop = stop
}
