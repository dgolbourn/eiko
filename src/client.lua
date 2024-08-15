local socket = require "socket"
local ssl = require "ssl"
local codec = require "eiko.codec"
local data_model = require "eiko.data_model"
local log = require "eiko.logs".client
local uri = require "eiko.uri"


local function new(config)
    local state = nil

    local function connection_close()
        local current_state = state.login_state or state.pending_state or state.active_state
        state.login_state = nil
        state.pending_state = nil
        state.active_state = nil
        if current_state then
            if current_state.authenticator_io_watcher then
                current_state.authenticator_io_watcher.stop()
            end
            if current_state.authenticator then
                current_state.authenticator:close()
            end
            if current_state.timer_watcher then
                current_state.timer_watcher.stop()
            end
            if current_state.stream_io_watcher then
                current_state.stream_io_watcher.stop()
            end
            if current_state.stream then
                current_state.stream:close()
            end
            if current_state.server_io_watcher then
                current_state.server_io_watcher.stop()
            end
            if current_state.server then
                current_state.server:close()
            end
        end
    end

    local function on_server_io_event()
        local active_state = state.active_state
        if active_state then
            local data, err, partial = active_state.server:receive('*l', active_state.buffer)
            active_state.buffer = partial
            if err == "timeout" then
            elseif err then
                log:warn("\"" .. err .. "\" while receiving data from " .. active_state.tcp_peername)
                connection_close()
            else
                local incoming_event, err = data_model.server_state_request.decode(data)
                if incoming_event then
                    local event = data_model.client_state_request.encode{
                        global = incoming_event.global,
                        ipc = incoming_event.ipc
                    }
                    state.ipc:send(event)
                else
                    log:warn("\"" .. err .. "\" while receiving data from " .. active_state.tcp_peername)
                    connection_close()
                end
            end
        else
            log:error("no active connection")
        end
    end

    local function on_stream_io_event()
        local active_state = state.active_state
        if active_state then
            local data, err = active_state.stream:receive()
            if err == "timeout" then
            elseif err then
                log:warn("\"" .. err .. "\" while receiveing event from " .. active_state.udp_peername)
                connection_close()
            else
                local incoming_event, epoch = codec.delta_compress_decode(data, active_state.previous, active_state.traffic_key)
                if epoch <= active_state.epoch then
                    log:debug("discarding out of date event referring to epoch " .. epoch .. " <= " .. active_state.epoch .. " from " .. active_state.udp_peername)
                else
                    active_state.epoch = epoch
                    active_state.previous[epoch] = incoming_event
                    for past_epoch, _ in pairs(active_state.previous) do
                        if active_state.epoch - past_epoch > config.message_history_depth then
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
                            ipc = incoming_event.ipc
                        }
                        state.ipc:send(event)
                        local event = data_model.server_stream_response.encode{}
                        event = codec.encode(event, active_state.counter, active_state.epoch, active_state.traffic_key)
                        active_state.counter = active_state.counter + 1
                        local _, err = active_state.stream:send(event)
                        if err then
                            log:warn("\"" .. err:msg() .. "\" while sending to " .. active_state.udp_peername)
                            connection_close()
                        end
                    end
                end
            end
        else
            log:error("no active connection")
        end
    end

    local function on_stream_authentication_io_event()
        local pending_state = state.pending_state
        if pending_state then
            local data, err, partial = pending_state.server:receive('*l', pending_state.buffer)
            pending_state.buffer = partial
            if err == "timeout" then
            elseif err then
                log:warn("\"" .. err .. "\" while attempting authentication with " .. pending_state.udp_peername)
                connection_close()
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
                        connection_close()
                    end
                    pending_state.timer_watcher.stop()
                    pending_state.server_io_watcher.callback(on_server_io_event)
                    pending_state.server_io_watcher.start()
                    pending_state.stream_io_watcher = state.event.receiver(pending_state.stream, on_stream_io_event)
                    pending_state.stream_io_watcher.start()
                    pending_state.previous = {}
                    pending_state.previous[0] = ""
                    state.pending_state = nil
                    state.active_state = pending_state
                else
                    log:warn("\"" .. err .. "\" while attempting authentication with " .. pending_state.udp_peername)
                    connection_close()
                end
            end
        else
            log:error("no pending connection")
        end
    end

    local function on_server_authorisation_io_event()
        local pending_state = state.pending_state
        if pending_state then
            local data, err, partial = pending_state.authenticator:receive('*l', pending_state.buffer)
            pending_state.buffer = partial
            if err == "timeout" then
            elseif err then
                log:warn("\"" .. err .. "\" when expecting authorisation of " .. pending_state.tcp_peername .. " with " .. pending_state.authenticator_peername)
                connection_close()
            else
                local incoming_event, err = data_model.authenticator_authorise_response.decode(data)
                if incoming_event then
                    log:info("Received authorisation of " .. pending_state.tcp_peername .. " from " .. pending_state.authenticator_peername)
                    pending_state.authenticator:close()
                    pending_state.authenticator_io_watcher.stop()
                    local event = data_model.server_authentication_response.encode{
                        authentication_token = incoming_event.authentication_token
                    }
                    local _, err = pending_state.server:send(event)
                    if err then
                        log:warn("\"" .. err:msg() .. "\" when confirming authorisation of " .. pending_state.tcp_peername .. " from " .. pending_state.authenticator_peername)
                        connection_close()
                    end
                    pending_state.server_io_watcher.callback(on_stream_authentication_io_event)
                    pending_state.server_io_watcher.start()
                else
                    log:warn("\"" .. err .. "\" when expecting authorisation of " .. pending_state.tcp_peername .. " from " .. pending_state.authenticator_peername)
                    connection_close()
                end
            end
        else
            log:error("no pending connection")
        end
    end

    local function on_authenticator_handshake_io_event()
        local pending_state = state.pending_state
        if pending_state then
            local success, err = pending_state.authenticator:dohandshake()
            if success then
                log:info("successful tls handshake with " .. pending_state.authenticator_peername)
                pending_state.authenticator_io_watcher.callback(on_server_authorisation_io_event)
                local event = data_model.authenticator_authorise_request.encode{
                    server_authentication_token = pending_state.authentication_token,
                    user_authentication_token = state.authentication_token
                }
                local _, err = pending_state.authenticator:send(event)
                if err then
                    log:warn("\"" .. err .. "\" while attempting authorisation of " .. pending_state.tcp_peername .. " with " .. pending_state.authenticator_peername)
                    connection_close()
                else
                    log:info("sent authorisation request for " .. pending_state.tcp_peername .. " to " .. pending_state.authenticator_peername)
                end
            elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
            else
                log:warn("\"" .. err .. "\" while attempting tls handshake with " .. pending_state.authenticator_peername)
                connection_close()
            end
        else
            log:error("no pending connection")
        end
    end

    local function on_server_verify_io_event()
        local pending_state = state.pending_state
        if pending_state then
            local data, err, partial = pending_state.server:receive('*l', pending_state.buffer)
            pending_state.buffer = partial
            if err == "timeout" then
            elseif err then
                log:warn("\"" .. err .. "\" when authenticating with " .. pending_state.tcp_peername)
                connection_close()
            else
                local incoming_event, err = data_model.server_authentication_request.decode(data)
                if incoming_event then
                    log:info("authenticating with " .. pending_state.tcp_peername)
                    pending_state.server_io_watcher.stop()
                    local authenticator = socket.tcp()
                    authenticator:connect(config.authenticator.host, config.authenticator.port)
                    local authenticator_peername = uri("tcp", unpack{authenticator:getpeername()})
                    local authenticator, err = ssl.wrap(authenticator, config.ssl)
                    if err then
                        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator_peername)
                        connection_close()
                    else
                        authenticator:settimeout(0)
                        pending_state.authenticator_peername = authenticator_peername
                        pending_state.authentication_token = incoming_event.authentication_token
                        pending_state.authenticator = authenticator
                        pending_state.authenticator_io_watcher = state.event.receiver(authenticator, on_authenticator_handshake_io_event)
                        pending_state.authenticator_io_watcher.start()
                        on_authenticator_handshake_io_event()
                    end
                else
                    log:warn("\"" .. err .. "\" when authenticating with " .. pending_state.tcp_peername)
                    connection_close()
                end
            end
        else
            log:error("no pending connection")
        end
    end

    local function on_server_handshake_io_event()
        local pending_state = state.pending_state
        if pending_state then
            local success, err = pending_state.server:dohandshake()
            if success then
                log:info("successful tls handshake with " .. pending_state.tcp_peername)
                pending_state.server_io_watcher.callback(on_server_verify_io_event)
            elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
            else
                log:warn("\"" .. err .. "\" while attempting tls handshake with " .. pending_state.tcp_peername)
                connection_close()
            end
        else
            log:error("no pending connection")
        end
    end

    local function on_authentication_timeout_event()
        local pending_state = state.pending_state
        if pending_state then
            log:warn("authentication period has elapsed for " .. pending_state.tcp_peername)
            connection_close()
        else
            log:error("no pending connection")
        end
    end

    local function on_login_io_event()
        local login_state = state.login_state
        if login_state then
            local data, err, partial = login_state.authenticator:receive('*l', login_state.buffer)
            login_state.buffer = partial
            if err == "timeout" then
            elseif err then
                log:warn("\"" .. err .. "\" when attempting login with " .. login_state.authenticator_peername)
                connection_close()
            else
                local incoming_event, err = data_model.authenticator_login_response.decode(data)
                if incoming_event then
                    log:info("logged in as " .. login_state.login)
                    connection_close()
                    state.authentication_token = incoming_event.authentication_token
                    local event = data_model.user_login_response.encode{}
                    state.ipc:send(event)
                else
                    log:warn("\"" .. err .. "\" when attempting login with " .. login_state.authenticator_peername)
                    connection_close()
                end
            end
        else
            log:error("no pending login")
        end
    end

    local function on_login_handshake_io_event()
        local login_state = state.login_state
        if login_state then
            local success, err = login_state.authenticator:dohandshake()
            if success then
                log:info("successful tls handshake with " .. login_state.authenticator_peername)
                login_state.authenticator_io_watcher.callback(on_login_io_event)
                local event = data_model.authenticator_login_request.encode{
                    login = login_state.login,
                    password = login_state.password
                }
                local _, err = login_state.authenticator:send(event)
                if err then
                    log:warn("\"" .. err:msg() .. "\" while sending to " .. login_state.authenticator_peername)
                    connection_close()
                end
            elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
            else
                log:warn("\"" .. err .. "\" while attempting tls handshake with " .. login_state.authenticator_peername)
                connection_close()
            end
        else
            log:error("no pending login")
        end
    end

    local function on_login_timeout_event()
        local login_state = state.login_state
        if login_state then
            log:warn("timeout period has elapsed for " .. login_state.authenticator_peername)
            connection_close()
        else
            log:error("no pending login")
        end
    end

    local function on_ipc_io_event()
        local data, err = state.ipc:receive()
        if err == "timeout" then
        elseif err then
            log:warn("\"" .. err .. "\" while receiveing event from " .. state.ipc_peername)
        else
            if state.active_state then
                local incoming_event, err = data_model.client_response.decode(data)
                if err then
                    log:error("\"" .. err .. "\" when decoding data from " .. state.ipc_peername)
                else
                    local active_state = state.active_state
                    if data_model.client_state_response.kindof(incoming_event) then
                        local event = data_model.server_state_response.encode{
                            ipc = incoming_event.ipc
                        }
                        local _, err = active_state.server:send(event)
                        if err then
                            log:warn("\"" .. err:msg() .. "\" while sending to " .. active_state.tcp_peername)
                            connection_close()
                        end
                    elseif data_model.client_stream_response.kindof(incoming_event) then
                        local event = data_model.server_stream_response.encode{
                            ipc = incoming_event.ipc
                        }
                        event = codec.encode(event, active_state.counter, active_state.epoch, active_state.traffic_key)
                        active_state.counter = active_state.counter + 1
                        local _, err = active_state.stream:send(event)
                        if err then
                            log:warn("\"" .. err:msg() .. "\" while sending to " .. active_state.udp_peername)
                            connection_close()
                        end
                    else
                        log:error("unimplemented " .. incoming_event._kind .. " received from " .. state.ipc_peername)
                    end
                end
            elseif state.authentication_token then
                local incoming_event, err = data_model.user_connection_request.decode(data)
                if err then
                    log:error("\"" .. err .. "\" when decoding data from " .. state.ipc_peername)
                else
                    local server = socket.tcp()
                    server:connect(incoming_event.host, incoming_event.port)
                    local tcp_peername = uri("tcp", unpack{server:getpeername()})
                    local server, err = ssl.wrap(server, config.ssl)
                    if err then
                        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. tcp_peername)
                    else
                        log:info("connecting to " .. tcp_peername)
                        local pending_state = {}
                        pending_state.tcp_peername = tcp_peername
                        pending_state.server = server
                        pending_state.timer_watcher = state.event.timer(config.authentication_period, on_authentication_timeout_event)
                        pending_state.timer_watcher.start()
                        pending_state.server:settimeout(0)
                        pending_state.stream = socket.udp()
                        pending_state.stream:setpeername(incoming_event.host, incoming_event.port)
                        pending_state.udp_peername = uri("udp", unpack{pending_state.stream:getpeername()})
                        pending_state.stream:settimeout(0)
                        pending_state.server_io_watcher = state.event.receiver(server, on_server_handshake_io_event)
                        pending_state.server_io_watcher.start()
                        state.pending_state = pending_state
                        on_server_handshake_io_event()
                    end
                end
            elseif state.login_state then
                log:error("current login attempt ongoing")
            else
                local incoming_event, err = data_model.user_login_request.decode(data)
                if err then
                    log:error("\"" .. err .. "\" when decoding data from " .. config.ipc)
                else
                    log:info("attempting login as " .. incoming_event.login)
                    local authenticator = socket.tcp()
                    authenticator:connect(config.authenticator.host, config.authenticator.port)
                    local authenticator_peername = uri("tcp", unpack{authenticator:getpeername()})
                    local authenticator, err = ssl.wrap(authenticator, config.ssl)
                    if err then
                        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator_peername)
                        connection_close()
                    else
                        authenticator:settimeout(0)
                        local login_state = {}
                        login_state.authenticator_peername = authenticator_peername
                        login_state.login = incoming_event.login
                        login_state.password = incoming_event.password
                        login_state.authenticator = authenticator
                        login_state.authenticator_io_watcher = state.event.receiver(authenticator, on_login_handshake_io_event)
                        login_state.authenticator_io_watcher.start()
                        login_state.timer_watcher = state.event.timer(config.timeout_period, on_login_timeout_event)
                        login_state.timer_watcher.start()
                        state.login_state = login_state
                        on_login_handshake_io_event()
                    end
                end
            end
        end
    end

    local function start(event)
        log:info("starting client")
        state = {}
        state.event = event
        state.ipc = socket.udp()
        state.ipc:settimeout(0)
        state.ipc:setsockname(config.ipc.outgoing.host, config.ipc.outgoing.port)
        state.ipc:setpeername(config.ipc.incoming.host, config.ipc.incoming.port)
        state.ipc_io_watcher = state.event.receiver(state.ipc, on_ipc_io_event)
        state.ipc_io_watcher.start()
        state.ipc_peername = uri("udp", unpack{state.ipc:getpeername()})
    end

    local function stop()
        log:info("stopping client")
        connection_close()
        if state.ipc_io_watcher then
            state.ipc_io_watcher.stop()
        end
        if state.ipc then
            state.ipc:close()
        end
        state = nil
    end

    return {
        start = start,
        stop = stop
    }
end

return {
    new = new
}
