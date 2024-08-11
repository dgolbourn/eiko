local socket = require "socket"
local ev = require "ev"
local ssl = require "ssl"
local config = require "eiko.config"
local log = require "eiko.logs".server
local data_model = require "eiko.data_model"
local codec = require "eiko.codec"
local zmq = require "lzmq"
local uri = require "eiko.uri"


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
    if client_state.tcp_peername then
        state.clients[client_state.tcp_peername] = nil
    end
    if client_state.udp_peername then
        state.clients[client_state.udp_peername] = nil
    end
    if client_state.uuid then
        state.pending[client_state.uuid] = nil
        state.clients[client_state.uuid] = nil
    end
end

local function on_traffic_key_timeout_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
        log:info("traffic key period has elapsed for " .. peername)
        client_state.traffic_key = codec.traffic_key()
        local event = data_model.server_traffic_key_request.encode{
            traffic_key = incoming_event.traffic_key
        }
        local _, err = client_state.client:send(event)
        if err then
            log:warn("\"" .. err .. "\" while attempting to send traffic key to " .. incoming_event.uuid)
            client_state_close(client_state, loop)
        else
            log:info("sent traffic key to " .. incoming_event.uuid)
        end
    else
        log:warn("no verified client " .. peername)
    end
end

local function verify(loop, peername, host, port, data)
    for _, pending in pairs(state.pending) do
        local incoming_event, _, _ = codec.decode(data, pending.traffic_key)
        local incoming_event, err = data_model.server_stream_authentication_response.decode(incoming_event)
        if err then
            log:debug("unable to authenticate data as " .. pending.uuid .. " at unverified " .. peername)
        else
            local client_state = state.clients[pending.uuid]
            if client_state then
                if incoming_event.authentication_token == pending.authentication_token then
                    log:info("authenticated " .. pending.uuid .. " at " .. peername)
                    state.pending[pending.uuid] = nil
                    client_state.traffic_key = pending.traffic_key
                    client_state.port = port
                    client_state.host = host
                    client_state.udp_peername = peername
                    client_state.history = {}
                    client_state.epoch = 0
                    client_state.ack = 0
                    client_state.counter = 0
                    client_state.timer_watcher:stop(loop)
                    local timer_event = function(loop, io, revents)
                        on_traffic_key_timeout_event(peername, loop, io, revents)
                    end
                    client_state.timer_watcher = ev.Timer.new(timer_event, config.server.traffic_key_period, 0)
                    client_state.timer_watcher:start(loop)
                    state.clients[peername] = client_state
                    return
                else
                    log:error("incorrect authentication token received from " .. pending.uuid)
                end
            else
                log:warn("no pending authentication for " .. peername)
            end
        end
    end
    log:warn("unable to authenticate data from unverified " .. peername)
end

local function decode(client_state, data)
    local incoming_event, counter, epoch = codec.decode(data, client_state.traffic_key)
    if counter <= client_state.counter then
        log:debug("discarding out of order event with counter " .. counter .. " <= " .. client_state.counter .. " from " .. client_state.uuid)
    elseif epoch < client_state.ack then
        log:debug("discarding out of date event referring to epoch " .. epoch .. " < " .. client_state.ack .. " from " .. client_state.uuid)
    elseif epoch > client_state.epoch then
        log:warn("discarding inconsistent event referring to future epoch " .. epoch .. " > " .. client_state.epoch .. " from " .. client_state.uuid)
    else
        local incoming_event, err = data_model.server_stream_response.decode(incoming_event)
        if err then
            log:warn("\"" .. err .. "\" when decoding data from " .. client_state.uuid)
        else
            client_state.counter = counter
            if epoch > client_state.ack then
                client_state.ack = epoch
                for past_epoch, _ in pairs(client_state.history) do
                    if past_epoch < client_state.ack then
                        client_state.history[past_epoch] = nil
                    end
                end
            end
            if incoming_event.user then
                local event = data_model.game_stream_response.encode{
                    uuid = client_state.uuid,
                    user = incoming_event.user
                }
                state.game:send(event)
            end
        end
    end
end

local function on_stream_io_event(loop, io, revents)
    local data, host, port = state.udp:receivefrom()
    local peername = uri("udp", host, port)
    local client_state = state.clients[peername]
    if client_state then
        log:debug("data received from " .. client_state.uuid)
        decode(client_state, data)
    else
        log:debug("data received from unverified " .. peername)
        verify(loop, peername, host, port, data)
    end
end

