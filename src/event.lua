local encdec = require "eiko.encdec"
local data_model = require "eiko.data_model"
local log = require "eiko.logs".defaultLogger()
local socket = require "socket"
local config = require "config"
local mime = require "mime"
local zmq = require "lzmq"


local state = nil

local function to_peername(host, port)
    return "udp/" .. host .. ":" .. port
end

local function verify(host, port, data)
    for _, pending in pairs(state.pending) do
        local incoming_event, _, _ = encdec.decode(pending.traffic_key, data)
        local incoming_event, err = data_model.event_authentication_response.decode(incoming_event)
        if err then
            log:debug("unable to authenticate data as " .. pending.id .. " at unverified " .. to_peername(host, port))
        else
            log:info("authenticated " .. pending.id .. " at " .. to_peername(host, port))
            local verified = pending
            state.pending[pending.id] = nil
            verified.authentication_token = nil
            verified.port = port
            verified.host = host
            verified.history = {}
            verified.epoch = 0
            verified.ack = 0
            verified.counter = 0
            state.verified[to_peername(host, port)] = verified
            state.verified[verified.id] = verified
            return
        end
    end
    log:warn("unable to authenticate data from unverified " .. to_peername(host, port))
end

local function decode(verified, data)
    local incoming_event, counter, epoch = encdec.decode(verified.traffic_key, data)
    if counter <= verified.counter then
        log:debug("discarding out of order event with counter " .. counter .. " <= " .. verified.counter .. " from " .. verified.id)
    elseif epoch < verified.ack then
        log:debug("discarding out of date event referring to epoch " .. epoch .. " < " .. verified.ack .. " from " .. verified.id)
    elseif epoch > verified.epoch then
        log:warn("discarding inconsistent event referring to future epoch " .. epoch .. " > " .. verified.epoch .. " from " .. verified.id)
    else
        local incoming_event, err = data_model.client_action.decode(incoming_event)
        if err then
            log:warn("\"" .. err .. "\" when decoding data from " .. verified.id)
        else
            verified.counter = counter
            if epoch > verified.ack then
                verified.ack = epoch
                for past_epoch, previous in pairs(verified.history) do
                    if past_epoch < verified.ack then
                        verified.history[past_epoch] = nil
                    end
                end
            end
            if data_model.client_ack_action.kindof(incoming_event) then
            elseif data_model.client_example_action.kindof(incoming_event) then
                local event = data_model.game_action.encode{
                    id = verified.id,
                    action = incoming_event.action
                }
                state.game:send(event)
            else
                log:error("unimplemented action kind " .. incoming_event._kind .. " received from " .. verified.id)
            end
        end
    end
end

local function consume(host, port, data)
    local peername = to_peername(host, port)
    local verified = state.verified[peername]
    if verified then
        log:debug("data received from " .. verified.id)
        decode(verified, data)
    else
        log:debug("data received from unverified " .. to_peername(host, port))
        verify(host, port, data)
    end
end

local function produce(id, message)
    local verified = state.verified[id]
    verified.epoch = verified.epoch + 1
    local new = message
    verified.history[verified.epoch] = new
    local previous = verified.history[verified.ack]
    local previous_epoch = verified.ack
    if previous == nil then
        previous = ""
        previous_epoch = 0
    end
    for past_epoch, _ in pairs(verified.history) do
        if verified.epoch - past_epoch > config.event.message_history_depth then
            verified.history[past_epoch] = nil
        end
    end
    local encoded_message = encdec.delta_compress_encode(new, verified.epoch, previous, previous_epoch, verified.traffic_key)
    log:debug("delta (" .. verified.epoch .. " <- " .. previous_epoch .. ") encoded message produced for " .. id .. " at " .. to_peername(verified.host, verified.port))
    return encoded_message, verified.host, verified.port
end

local function on_timer_event(loop, timer_event)
    local now = os.clock()
    for id, pending in pairs(state.pending) do
        if now - pending.now > config.event.authentication_period then
            log:warn("authentication period has elapsed for " .. pending.id)
            state.pending[id] = nil
        end
    end
    for id, verified in pairs(state.verified) do
        if now - verified.now > config.event.traffic_key_period then
            log:warn("traffic key has expired for " .. verified.id)
            state.verified[to_peername(verified.host, verified.port)] = nil
            state.verified[verified.id] = nil
        end
    end
end

local function on_client_io_event(loop, io, revents)
    data, host, port = state.udp:receivefrom()
    consume(host, port, data)
end

