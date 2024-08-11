local socket = require "socket"
local ssl = require "ssl"
local codec = require "eiko.codec"
local data_model = require "eiko.data_model"
local config = require "eiko.config"
local log = require "eiko.logs".client
local zmq = require "lzmq"
local ev = require "ev"
local uri = require "eiko.uri"


local state = {}

count = 0

local function connection_close(loop)
    log:info("closing connection")
    local current_state = state.login_state or state.pending_state or state.active_state
    state.login_state = nil
    state.pending_state = nil
    state.active_state = nil
    if current_state then
        if current_state.authenticator_io_watcher then
            current_state.authenticator_io_watcher:stop(loop)
        end
        if current_state.authenticator then
            current_state.authenticator:close()
        end
        if current_state.timer_watcher then
            current_state.timer_watcher:stop(loop)
        end
        if current_state.stream_io_watcher then
            current_state.stream_io_watcher:stop(loop)
        end
        if current_state.stream then
            current_state.stream:close()
        end
        if current_state.server_io_watcher then
            current_state.server_io_watcher:stop(loop)
        end
        if current_state.server then
            current_state.server:close()
        end
    end
end

local function on_server_io_event(loop, io, revents)
    local active_state = state.active_state
    if active_state then
        local data, err, partial = active_state.server:receive('*l', active_state.buffer)
        active_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while receiving data from " .. active_state.tcp_peername)
            connection_close(loop)
        else
            local incoming_event, err = data_model.server_state_request.decode(data)
            if incoming_event then
                local event = data_model.client_state_request.encode{
                    global = incoming_event.global,
                    user = incoming_event.user
                }
                active_state.client:send(event)
            else
                log:warn("\"" .. err .. "\" while receiving data from " .. active_state.udp_peername)
                connection_close(loop)
            end
        end
    else
        log:error("no active connection")
    end
end

local function on_stream_io_event(loop, io, revents)
    local active_state = state.active_state
    if active_state then
        local data, err = active_state.stream:receive()
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while receiveing event from " .. active_state.udp_peername)
            connection_close(loop)
        else
            local incoming_event, epoch = codec.delta_compress_decode(data, active_state.previous, active_state.traffic_key)
            if epoch <= active_state.epoch then
                log:debug("discarding out of date event referring to epoch " .. epoch .. " <= " .. active_state.epoch .. " from " .. active_state.udp_peername)
            else
                active_state.epoch = epoch
                active_state.previous[epoch] = incoming_event
                for past_epoch, _ in pairs(active_state.previous) do
                    if active_state.epoch - past_epoch > config.event.message_history_depth then
                        active_state.previous[past_epoch] = nil
                    end
                end
                active_state.previous[0] = ""
                local incoming_event, err = data_model.server_stream_request.decode(incoming_event)
                if err then
                    log:warn("\"" .. err .. "\" when decoding data from " .. active_state.udp_peername)
                else
                    local event = data_model.client_stream_request.encode{
                        global = incoming_event.global,
                        user = incoming_event.user
                    }
                    active_state.client:send(event)
                    local event = data_model.server_stream_response.encode{}
                    event = codec.encode(event, active_state.counter, active_state.epoch, active_state.traffic_key)
                    active_state.counter = active_state.counter + 1
                    local _, err = active_state.stream:send(event)
                    if err then
                        log:warn("\"" .. err:msg() .. "\" while sending to " .. active_state.udp_peername)
                        connection_close(loop)
                    end
                end
            end
        end
    else
        log:error("no active connection")
    end
end