local function on_client_io_event(uuid, loop, io, revents)
    local client_state = state.clients[uuid]
    if client_state then
        local data, err, partial = client_state.client:receive('*l', client_state.buffer)
        client_state.buffer = partial
        if data then
            local incoming_event, err = data_model.server_state_reponse.decode(data)
            if incoming_event then
                local event = data_model.game_state_response.encode{
                    uuid = uuid,
                    user = incoming_event.user
                }
                state.game:send(event)
            else
                log:error("\"" .. err .. "\" when decoding data from " .. uuid)
            end
        elseif err == "timeout" then
        else
            log:warn("\"" .. err .. "\" while receiving from " .. uuid)
            client_state_close(client_state, loop)
        end
    else
        log:warn("no verified client " .. uuid)
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
                log:info(client_state.authenticator_peername .. " verified authentication token as " .. incoming_event.uuid .. " at " .. peername)
                client_state.authenticator:close()
                client_state.authenticator_io_watcher:stop(loop)
                client_state.uuid = incoming_event.uuid
                local uuid = incoming_event.uuid
                local io_event = function(loop, io, revents)
                    on_client_io_event(uuid, loop, io, revents)
                end
                client_state.client_io_watcher:callback(io_event)
                client_state.client_io_watcher:start(loop)
                local pending = {}
                pending.authentication_token = codec.authentication_token()
                pending.traffic_key = codec.traffic_key()
                pending.uuid = client_state.uuid
                state.pending[client_state.uuid] = pending
                state.clients[client_state.uuid] = client_state
                local event = data_model.server_stream_authentication_request.encode{
                    authentication_token = pending.authentication_token,
                    traffic_key = pending.traffic_key
                }
                local _, err = client_state.client:send(event)
                if err then
                    log:warn("\"" .. err .. "\" while attempting to send authentication token and traffic key to " .. incoming_event.uuid)
                    client_state_close(client_state, loop)
                else
                    log:info("sent authentication token and traffic key to " .. incoming_event.uuid)
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
        if success then
            log:info("successful tls handshake with " .. client_state.authenticator_peername)
            local io_event = function(loop, io, revents)
                on_verify_io_event(peername, loop, io, revents)
            end
            client_state.authenticator_io_watcher:callback(io_event)
            local event = data_model.authenticator_verify_request.encode{
                server_authentication_token = client_state.server_authentication_token,
                client_authentication_token = client_state.client_authentication_token
            }
            local _, err = client_state.authenticator:send(event)
            if err then
                log:warn("\"" .. err .. "\" while attempting authentication of " .. peername)
                client_state_close(client_state, loop)
            else
                log:info("sent verification request to " .. client_state.authenticator_peername .. " for " .. peername)
            end
        elseif err == "timeout" or err == "wantread" or err == "wantwrite" then
        else
            log:warn("\"" .. err .. "\" while attempting tls handshake with " .. client_state.authenticator_peername)
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
        elseif err then
            log:warn("\"" .. err .. "\" when expecting authentication of " .. peername)
            client_state_close(client_state, loop)
        else
            client_state.client_io_watcher:stop(loop)
            local incoming_event, err = data_model.server_authentication_response.decode(data)
            if incoming_event then
                log:info("verifying " .. peername)
                local authenticator = socket.tcp()
                authenticator:connect(config.authenticator.host, config.authenticator.port)
                local authenticator_peername = uri("tcp", unpack{authenticator:getpeername()})
                local authenticator, err = ssl.wrap(authenticator, config.client.ssl_params)
                if err then
                    log:warn("\"" .. err .. "\" while attempting tls handshake with " .. authenticator_peername)
                    client_state_close(client_state, loop)
                else
                    authenticator:settimeout(0)
                    local io_event = function(loop, io, revents)
                        on_authenticator_handshake_io_event(peername, loop, io, revents)
                    end
                    client_state.authenticator_peername = authenticator_peername
                    client_state.client_authentication_token = incoming_event.authentication_token
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