local function on_command_io_event(loop, io, revents)
    state.command_idle_watcher:start(loop)
    state.command_io_watcher:stop(loop)
end

local function on_command_idle_event(loop, idle, revents)
    if state.command:has_event(zmq.POLLIN) then
        local incoming_event, err = state.command:recv(zmq.NOBLOCK)
        if incoming_event then
            local incoming_event, err = data_model.event_connection_request.decode(incoming_event)
            if err then
                log:warn("\"" .. err .. "\" when decoding data from " .. config.command.pair.event)
            else
                connect(incoming_event)
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:warn("\"" .. err:msg() .. "\" when decoding data from " .. config.command.pair.event)
        end
    else
        state.command_idle_watcher:stop(loop)
        state.command_io_watcher:start(loop)
    end
end

local function connect(incoming_event)
    local pending = {}
    pending.authentication_token = encdec.authentication_token()
    pending.traffic_key = sodium.crypto_secretbox_keygen()
    pending.now = os.clock()
    pending.id = incoming_event.id
    state.pending[pending.id] = pending
    local event = data_model.event_connection_response.encode{
        id = pending.id,
        authentication_token = pending.authentication_token,
        traffic_key = pending.traffic_key
    }
    state.command:send(event)
    log:info("authentication token and traffic key generated for " .. pending.id)
end

local function on_game_io_event(loop, io, revents)
    state.game_idle_watcher:start(loop)
    state.game_io_watcher:stop(loop)
end

local function on_game_idle_event(loop, idle, revents)
    if state.game:has_event(zmq.POLLIN) then
        local incoming_event, err = state.game:recv(zmq.NOBLOCK)
        if incoming_event then
            incoming_event, err = data_model.game_event.decode()
            if err then
                log:warn("\"" .. err .. "\" when decoding data from " .. config.game.pair.event)
            else
                if state.verified[incoming_event.id] then
                    local event = data_model.server_event.encode{
                        state = incoming_event.event
                    }
                    local encoded_message, host, port = produce(incoming_event.id, event)
                    state.udp:sendto(encoded_message, host, port)
                    log:debug("message sent to " .. incoming_event.id)
                elseif state.pending[id] then
                    log:debug("no verified route to produce message for " .. incoming_event.id)
                else
                    log:debug("no pending or verified route for " .. incoming_event.id)
                end
            end
        elseif err:no() == zmq.errors.EAGAIN then
        else
            log:warn("\"" .. err:msg() .. "\" when decoding data from " .. config.game.pair.event)
        end
    else
        state.game_idle_watcher:stop(loop)
        state.game_io_watcher:start(loop)
    end
end

local function start(loop)
    log:info("starting event")
    state = {}
    state.loop = loop or ev.Loop.default
    state.verified = {}
    state.pending = {}
    state.timer_watcher = ev.Timer.new(on_timer_event, config.event.key_expiry_check_period, config.event.key_expiry_check_period)
    state.timer_watcher = state.timer_watcher:start(loop)
    state.udp = socket.udp()
    state.udp:settimeout(0)
    state.udp:setsockname(config.event.host, config.event.port)
    state.client_io_watcher = ev.IO.new(on_client_io_event, state.udp:getfd(), ev.READ)
    state.client_io_watcher:start(loop)
    state.ipc_context = zmq.context{io_threads = 1}
    state.game = state.ipc_context:socket{zmq.PAIR,
        connect = config.game.pair.event
    }
    state.game_io_watcher = ev.IO.new(on_game_io_event, state.game:get_fd(), ev.READ)
    state.game_idle_watcher = ev.Idle.new(on_game_idle_event)
    state.game_io_watcher:start(loop)
    state.command = state.ipc_context:socket{zmq.PAIR,
        bind = config.event.pair.command
    }
    state.command_io_watcher = ev.IO.new(on_command_io_event, state.command:get_fd(), ev.READ)
    state.command_idle_watcher = ev.Idle.new(on_command_idle_event)
    state.command_io_watcher:start(loop)
end

local function stop()
    log:info("stopping event")
    local loop = state.loop
    state.loop = nil
    if state.timer_watcher then
        state.timer_watcher:stop(loop)
    end
    if state.client_io_watcher then
        state.client_io_watcher:stop(loop)
    end
    if state.udp then
        state.udp:close()
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
    if state.command_io_watcher then
        state.command_io_watcher:stop(loop)
    end
    if state.command_idle_watcher then
        state.command_idle_watcher:stop(loop)
    end
    if state.command then
        state.command:close()
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