local function on_stream_authentication_io_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        local data, err, partial = pending_state.server:receive('*l', pending_state.buffer)
        pending_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while attempting authentication with " .. pending_state.udp_peername)
            connection_close(loop)
        else
            local incoming_event, err = data_model.server_stream_authentication_request.decode(data)
            if incoming_event then
                log:info("Authenticating with " .. pending_state.udp_peername)
                pending_state.traffic_key = incoming_event.traffic_key
                pending_state.epoch = 0
                pending_state.counter = 0
                local event = data_model.server_stream_authentication_response.encode{
                    authentication_token = incoming_event.authentication_token
                }
                event = codec.encode(event, pending_state.counter, pending_state.epoch, pending_state.traffic_key)
                pending_state.counter = pending_state.counter + 1
                local _, err = pending_state.stream:send(event)
                if err then
                    log:warn("\"" .. err:msg() .. "\" while attempting authentication with " .. pending_state.udp_peername)
                    connection_close(loop)
                end
                pending_state.timer_watcher:stop(loop)
                pending_state.server_io_watcher:callback(on_server_io_event)
                pending_state.server_io_watcher:start(loop)
                pending_state.stream_io_watcher = ev.IO.new(on_stream_io_event, pending_state.stream:getfd(), ev.READ)
                pending_state.stream_io_watcher:start(loop)
                pending_state.previous = {}
                pending_state.previous[0] = ""
                state.pending_state = nil
                state.active_state = pending_state
            else
                log:warn("\"" .. err .. "\" while attempting authentication with " .. pending_state.udp_peername)
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
            log:warn("\"" .. err .. "\" when expecting authorisation of " .. pending_state.tcp_peername .. " with " .. pending_state.authenticator_peername)
            connection_close(loop)
        else
            local incoming_event, err = data_model.authenticator_authorise_response.decode(data)
            if incoming_event then
                log:info("Received authorisation of " .. pending_state.tcp_peername .. " from " .. pending_state.authenticator_peername)
                pending_state.authenticator:close()
                pending_state.authenticator_io_watcher:stop(loop)
                local event = data_model.server_authentication_response.encode{
                    authentication_token = incoming_event.authentication_token
                }
                local _, err = pending_state.server:send(event)
                if err then
                    log:warn("\"" .. err:msg() .. "\" when confirming authorisation of " .. pending_state.tcp_peername .. " from " .. pending_state.authenticator_peername)
                    connection_close(loop)
                end
                pending_state.server_io_watcher:callback(on_stream_authentication_io_event)
                pending_state.server_io_watcher:start(loop)
            else
                log:warn("\"" .. err .. "\" when expecting authorisation of " .. pending_state.tcp_peername .. " from " .. pending_state.authenticator_peername)
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
            log:info("successful tls handshake with " .. pending_state.authenticator_peername)
            pending_state.authenticator_io_watcher:callback(on_server_authorisation_io_event)
            local event = data_model.authenticator_authorise_request.encode{
                server_authentication_token = pending_state.authentication_token,
                user_authentication_token = state.authentication_token
            }
            local _, err = pending_state.authenticator:send(event)
            if err then
                log:warn("\"" .. err .. "\" while attempting authorisation of " .. pending_state.tcp_peername .. " with " .. pending_state.authenticator_peername)
                connection_close(loop)
            else
                log:info("sent authorisation request for " .. pending_state.tcp_peername .. " to " .. pending_state.authenticator_peername)
            end
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. pending_state.authenticator_peername)
            connection_close(loop)
        end
    else
        log:error("no pending connection")
    end
end

local function on_server_verify_io_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        local data, err, partial = pending_state.server:receive('*l', pending_state.buffer)
        pending_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" when authenticating with " .. pending_state.tcp_peername)
            connection_close(loop)
        else
            local incoming_event, err = data_model.server_authentication_request.decode(data)
            if incoming_event then
                log:info("authenticating with " .. pending_state.tcp_peername)
                pending_state.server_io_watcher:stop(loop)
                local authenticator = socket.tcp()
                authenticator:connect(config.authenticator.host, config.authenticator.port)
                local authenticator_peername = uri("tcp", unpack{authenticator:getpeername()})
                local authenticator, err = ssl.wrap(authenticator, config.client.ssl_params)
                if err then
                    log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator_peername)
                    connection_close(loop)
                else
                    authenticator:settimeout(0)
                    pending_state.authenticator_peername = authenticator_peername
                    pending_state.authentication_token = incoming_event.authentication_token
                    pending_state.authenticator = authenticator
                    pending_state.authenticator_io_watcher = ev.IO.new(on_authenticator_handshake_io_event, authenticator:getfd(), ev.READ)
                    pending_state.authenticator_io_watcher:start(loop)
                    on_authenticator_handshake_io_event(loop, io, revents)
                end
            else
                log:warn("\"" .. err .. "\" when authenticating with " .. pending_state.tcp_peername)
                connection_close(loop)
            end
        end
    else
        log:error("no pending connection")
    end
end

local function on_server_handshake_io_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        local success, err = pending_state.server:dohandshake()
        if success then
            log:info("successful tls handshake with " .. pending_state.tcp_peername)
            pending_state.server_io_watcher:callback(on_server_verify_io_event)
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. pending_state.tcp_peername)
            connection_close(loop)
        end
    else
        log:error("no pending connection")
    end
end

local function on_authentication_timeout_event(loop, io, revents)
    local pending_state = state.pending_state
    if pending_state then
        log:warn("authentication period has elapsed for " .. pending_state.tcp_peername)
        connection_close(loop)
    else
        log:error("no pending connection")
    end
end

local function on_login_io_event(loop, io, revents)
    local login_state = state.login_state
    if login_state then
        local data, err, partial = login_state.authenticator:receive('*l', login_state.buffer)
        login_state.buffer = partial
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" when attempting login with " .. login_state.authenticator_peername)
            connection_close(loop)
        else
            local incoming_event, err = data_model.authenticator_login_response.decode(data)
            if incoming_event then
                log:info("logged in as " .. login_state.login)
                connection_close(loop)
                state.authentication_token = incoming_event.authentication_token
                local event = data_model.user_login_response.encode{}
                state.user:send(event)
            else
                log:warn("\"" .. err .. "\" when attempting login with " .. login_state.authenticator_peername)
                connection_close(loop)
            end
        end
    else
        log:error("no pending login")
    end
end

