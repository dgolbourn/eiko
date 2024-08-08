local socket = require "socket"
local ssl = require "ssl"
local codec = require "eiko.codec"
local data_model = require "eiko.data_model"
local config = require "eiko.config"


local state = {}

local function on_command_io_event(loop, io, revents)
    local active_state = state.active_state
    if active_state then
        local data, err, partial = active_state.command:receive('*l', active_state.buffer)
        active_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while receiving data from " .. active_state.command:getpeername())
            connection_close(loop)
        else
            local incoming_event, err = data_model.server_status.decode(data)
            if incoming_event then
                local event = data_model.user_status.encode{
                    status = incoming_event.status,
                }
                active_state.client:send(event)
            else
                log:warn("\"" .. err .. "\" while receiving data from " .. active_state.event:getpeername())
                connection_close(loop)
            end
        end
    else
        log:error("no active connection")
    end
end

local function on_event_io_event(loop, io, revents)
    local active_state = state.active_state
    if active_state then
        local data, err = active_state.event:receive()
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while receiveing event from " .. active_state.event:getpeername())
            connection_close(loop)
        else
            local incoming_event, epoch = codec.delta_compress_decode(data, active_state.previous, active_state.traffic_key)
            if epoch <= active_state.epoch then
                log:debug("discarding out of date event referring to epoch " .. epoch .. " <= " .. active_state.epoch .. " from " .. active_state.event:getpeername())
            else
                active_state.epoch = epoch
                active_state.previous[epoch] = incoming_event
                for past_epoch, _ in pairs(active_state.previous) do
                    if active_state.epoch - past_epoch > config.event.message_history_depth then
                        active_state.previous[past_epoch] = nil
                    end
                end
                active_state.previous[0] = ""
                local incoming_event, err = data_model.server_event.decode(incoming_event)
                if err then
                    log:warn("\"" .. err .. "\" when decoding data from " .. active_state.event:getpeername())
                else
                    local event = data_model.user_event.encode{
                        state = incoming_event.state,
                    }
                    active_state.client:send(event)
                    local event = data_model.client_ack_action.encode{}
                    event = codec.encode(event, active_state.counter, active_state.epoch, incoming_event.traffic_key)
                    active_state.counter = active_state.counter + 1
                    local _, err = active_state.event:send(event)
                    if err then
                        log:warn("\"" .. err:msg() .. "\" while sending to " .. active_state.event:getpeername())
                        connection_close(loop)
                    end
                end
            end
        end
    else
        log:error("no active connection")
    end
end

local function on_event_authentication_io_event(peername, loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        local data, err, partial = pending_state.command:receive('*l', pending_state.buffer)
        pending_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while attempting authentication with " .. pending_state.event:getpeername())
            connection_close(loop)
        else
            local incoming_event, err = data_model.event_authentication_request.decode(data)
            if incoming_event then
                log:info("Authenticating with " .. pending_state.event:getpeername())
                pending_state.traffic_key = incoming_event.traffic_key
                pending_state.epoch = 0
                pending_state.counter = 0
                event = data_model.event_authentication_response.encode{
                    authentication_token = incoming_event.authentication_token
                }
                event = codec.encode(event, pending_state.counter, pending_state.epoch, incoming_event.traffic_key)
                pending_state.counter = pending_state.counter + 1
                local _, err = pending_state.event:send(event)
                if err then
                    log:warn("\"" .. err:msg() .. "\" while attempting authentication with " .. pending_state.event:getpeername())
                    connection_close(loop)
                end
                pending_state.command_io_watcher:callback(on_command_io_event)
                pending_state.command_io_watcher:start(loop)
                pending_state.event_io_watcher = ev.IO.new(on_event_io_event, event:getfd(), ev.READ)
                pending_state.previous = {}
                pending_state.previous[0] = ""
                pending_state.event_io_watcher:start(loop)
                pending_state.timer_watcher:stop(loop)
                state.pending_state = nil
                state.active_state = pending_state
            else
                log:warn("\"" .. err .. "\" while attempting authentication with " .. pending_state.event:getpeername())
                connection_close(loop)
            end
        end
    else
        log:error("no pending connection")
    end
end

local function on_server_authorisation_io_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        local data, err, partial = pending_state.authenticator:receive('*l', pending_state.buffer)
        pending_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" when expecting authorisation of " .. pending_state.command:getpeername() .. " with " .. pending_state.authenticator:getpeername())
            connection_close(loop)
        else
            local incoming_event, err = data_model.authenticator_authorisation_response.decode(data)
            if incoming_event then
                log:info("Received authorisation of " .. pending_state.command:getpeername() .. " from " .. pending_state.authenticator:getpeername())
                pending_state.authenticator:close()
                pending_state.authenticator_io_watcher:stop(loop)
                local event = data_model.client_authentication_reponse.encode{
                    authentication_token = incoming_event.authentication_token
                }
                local _, err = pending_state.command:send(event)
                if err then
                    log:warn("\"" .. err:msg() .. "\" when confirming authorisation of " .. pending_state.command:getpeername() .. " from " .. pending_state.authenticator:getpeername())
                    connection_close(loop)
                end
                pending_state.command_io_watcher:callback(on_event_authentication_io_event)
                pending_state.command_io_watcher:start(loop)
            else
                log:warn("\"" .. err .. "\" when expecting authorisation of " .. pending_state.command:getpeername() .. " from " .. pending_state.authenticator:getpeername())
                connection_close(loop)
            end
        end
    else
        log:error("no pending connection")
    end
