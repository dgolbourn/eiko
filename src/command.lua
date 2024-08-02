local socket = require "socket"
local ev = require "ev"
local ssl = require "ssl"
local config = require "config"
local log = require "eiko.logs".defaultLogger()
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
        client_state.client_io_watcher:stop(loop)
        local incoming_event, err = data_model.client_authentication_response.decode(data)
        if incoming_event then
            log:info("verifying " .. peername)
            local event = data_model.authenticator_verify_request.encode{
                peername = peername,
                server_authentication_token = client_state.authentication_token,
                client_authentication_token = incoming_event.authentication_token
            }
            state.authenticator_pusher(event)
            return
        else
            log:warn("\"" .. err .. "\" when expecting authentication of " .. peername)
        end
    end
    client_state.timer_watcher:stop(loop)
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
        client_state.client_io_watcher:stop(loop)
        state.clients[peername] = nil
        state.clients[client_state.id] = nil
        log:warn("\"" .. err .. "\" while receiving from " .. client_state.id)
    end
end

local function on_authentication_timeout_event(peername, loop, io, revents)
    log:warn("authentication period has elapsed for " .. peername)
    local client_state = state.clients[peername]
    client_state.client_io_watcher:stop(loop)
    client_state.timer_watcher:stop(loop)
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
        client_state.client_io_watcher:callback(io_event)
        local timer_event = function(loop, io, revents)
            on_authentication_timeout_event(peername, loop, io, revents)
        end
        local timer_watcher = ev.Timer.new(timer_event, config.command.authentication_period, 0)
        if client_state.timer_watcher then
            client_state.timer_watcher:stop(loop)
        end
        client_state.timer_watcher = timer_watcher
        timer_watcher:start(loop)
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
        client_state.client_io_watcher:stop(loop)
        state.clients[peername] = nil
    end
end

local function on_authenticator_puller_io_event(loop, io, revents)
    state.authenticator_puller_idle_watcher:start(loop)
    state.authenticator_puller_io_watcher:stop(loop)
end

local function on_authenticator_puller_idle_event(loop, idle, revents)
    if state.authenticator_puller:has_event(zmq.POLLIN) then
        local incoming_event, err = state.authenticator_puller:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.authenticator_verify_response.decode(incoming_event)
            if err then
                log:warn("\"" .. err .. "\" when decoding data from " .. config.authenticator.push.command)
            else
                local client_state = state.clients[incoming_event.peername]
                if client_state then
                    log:info("verified " .. incoming_event.id .. " at " .. incoming_event.peername)
                    client_state.id = incoming_event.id
                    client_state.timer_watcher:stop(loop)
                    local io_event = function(loop, io, revents)
                        on_client_io_event(peername, loop, io, revents)
                    end
                    client_state.client_io_watcher:callback(io_event)
                    client_state.client_io_watcher:start(loop)
                    local event = data_model.event_connection_request.encode{
                        id = client_state.id
                    }
                    event_pusher:send(event)
                else
                    log:warn("no pending verification for " .. incoming_event.peername)
                end
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:warn("\"" .. err:msg() .. "\" when decoding data from " .. config.authenticator.push.command)
        end
    else
        state.authenticator_puller_idle_watcher:stop(loop)
        state.authenticator_puller_io_watcher:start(loop)
    end
end

local function on_event_puller_io_event(loop, io, revents)
    state.event_puller_idle_watcher:start(loop)
    state.event_puller_io_watcher:stop(loop)
end

local function on_event_puller_idle_event(loop, idle, revents)
    if state.event_puller:has_event(zmq.POLLIN) then
        local incoming_event, err = state.event_puller:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.event_connection_response.decode(incoming_event)
            if err then
                log:warn("\"" .. err .. "\" when decoding data from " .. config.event.push.command)
            else
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
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:warn("\"" .. err:msg() .. "\" when decoding data from " .. config.event.push.command)
        end
    else
        state.event_puller_idle_watcher:stop(loop)
        state.event_puller_io_watcher:start(loop)
    end
end

local function on_game_puller_io_event(loop, io, revents)
    state.game_puller_idle_watcher:start(loop)
    state.game_puller_io_watcher:stop(loop)
end

local function on_game_puller_idle_event(loop, idle, revents)
    if state.game_puller:has_event(zmq.POLLIN) then
        local incoming_event, err = state.game_puller:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.game_status.decode(incoming_event)
            if err then
                log:warn("\"" .. err .. "\" when decoding data from " .. config.game.push.command)
            else
                -- nothing yet
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:warn("\"" .. err:msg() .. "\" when decoding data from " .. config.event.push.command)
        end
    else
        state.game_puller_idle_watcher:stop(loop)
        state.game_puller_io_watcher:start(loop)
    end