local function on_authentication_timeout_event(peername, loop, io, revents)
    local client_state = state.clients[peername]
    if client_state then
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
            client_state.server_authentication_token = codec.authentication_token()
            local event = data_model.server_authentication_request.encode{
                authentication_token = client_state.server_authentication_token
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

local function on_game_io_event(loop, io, revents)
    state.game_idle_watcher:start(loop)
    state.game_io_watcher:stop(loop)
end

local function on_game_idle_event(loop, idle, revents)
    if state.game:has_event(zmq.POLLIN) then
        local incoming_event, err = state.game:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.game_request.decode(incoming_event)
            if err then
                log:error("\"" .. err .. "\" when decoding data from " .. config.server.ipc)
            else
                if data_model.game_state_request.kindof(incoming_event) then
                    for uuid, user in incoming_event.user do
                        local client_state = state.clients[uuid]
                        if client_state then
                            local event = data_model.server_state_request.encode{
                                global = incoming_event.global,
                                user = user
                            }
                            local _, err = client_state.client:send(event)
                            if err then
                                log:warn("\"" .. err .. "\" while attempting to send to " .. uuid)
                                client_state_close(client_state, loop)
                            end
                            log:debug("state sent to " .. uuid)
                        else
                            log:debug("no verified client for " .. uuid)
                        end
                    end
                elseif data_model.game_stream_request.kindof(incoming_event) then
                    for uuid, user in pairs(incoming_event.user) do
                        local client_state = state.clients[uuid]
                        if client_state and client_state.traffic_key then
                            local event = data_model.server_stream_request.encode{
                                global = incoming_event.global,
                                user = user
                            }
                            client_state.epoch = client_state.epoch + 1
                            client_state.history[client_state.epoch] = event
                            local previous = client_state.history[client_state.ack]
                            local previous_epoch = client_state.ack
                            if previous == nil then
                                previous = ""
                                previous_epoch = 0
                            end
                            for past_epoch, _ in pairs(client_state.history) do
                                if client_state.epoch - past_epoch > config.server.message_history_depth then
                                    client_state.history[past_epoch] = nil
                                end
                            end
                            local encoded_message = codec.delta_compress_encode(event, client_state.epoch, previous, previous_epoch, client_state.traffic_key)
                            local _, err = state.udp:sendto(encoded_message, client_state.host, client_state.port)
                            if err then
                                log:warn("\"" .. err .. "\" while attempting to send to " .. uuid)
                                client_state_close(client_state, loop)
                            end
                            log:debug("delta (" .. client_state.epoch .. " <- " .. previous_epoch .. ") stream sent to " .. uuid)
                        else
                            log:debug("no verified route to " .. uuid)
                        end
                    end
                else
                    log:error("unimplemented game request kind " .. incoming_event._kind)
                end
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:error("\"" .. err:msg() .. "\" when decoding data from " .. config.server.ipc)
        end
    else
        state.game_idle_watcher:stop(loop)
        state.game_io_watcher:start(loop)
    end
end

local function on_new_client_io_event(loop, io, revents)
    local client = state.tcp:accept()
    local peername = uri("tcp", unpack{client:getpeername()})
    log:info("connection from unverified " .. peername)
    local client, err = ssl.wrap(client, config.server.ssl_params)
    if err then
        log:warn("\"" .. err .. "\" while attempting tls handshake with " .. peername)
    else
        client:settimeout(0)
        local io_event = function(loop, io, revents)
            on_handshake_io_event(peername, loop, io, revents)
        end
        local client_state = {}
        client_state.client = client
        client_state.tcp_peername = peername
        client_state.client_io_watcher = ev.IO.new(io_event, client:getfd(), ev.READ)
        client_state.client_io_watcher:start(loop)
        local timer_event = function(loop, io, revents)
            on_authentication_timeout_event(peername, loop, io, revents)
        end
        client_state.timer_watcher = ev.Timer.new(timer_event, config.server.authentication_period, 0)
        client_state.timer_watcher:start(loop)
        state.clients[peername] = client_state
    end
end

local function start(loop)
    log:info("starting server")
    loop = loop or ev.Loop.default
    state = {}
    state.tcp = socket.tcp()
    state.tcp:bind(config.server.host, config.server.port)
    state.tcp:listen(config.server.max_clients)
    state.tcp:settimeout(0)
    state.new_client_io_watcher = ev.IO.new(on_new_client_io_event, state.tcp:getfd(), ev.READ)
    state.new_client_io_watcher:start(loop)
    state.ipc_context = zmq.context{io_threads = 1}
    state.game = state.ipc_context:socket{zmq.PAIR, bind = config.server.ipc}
    state.game_io_watcher = ev.IO.new(on_game_io_event, state.game:get_fd(), ev.READ)
    state.game_idle_watcher = ev.Idle.new(on_game_idle_event)
    state.game_io_watcher:start(loop)
    state.clients = {}
    state.udp = socket.udp()
    state.udp:settimeout(0)
    state.udp:setsockname(config.server.host, config.server.port)
    state.stream_io_watcher = ev.IO.new(on_stream_io_event, state.udp:getfd(), ev.READ)
    state.stream_io_watcher:start(loop)
    state.pending = {}
end

local function stop(loop)
    log:info("stopping server")
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
    if state.stream_io_watcher then
        state.stream_io_watcher:stop(loop)
    end
    if state.udp then
        state.udp:close()
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