end

local function on_authenticator_handshake_io_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        local success, err = pending_state.authenticator:dohandshake()
        if success then
            log:info("successful tls handshake with " .. pending_state.authenticator:getpeername())
            pending_state.authenticator_io_watcher:callback(on_server_authorisation_io_event)
            local event = data_model.authenticator_authorise_request.encode{
                server_authentication_token = incoming_event.authentication_token,
                client_authentication_token = pending_state.authentication_token
            }
            local _, err = pending_state.authenticator:send(event)
            if err then
                log:warn("\"" .. err .. "\" while attempting authorisation of " .. pending_state.command:getpeername() .. " with " .. pending_state.authenticator:getpeername())
                connection_close(loop)
            else
                log:info("sent authorisation request for " .. pending_state.command:getpeername() .. " to " .. pending_state.authenticator:getpeername())
            end
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. pending_state.authenticator:getpeername())
            connection_close(loop)
        end
    else
        log:error("no pending connection")
    end
end

local function on_command_verify_io_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        local data, err, partial = pending_state.command:receive('*l', pending_state.buffer)
        pending_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" when authenticating with " .. pending_state.command:getpeername())
            connection_close(loop)
        else
            local incoming_event, err = data_model.client_authentication_request.decode(data)
            if incoming_event then
                log:info("authenticating with " .. pending_state.command:getpeername())
                pending_state.command_io_watcher:stop(loop)
                local authenticator = socket.tcp()
                authenticator:connect(config.authenticator.host, config.authenticator.port)
                local authenticator, err = ssl.wrap(authenticator, config.authenticator.ssl_params)
                if err then
                    log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator:getpeername())
                    connection_close(loop)
                else
                    authenticator:settimeout(0)
                    pending_state.authenticator = authenticator
                    pending_state.authenticator_io_watcher = ev.IO.new(on_authenticator_handshake_io_event, authenticator:getfd(), ev.READ)
                    pending_state.authenticator_io_watcher:start(loop)
                    on_authenticator_handshake_io_event(loop, io, revents)
                end
            else
                log:warn("\"" .. err .. "\" when authenticating with " .. pending_state.command:getpeername())
                connection_close(loop)
            end
        end
    else
        log:error("no pending connection")
    end
end

local function on_command_handshake_io_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        local success, err = pending_state.command:dohandshake()
        if success then
            log:info("successful tls handshake with " .. pending_state.command:getpeername())
            command:callback(on_command_verify_io_event)
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. pending_state.command:getpeername())
            connection_close(loop)
        end
    else
        log:error("no pending connection")
    end
end

local function on_authentication_timeout_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        log:warn("authentication period has elapsed for " .. pending_state.command:getpeername())
        connection_close(loop)
    else
        log:error("no pending connection")
    end
end

local function on_user_io_event(loop, io, revents)
    state.user_idle_watcher:start(loop)
    state.user_io_watcher:stop(loop)
end

