local socket = require "socket"
local ssl = require "ssl"
local codec = require "eiko.codec"
local data_model = require "eiko.data_model"
local config = require "eiko.config"

local state = {}

local function on_command_io_event(loop, io, revents)
    local connection_state = state.connection_state
    if connection_state then
        local data, err, partial = connection_state.command:receive('*l', connection_state.buffer)
        connection_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while receiving data from " .. connection_state.command:getpeername())
            connection_close(loop)
        else
            local incoming_event, err = data_model.server_status.decode(data)
            if incoming_event then
                local event = data_model.user_status.encode{
                    status = incoming_event.status,
                }
                connection_state.client:send(event)
            else
                log:warn("\"" .. err .. "\" while receiving data from " .. connection_state.event:getpeername())
                connection_close(loop)
            end
        end
    else
        log:error("no connection")
    end
end

local function on_event_io_event(loop, io, revents)
    local connection_state = state.connection_state
    if connection_state then
        local data, err = connection_state.event:receive()
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while receiveing event from " .. connection_state.event:getpeername())
            connection_close(loop)
        else
            local incoming_event, epoch = codec.delta_compress_decode(data, connection_state.previous, connection_state.traffic_key)
            if epoch <= connection_state.epoch then
                log:debug("discarding out of date event referring to epoch " .. epoch .. " <= " .. connection_state.epoch .. " from " .. connection_state.event:getpeername())
            else
                connection_state.epoch = epoch
                connection_state.previous[epoch] = incoming_event
                for past_epoch, _ in pairs(connection_state.previous) do
                    if connection_state.epoch - past_epoch > config.event.message_history_depth then
                        connection_state.previous[past_epoch] = nil
                    end
                end
                connection_state.previous[0] = ""
                local incoming_event, err = data_model.server_event.decode(incoming_event)
                if err then
                    log:warn("\"" .. err .. "\" when decoding data from " .. connection_state.event:getpeername())
                else
                    local event = data_model.user_event.encode{
                        state = incoming_event.state,
                    }
                    connection_state.client:send(event)
                    local event = data_model.client_ack_action.encode{}
                    event = codec.encode(event, connection_state.counter, connection_state.epoch, incoming_event.traffic_key)
                    connection_state.counter = connection_state.counter + 1
                    local _, err = connection_state.event:send(event)
                    if err then
                        log:warn("\"" .. err:msg() .. "\" while sending to " .. connection_state.event:getpeername())
                        connection_close(loop)
                    end
                end
            end
        end
    else
        log:error("no connection")
    end
end

local function on_event_authentication_io_event(peername, loop, io, revents)
    local connection_state = state.connection_state
    if connection_state then
        local data, err, partial = connection_state.command:receive('*l', connection_state.buffer)
        connection_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while attempting authentication with " .. connection_state.event:getpeername())
            connection_close(loop)
        else
            local incoming_event, err = data_model.event_authentication_request.decode(data)
            if incoming_event then
                log:info("Authenticating with " .. connection_state.event:getpeername())
                connection_state.traffic_key = incoming_event.traffic_key
                connection_state.epoch = 0
                connection_state.counter = 0
                event = data_model.event_authentication_response.encode{
                    authentication_token = incoming_event.authentication_token
                }
                event = codec.encode(event, connection_state.counter, connection_state.epoch, incoming_event.traffic_key)
                connection_state.counter = connection_state.counter + 1
                local _, err = connection_state.event:send(event)
                if err then
                    log:warn("\"" .. err:msg() .. "\" while attempting authentication with " .. connection_state.event:getpeername())
                    connection_close(loop)
                end
                connection_state.command_io_watcher:callback(on_command_io_event)
                connection_state.command_io_watcher:start(loop)
                connection_state.event_io_watcher = ev.IO.new(on_event_io_event, event:getfd(), ev.READ)
                connection_state.previous = {}
                connection_state.previous[0] = ""
                connection_state.event_io_watcher:start(loop)
                connection_state.timer_watcher:stop(loop)
            else
                log:warn("\"" .. err .. "\" while attempting authentication with " .. connection_state.event:getpeername())
                connection_close(loop)
            end
        end
    else
        log:error("no connection")
    end
end

local function on_server_authorisation_io_event(loop, io, revents)
    local connection_state = state.connection_state
    if connection_state then
        local data, err, partial = connection_state.authenticator:receive('*l', connection_state.buffer)
        connection_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" when expecting authorisation of " .. connection_state.command:getpeername() .. " with " .. connection_state.authenticator:getpeername())
            connection_close(loop)
        else
            local incoming_event, err = data_model.authenticator_authorisation_response.decode(data)
            if incoming_event then
                log:info("Received authorisation of " .. connection_state.command:getpeername() .. " from " .. connection_state.authenticator:getpeername())
                connection_state.authenticator:close()
                connection_state.authenticator_io_watcher:stop(loop)
                local event = data_model.client_authentication_reponse.encode{
                    authentication_token = incoming_event.authentication_token
                }
                local _, err = connection_state.command:send(event)
                if err then
                    log:warn("\"" .. err:msg() .. "\" when confirming authorisation of " .. connection_state.command:getpeername() .. " from " .. connection_state.authenticator:getpeername())
                    connection_close(loop)
                end
                connection_state.command_io_watcher:callback(on_event_authentication_io_event)
                connection_state.command_io_watcher:start(loop)
            else
                log:warn("\"" .. err .. "\" when expecting authorisation of " .. connection_state.command:getpeername() .. " from " .. connection_state.authenticator:getpeername())
                connection_close(loop)
            end
        end
    else
        log:error("no connection")
    end
end