end

local function on_new_client_io_event(loop, io, revents)
    local client = state.tcp:accept()
    local peername = client:getpeername()
    log:info("connection from unverified " .. peername)
    local client, err = ssl.wrap(client, config.command.ssl_params)
    if err then
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
        return
    end
    client:settimeout(0)
    local io_event = function(loop, io, revents)
        on_handshake_io_event(peername, loop, io, revents)
    end
    local client_state = {}
    client_state.client = client
    client_state.client_io_watcher = ev.IO.new(io_event, client_state.client:getfd(), ev.READ)
    state.clients[peername] = client_state
    client_io_watcher:start(loop)
end

local function start(loop)
    log:info("starting command")
    state = {}
    state.loop = loop or ev.Loop.default
    state.tcp = socket.tcp()
    state.tcp:bind(config.command.host, config.command.port)
    state.tcp:listen(config.command.max_clients)
    state.tcp:settimeout(0)
    state.new_client_io_watcher = ev.IO.new(on_new_client_io_event, state.tcp:getfd(), ev.READ)
    state.new_client_io_watcher:start(loop)
    state.ipc_context = zmq.context{io_threads = 1}
    state.game_puller = state.ipc_context:socket{zmq.PULL,
        connect = config.game.push.command
    }
    state.game_puller_io_watcher = ev.IO.new(on_game_puller_io_event, state.game_puller:get_fd(), ev.READ)
    state.game_puller_idle_watcher = ev.Idle.new(on_game_puller_idle_event)
    state.game_puller_io_watcher:start(loop)
    state.game_pusher = state.ipc_context:socket{zmq.PUSH,
        bind = config.command.push.game
    }
    state.event_puller = state.ipc_context:socket{zmq.PULL,
        connect = config.event.push.command
    }
    state.event_puller_io_watcher = ev.IO.new(on_event_puller_io_event, state.event_puller:get_fd(), ev.READ)
    state.event_puller_idle_watcher = ev.Idle.new(on_event_puller_idle_event)
    state.event_puller_io_watcher:start(loop)
    state.event_pusher = state.ipc_context:socket{zmq.PUSH,
        bind = config.command.push.event
    }
    state.authenticator_puller = state.ipc_context:socket{zmq.PULL,
        connect = config.authenticator.push.command
    }
    state.authenticator_puller_io_watcher = ev.IO.new(on_authenticator_puller_io_event, state.authenticator_puller:get_fd(), ev.READ)
    state.authenticator_puller_idle_watcher = ev.Idle.new(on_authenticator_puller_idle_event)
    state.authenticator_puller_io_watcher:start(loop)
    state.authenticator_pusher = state.ipc_context:socket{zmq.PUSH,
        bind = config.command.push.authenticator
    }
    state.clients = {}
end

local function stop()
    log:info("stopping command")
    local loop = state.loop
    state.loop = nil    
    for _, client_state in pairs(state.clients) do
        if client_state.timer_watcher then
            client_state.timer_watcher:stop(loop)
        end
        if client_state.client_io_watcher then
            client_state.client_io_watcher:stop(loop)
        end
        if client_state.client then
            client_state.client:close()
        end
    end
    if state.new_client_io_watcher then
        state.new_client_io_watcher:stop(loop)
    end
    if state.tcp then
        state.tcp:close()
    end
    if state.game_puller_io_watcher then
        state.game_puller_io_watcher:stop(loop)
    end
    if state.game_puller_idle_watcher then
        state.game_puller_idle_watcher:stop(loop)
    end
    if state.game_puller then
        state.game_puller:close()
    end
    if state.game_pusher then
        state.game_pusher:close()
    end
    if state.event_puller_io_watcher then
        state.event_puller_io_watcher:stop(loop)
    end
    if state.event_puller_idle_watcher then
        state.event_puller_idle_watcher:stop(loop)
    end
    if state.event_puller then
        state.event_puller:close()
    end
    if state.event_pusher then
        state.event_pusher:close()
    end
    if state.authenticator_puller_io_watcher then
        state.authenticator_puller_io_watcher:stop(loop)
    end
    if state.authenticator_puller_idle_watcher then
        state.authenticator_puller_idle_watcher:stop(loop)
    end
    if state.authenticator_puller then
        state.authenticator_puller:close()
    end
    if state.authenticator_pusher then
        state.authenticator_pusher:close()
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
