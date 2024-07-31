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
                state.publisher:send(event)
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

local function on_io_event(loop, io, revents)
    data, host, port = state.udp:receivefrom()
    consume(host, port, data)
end

local function on_signal_event(loop, sig, revents)
    local _, incoming_event = context:receive(nil, config.event.itc_channel)
    local incoming_event, err = data_model.event_connection_request.decode(incoming_event)
    if err then
        log:error("\"" .. err .. "\" when decoding data from " .. config.event.itc_channel)
    else 
        connect(incoming_event)
    end
end

local function connect(incoming_event)
    local pending = {}
    pending.authentication_token = encdec.authentication_token()
    pending.traffic_key = sodium.crypto_secretbox_keygen()
    pending.now = os.clock()
    pending.id = incoming_event.id
    state.pending[pending.id] = pending
    local event = data_model.event_connection_response{
        id = pending.id,
        authentication_token = pending.authentication_token,
        traffic_key = pending.traffic_key
    }
    log:info("authentication token and traffic key generated for " .. pending.id)
    context:send(nil, config.command.itc_channel, event)
    signal.raise(signal.realtime(config.command.itc_channel))
end

local function on_ipc_io_event(loop, io, revents)
    state.ipc_idle_watcher:start(ev.Loop.default)
    state.ipc_io_watcher:stop(ev.Loop.default)
end

local function on_ipc_idle_event(loop, idle, revents)
    if state.subscriber:has_event(zmq.POLLIN) then
        local incoming_event, err = state.subscriber:recv(zmq.NOBLOCK)
        if incoming_event then
            incoming_event, err = data_model.game_event.decode()
            if err then
                log:warn("\"" .. err .. "\" when decoding data from " .. config.game.ipc_event_channel)
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
            log:warn("\"" .. err:msg() .. "\" when decoding data from " .. config.game.ipc_event_channel)
        end
    else 
        state.ipc_idle_watcher:stop(ev.Loop.default)
        state.ipc_io_watcher:start(ev.Loop.default)
    end
end

local function start()
    log:info("starting server event")
    local timer = ev.Timer.new(on_timer_event, config.event.key_expiry_check_period, config.event.key_expiry_check_period)
    timer:start(ev.Loop.default)
    state = {}
    state.verified = {}
    state.pending = {}
    state.timer = timer
    local udp = socket.udp()
    udp:settimeout(0)
    udp:setsockname(config.event.host, config.event.port)
    local io_watcher = ev.IO.new(on_io_event, udp:getfd(), ev.READ)
    io_watcher:start(ev.Loop.default)
    state.udp = udp
    state.io_watcher = io_watcher
    local signal_watcher = ev.Signal.new(on_signal_event, signal.realtime(config.event.itc_channel))
    state.signal_watcher = signal_watcher
    signal_watcher:start(ev.Loop.default)   
    state.ipc_context = zmq.context{io_threads = 1}
    state.subscriber = state.ipc_context:socket{zmq.SUB,
        subscribe = '',
        connect = config.game.ipc_event_channel
    }
    state.ipc_io_watcher = ev.IO.new(on_ipc_io_event, state.subscriber:get_fd(), ev.READ)
    state.ipc_idle_watcher = ev.Idle.new(on_ipc_idle_event)
    state.ipc_io_watcher:start(ev.Loop.default)
    state.publisher = state.ipc_context:socket{zmq.PUB,
        bind = config.game.ipc_action_channel
    }
end

local function stop()
    log:info("stopping server event")
    if state.timer then
        state.timer:stop(ev.Loop.default)
    end
    if state.io_watcher then
        state.io_watcher:stop(ev.Loop.default)
    end
    if state.ipc_io_watcher then
        state.ipc_io_watcher:stop(ev.Loop.default)
    end
    if state.ipc_idle_watcher then
        state.ipc_idle_watcher:stop(ev.Loop.default)
    end    
    if state.udp then
        state.udp:close()
    end
    if state.subscriber then
        state.subscriber:close()
    end
    if state.publisher then
        state.publisher:close()
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