local function on_authenticator_handshake_io_event(loop, io, revents)
    local connection_state = state.connection_state
    if connection_state then
        local success, err = connection_state.authenticator:dohandshake()
        if success then
            log:info("successful tls handshake with " .. connection_state.authenticator:getpeername())
            connection_state.authenticator_io_watcher:callback(on_server_authorisation_io_event)
            local event = data_model.authenticator_authorise_request.encode{
                server_authentication_token = incoming_event.authentication_token,
                client_authentication_token = connection_state.authentication_token
            }
            local _, err = connection_state.authenticator:send(event)
            if err then
                log:warn("\"" .. err .. "\" while attempting authorisation of " .. connection_state.command:getpeername() .. " with " .. connection_state.authenticator:getpeername())
                connection_close(loop)
            else
                log:info("sent authorisation request for " .. connection_state.command:getpeername() .. " to " .. connection_state.authenticator:getpeername())
            end
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. connection_state.authenticator:getpeername())
            connection_close(loop)
        end
    else
        log:error("no connection")
    end
end

local function on_command_verify_io_event(loop, io, revents)
    local connection_state = state.connection_state
    if connection_state then
        local data, err, partial = connection_state.command:receive('*l', connection_state.buffer)
        connection_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" when authenticating with " .. connection_state.command:getpeername())
            connection_close(loop)
        else
            local incoming_event, err = data_model.client_authentication_request.decode(data)
            if incoming_event then
                log:info("authenticating with " .. connection_state.command:getpeername())
                connection_state.command_io_watcher:stop(loop)
                local authenticator = socket.tcp()
                authenticator:connect(config.authenticator.host, config.authenticator.port)
                local authenticator, err = ssl.wrap(authenticator, config.authenticator.ssl_params)
                if err then
                    log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator:getpeername())
                    connection_close(loop)
                else
                    authenticator:settimeout(0)
                    connection_state.authenticator = authenticator
                    connection_state.authenticator_io_watcher = ev.IO.new(on_authenticator_handshake_io_event, authenticator:getfd(), ev.READ)
                    connection_state.authenticator_io_watcher:start(loop)
                    on_authenticator_handshake_io_event(loop, io, revents)
                end
            else
                log:warn("\"" .. err .. "\" when authenticating with " .. connection_state.command:getpeername())
                connection_close(loop)
            end
        end
    else
        log:error("no connection")
    end
end

local function on_command_handshake_io_event(loop, io, revents)
    local connection_state = state.connection_state
    if connection_state then
        local success, err = connection_state.command:dohandshake()
        if success then
            log:info("successful tls handshake with " .. connection_state.command:getpeername())
            command:callback(on_command_verify_io_event)
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. connection_state.command:getpeername())
            connection_close(loop)
        end
    else
        log:error("no connection")
    end
end

local function on_authentication_timeout_event(loop, io, revents)
    local connection_state = state.connection_state
    if connection_state then
        log:warn("authentication period has elapsed for " .. connection_state.command:getpeername())
        connection_close(loop)
    else
        log:error("no connection")
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
                    local command = socket.tcp()
                    command:connect(incoming_event.host, incoming_event.port)
                    local command, err = ssl.wrap(command, config.client.ssl_params)
                    if err then
                        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. command:getpeername())
                    else
                        log:info("connecting to  " .. command:getpeername())
                        local connection_state = {}
                        connection_state.command = command
                        connection_state.timer_watcher = ev.Timer.new(on_authentication_timeout_event, config.client.authentication_period, 0)
                        connection_state.timer_watcher:start(loop)
                        connection_state.command:settimeout(0)
                        connection_state.event = socket.udp()
                        connection_state.event:setpeername(incoming_event.host, incoming_event.port)
                        connection_state.event:settimeout(0)
                        connection_state.authentication_token = incoming_event.authentication_token
                        connection_state.command_io_watcher = ev.IO.new(on_command_handshake_io_event, command:getfd(), ev.READ)
                        connection_state.command_io_watcher:start(loop)
                        state.connection_state = connection_state
                        on_command_handshake_io_event(loop, idle, revents)
                    end
                elseif data_model.user_example_command.kindof(incoming_event) then
                    local event = data_model.client_example_command.encode{
                        command = incoming_event.command
                    }
                    local _, err = connection_state.command:send(event)
                    if err then
                        log:warn("\"" .. err:msg() .. "\" while sending to " .. connection_state.command:getpeername())
                        connection_close(loop)
                    end
                elseif data_model.user_example_action.kindof(incoming_event) then
                    local event = data_model.client_example_action.encode{
                        action = incoming_event.action
                    }
                    event = codec.encode(event, connection_state.counter, connection_state.epoch, incoming_event.traffic_key)
                    connection_state.counter = connection_state.counter + 1
                    local _, err = connection_state.event:send(event)
                    if err then
                        log:warn("\"" .. err:msg() .. "\" while sending to " .. connection_state.event:getpeername())
                        connection_close(loop)
                    end
                else
                    log:error("unimplemented command kind " .. incoming_event._kind .. " received from " .. config.user.pair.client)
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
    local connection_state = state.connection_state
    state.connection_state = nil
    if connection_state then
        if connection_state.authenticator_idle_watcher then
            connection_state.authenticator_idle_watcher:stop(loop)
        end
        if connection_state.authenticator_io_watcher then
            connection_state.authenticator_io_watcher:stop(loop)
        end
        if connection_state.authenticator then
            connection_state.authenticator:close()
        end
        if connection_state.timer_watcher then
            connection_state.timer_watcher:close()
        end
        if connection_state.event_io_watcher then
            connection_state.event_io_watcher:stop(loop)
        end
        if connection_state.event then
            connection_state.event:close()
        end
        if connection_state.command_io_watcher then
            connection_state.command_io_watcher:stop(loop)
        end
        if connection_state.command then
            connection_state.command:close()
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