local function on_login_handshake_io_event(loop, io, revents)
    local login_state = state.login_state
    if login_state then
        local success, err = login_state.authenticator:dohandshake()
        if success then
            log:info("successful tls handshake with " .. login_state.authenticator_peername)
            login_state.authenticator_io_watcher:callback(on_login_io_event)
            local event = data_model.authenticator_login_request.encode{
                login = login_state.login,
                password = login_state.password
            }
            local _, err = login_state.authenticator:send(event)
            if err then
                log:warn("\"" .. err:msg() .. "\" while sending to " .. login_state.authenticator_peername)
                connection_close(loop)
            end
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. login_state.authenticator_peername)
            connection_close(loop)
        end
    else
        log:error("no pending login")
    end
end

local function on_login_timeout_event(loop, io, revents)
    local login_state = state.login_state
    if login_state then
        log:warn("timeout period has elapsed for " .. login_state.authenticator_peername)
        connection_close(loop)
    else
        log:error("no pending login")
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
            if state.active_state then
                local incoming_event, err = data_model.client_response.decode(incoming_event)
                if err then
                    log:error("\"" .. err .. "\" when decoding data from " .. config.client.ipc)
                else
                    local active_state = state.active_state
                    if data_model.client_state_response.kindof(incoming_event) then
                        local event = data_model.server_state_response.encode{
                            user = incoming_event.user
                        }
                        local _, err = active_state.server:send(event)
                        if err then
                            log:warn("\"" .. err:msg() .. "\" while sending to " .. active_state.tcp_peername)
                            connection_close(loop)
                        end
                    elseif data_model.client_stream_response.kindof(incoming_event) then
                        local event = data_model.server_stream_response.encode{
                            user = incoming_event.user
                        }
                        event = codec.encode(event, active_state.counter, active_state.epoch, active_state.traffic_key)
                        active_state.counter = active_state.counter + 1
                        local _, err = active_state.stream:send(event)
                        if err then
                            log:warn("\"" .. err:msg() .. "\" while sending to " .. active_state.udp_peername)
                            connection_close(loop)
                        end
                    else
                        log:error("unimplemented " .. incoming_event._kind .. " received from " .. config.client.ipc)
                    end
                end
            elseif state.authentication_token then
                local incoming_event, err = data_model.user_connection_request.decode(incoming_event)
                if err then
                    log:error("\"" .. err .. "\" when decoding data from " .. config.client.ipc)
                else
                    local server = socket.tcp()
                    server:connect(incoming_event.host, incoming_event.port)
                    local tcp_peername = uri("tcp", unpack{server:getpeername()})
                    local server, err = ssl.wrap(server, config.client.ssl_params)
                    if err then
                        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. tcp_peername)
                    else
                        log:info("connecting to " .. tcp_peername)
                        local pending_state = {}
                        pending_state.tcp_peername = tcp_peername
                        pending_state.server = server
                        pending_state.timer_watcher = ev.Timer.new(on_authentication_timeout_event, config.client.authentication_period, 0)
                        pending_state.timer_watcher:start(loop)
                        pending_state.server:settimeout(0)
                        pending_state.stream = socket.udp()
                        pending_state.stream:setpeername(incoming_event.host, incoming_event.port)
                        pending_state.udp_peername = uri("udp", unpack{pending_state.stream:getpeername()})
                        pending_state.stream:settimeout(0)
                        pending_state.server_io_watcher = ev.IO.new(on_server_handshake_io_event, server:getfd(), ev.READ)
                        pending_state.server_io_watcher:start(loop)
                        state.pending_state = pending_state
                        on_server_handshake_io_event(loop, idle, revents)
                    end
                end
            elseif state.login_state then
                log:error("current login attempt ongoing")
            else
                local incoming_event, err = data_model.user_login_request.decode(incoming_event)
                if err then
                    log:error("\"" .. err .. "\" when decoding data from " .. config.client.ipc)
                else
                    log:info("attempting login as " .. incoming_event.login)
                    local authenticator = socket.tcp()
                    authenticator:connect(config.authenticator.host, config.authenticator.port)
                    local authenticator_peername = uri("tcp", unpack{authenticator:getpeername()})
                    local authenticator, err = ssl.wrap(authenticator, config.client.ssl_params)
                    if err then
                        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator_peername)
                        connection_close(loop)
                    else
                        authenticator:settimeout(0)
                        local login_state = {}
                        login_state.authenticator_peername = authenticator_peername
                        login_state.login = incoming_event.login
                        login_state.password = incoming_event.password
                        login_state.authenticator = authenticator
                        login_state.authenticator_io_watcher = ev.IO.new(on_login_handshake_io_event, authenticator:getfd(), ev.READ)
                        login_state.authenticator_io_watcher:start(loop)
                        login_state.timer_watcher = ev.Timer.new(on_login_timeout_event, config.client.timeout_period, 0)
                        login_state.timer_watcher:start(loop)
                        state.login_state = login_state
                        on_login_handshake_io_event(loop, io, revents)
                    end
                end
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:error("\"" .. err:msg() .. "\" when decoding data from " .. config.client.ipc)
        end
    else
        state.user_idle_watcher:stop(loop)
        state.user_io_watcher:start(loop)
    end
end

local function start(loop)
    log:info("starting client")
    loop = loop or ev.Loop.default
    state = {}
    state.ipc_context = zmq.context{io_threads = 1}
    state.user = state.ipc_context:socket{zmq.PAIR,
        bind = config.client.ipc
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
