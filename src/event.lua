local encdec = require "eiko.encdec"
local data_model = require "eiko.data_model"
local log = require "eiko.logs".defaultLogger()
local socket = require "socket"
local config = require "config"
local mime = require "mime"

local state = nil

local function to_peername(host, port)
    return "udp/" .. host .. ":" .. port
end

local function verify(host, port, data)
    for _, pending in pairs(state.pending) do
        local incoming_event = encdec.decode(pending.traffic_key, data)
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
            verified.counter = 0
            verified.ack = 0
            verified.client_counter = 0
            state.verified[to_peername(host, port)] = verified
            state.verified[verified.id] = verified
            return
        end
    end
    log:warn("unable to authenticate data from unverified " .. to_peername(host, port))
end

local function decode(verified, data)
    local incoming_event = encdec.decode(verified.traffic_key, data)
    local incoming_event, err = data_model.client_update_event.decode(incoming_event)
    if err then
        log:warn("\"" .. err .. "\" when decoding data from " .. verified.id)
    elseif incoming_event.counter <= verified.client_counter then
        log:debug("discarding out of order event with incoming counter " .. incoming_event.counter .. " <= " .. verified.client_counter .. " from " .. verified.id)
    elseif incoming_event.server_counter < verified.ack then
        log:debug("discarding out of date event referring to outgoing counter " .. incoming_event.server_counter .. " < " .. verified.ack .. " from " .. verified.id)
    elseif incoming_event.server_counter > verified.counter then
        log:warn("discarding inconsistent event referring to future outgoing counter " .. incoming_event.server_counter .. " > " .. verified.counter .. " from " .. verified.id)
    else
        verified.client_counter = incoming_event.counter
        if incoming_event.server_counter > verified.ack then
            verified.ack = incoming_event.server_counter
            for counter, previous in pairs(verified.history) do
                if counter < verified.ack then
                    verified.history[counter] = nil
                end
            end
        end
        if incoming_event.actions then
            for _, action in ipairs(incoming_event.actions) do
                -- do something here
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
    if verified then
        verified.counter = verified.counter + 1
        local new = message
        verified.history[verified.counter] = new
        local previous = verified.history[verified.ack]
        local previous_counter = verified.ack
        if previous == nil then
            previous = ""
            previous_counter = 0
        end
        for counter in pairs(verified.history) do
            if verified.counter - counter > config.event.message_history_depth then
                verified.history[counter] = nil
            end
        end
        local encoded_message = encdec.delta_compress_encode(new, verified.counter, previous, previous_counter, verified.traffic_key)
        log:debug("delta (" .. verified.counter .. " <- " .. previous_counter .. ") encoded message produced for " .. id .. " at " .. to_peername(verified.host, verified.port))
        return encoded_message, verified.host, verified.port
    else
        local pending = state.pending[id]
        if pending then
            log:debug("no verified route to produce message for " .. id)
            return
        end
    end
    log:error("no pending or verified route for " .. id)
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
    local event = {
        _kind = data_model.event_connection_response.kind,
        id = pending.id,
        authentication_token = pending.authentication_token,
        traffic_key = pending.traffic_key
    }
    event = data_model.event_connection_response(event)
    log:info("authentication token and traffic key generated for " .. pending.id)
    context:send(nil, config.command.itc_channel, event)
    signal.raise(signal.realtime(config.command.itc_channel))
end

local function send(event)
    -- connect this to events from game
    local encoded_message, host, port = produce(event.id, event.message)
    if encoded_message then
        state.udp:sendto(encoded_message, host, port)
        log:debug("message sent to " .. event.id)
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
end

local function stop()
    log:info("stopping server event")
    if state.timer then
        state.timer:stop(ev.Loop.default)
    end
    if state.io_watcher then
        state.io_watcher:stop(ev.Loop.default)
    end
    if state.udp then
        state.udp:close()
    end
    state = nil
end

return {
    start = start,
    stop = stop
}