local function on_user_idle_event(loop, idle, revents)
    if state.user:has_event(zmq.POLLIN) then
        local incoming_event, err = state.user:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.user_command.decode(incoming_event)
            if err then
                log:error("\"" .. err .. "\" when decoding data from " .. config.user.pair.client)
            else
                if data_model.user_connect.kindof(incoming_event) then
                    if state.pending_state then
                        log:error("current pending connection to " ..state.command:peername())
                    elseif state.active_state then
                        log:error("current active connection with " ..state.command:peername())
                    else
                        local command = socket.tcp()
                        command:connect(incoming_event.host, incoming_event.port)
                        local command, err = ssl.wrap(command, config.client.ssl_params)
                        if err then
                            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. command:getpeername())
                        else
                            log:info("connecting to  " .. command:getpeername())
                            local pending_state = {}
                            pending_state.command = command
                            pending_state.timer_watcher = ev.Timer.new(on_authentication_timeout_event, config.client.authentication_period, 0)
                            pending_state.timer_watcher:start(loop)
                            pending_state.command:settimeout(0)
                            pending_state.event = socket.udp()
                            pending_state.event:setpeername(incoming_event.host, incoming_event.port)
                            pending_state.event:settimeout(0)
                            pending_state.authentication_token = incoming_event.authentication_token
                            pending_state.command_io_watcher = ev.IO.new(on_command_handshake_io_event, command:getfd(), ev.READ)
                            pending_state.command_io_watcher:start(loop)
                            state.pending_state = pending_state
                            on_command_handshake_io_event(loop, idle, revents)
                        end
                    end
                else
                    if state.active_state then
                        if data_model.user_example_command.kindof(incoming_event) then
                            local event = data_model.client_example_command.encode{
                                command = incoming_event.command
                            }
                            local _, err = state.active_state.command:send(event)
                            if err then
                                log:warn("\"" .. err:msg() .. "\" while sending to " .. state.active_state.command:getpeername())
                                connection_close(loop)
                            end
                        elseif data_model.user_example_action.kindof(incoming_event) then
                            local event = data_model.client_example_action.encode{
                                action = incoming_event.action
                            }
                            event = codec.encode(event, state.active_state.counter, state.active_state.epoch, incoming_event.traffic_key)
                            state.active_state.counter = state.active_state.counter + 1
                            local _, err = state.active_state.event:send(event)
                            if err then
                                log:warn("\"" .. err:msg() .. "\" while sending to " .. state.active_state.event:getpeername())
                                connection_close(loop)
                            end
                        else
                            log:error("unimplemented command kind " .. incoming_event._kind .. " received from " .. config.user.pair.client)
                        end
                    else
                        log:error("no active connection")
                    end
                end
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:error("\"" .. err:msg() .. "\" when decoding data from " .. config.user.pair.client)
        end
    else
        state.user_idle_watcher:stop(loop)
        state.user_io_watcher:start(loop)
    end
end

local function connection_close(loop)
    log:info("closing connection")
    local current_state = state.pending_state or state.active_state
    state.pending_state = nil
    state.active_state = nil
    if current_state then
        if current_state.authenticator_idle_watcher then
            current_state.authenticator_idle_watcher:stop(loop)
        end
        if current_state.authenticator_io_watcher then
            current_state.authenticator_io_watcher:stop(loop)
        end
        if current_state.authenticator then
            current_state.authenticator:close()
        end
        if current_state.timer_watcher then
            current_state.timer_watcher:close()
        end
        if current_state.event_io_watcher then
            current_state.event_io_watcher:stop(loop)
        end
        if current_state.event then
            current_state.event:close()
        end
        if current_state.command_io_watcher then
            current_state.command_io_watcher:stop(loop)
        end
        if current_state.command then
            current_state.command:close()
        end
    end
end

local function start(loop)
    log:info("starting client")
    loop = loop or ev.Loop.default
    state = {}
    state.ipc_context = zmq.context{io_threads = 1}
    state.user = state.ipc_context:socket{zmq.PAIR,
        connect = config.user.pair.client
    }
    state.user_io_watcher = ev.IO.new(on_user_io_event, state.user:get_fd(), ev.READ)
    state.user_idle_watcher = ev.Idle.new(on_user_idle_event)
    state.user_io_watcher:start(loop)
end

local function stop(loop)
    log:info("stopping client")
    loop = loop or ev.Loop.default
    connection_close(loop)
    if state.user_io_watcher then
        state.user_io_watcher:stop(loop)
    end
    if state.user_idle_watcher then
        state.user_idle_watcher:stop(loop)
    end
    if state.user then
        state.user:close()
    end
    if state.ipc_context then
        state.ipc_context:shutdown()
    end
end

return {
    start = start,
    stop = stop
}
