local encdec = require "eiko.encdec"
local data_model = require "eiko.data_model"
local log = require "eiko.logs".defaultLogger()
local socket = require "socket"
local config = require "config".server_event

local state = nil

local function to_peername(host, port)
    return "udp/" .. host .. ":" .. port
end

local function verify(host, port, data)
    for _, pending in pairs(state.pending) do
        if data == pending.authentication_token then
            log:info("authenticated " .. pending.id .. " at " .. to_peername(host, port))
            local verified = pending
            state.pending[pending.id] = nil
            verified.authentication_token = nil
            verified.port = port
            verified.host = host
            verified.history = {}
            verified.counter = 0
            verified.ack = 0
            state.verified[to_peername(host, port)] = verified
            state.verified[verified.id] = verified
            return
        end
    end
    log:warn("unable to authenticate data from " .. to_peername(host, port))
end

local function decode(verified, data)
    local message = encdec.decode(verified.traffic_key, data)
    if message then
        local acks = data_model.ack(message)
        if acks then
            log:debug("acknowledgement for " .. acks .. " received from " .. verified.id)
            for ack in acks do
                if verified.ack < ack.ack then
                    verified.ack = ack.ack
                end
            end
            for counter, previous in pairs(verified.history) do
                if counter < verified.ack then
                    verified.history[counter] = nil
                end
            end
            return
        end
        log:error("invalid format for data from " .. verified.id)
        return
    end
    log:error("unable to decode data from " .. verified.id)
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
    local verified = state.verified[verified.id]
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
            if verified.counter - counter > config.message_history_depth then
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
    log:error("no pending or verified route for " .. pending.id)
end

local function on_timer_event(loop, timer_event)
    local now = os.clock()
    for id, pending in pairs(state.pending) do
        if now - pending.now > config.authentication_period then
            log:warn("authentication period has elapsed for " .. pending.id)
            state.pending[id] = nil
        end
    end
    for id, verified in pairs(state.verified) do
        if now - verified.now > config.traffic_key_period then
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

local function connect(id)
    local pending = {}
    pending.authentication_token = encdec.authentication_token()
    pending.traffic_key = sodium.crypto_secretbox_keygen()
    pending.now = os.clock()
    pending.id = id
    state.pending[id] = pending
    log:info("authentication token and traffic key generated for " .. pending.id)
    return pending.authentication_token, pending.traffic_key
end

local function send(id, message)
    local encoded_message, host, port = produce(id, message)
    if encoded_message then
        state.udp:sendto(encoded_message, host, port)
    end
end

local function start()
    local timer = ev.Timer.new(on_timer_event, config.key_expiry_check_period, config.key_expiry_check_period)
    timer:start(ev.Loop.default)
    state = {}
    state.verified = {}
    state.pending = {}
    state.timer = timer
    local udp = socket.udp()
    udp:settimeout(0)
    udp:setsockname(config.host, config.port)
    local io_watcher = ev.IO.new(on_io_event, udp:getfd(), ev.READ)
    io_watcher:start(ev.Loop.default)
    state.udp = udp
    state.io_watcher = io_watcher
end

local function stop()
    state.io_watcher:stop(ev.Loop.default)
    state.udp:close()
    state.timer:stop(ev.Loop.default)
    state = nil
end

return {
    start = start,
    stop = stop,
    connect = connect,
    send = send
}
