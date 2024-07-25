local encdec = require "eiko.encdec"
local data_model = require "eiko.data_model"

local state = nil

local authentication_key_period = 30
local traffic_key_period = 86400

local function to_peername(host, port)
    return host .. ":" .. port
end

local function verify(host, port, data)
    for _, pending in pairs(state.pending) do
        if encdec.verify(data, pending.authentication_key) then
            print("verified", pending.id)
            local verified = pending
            state.pending[pending.id] = nil
            verified.authentication_key = nil
            verified.port = port
            verified.host = host
            verified.history = {}
            verified.counter = 0
            verified.ack = 0
            state.verified[to_peername(host, port)] = verified
            state.verified[verified.id] = verified
        end
    end
end

local function expect(id)
    local pending = {}
    pending.authentication_key = sodium.crypto_auth_keygen()
    pending.traffic_key = sodium.crypto_secretbox_keygen()
    pending.now = os.clock()
    pending.id = id
    state.pending[id] = pending
    return pending.authentication_key, pending.traffic_key
end

local function queue(id, message)
    local verified = state.verified[id]
    if verified then
        verified.new = message
    else
        local pending = state.pending[id]
        if pending then
            pending.new = message
        end
    end
end

local function decode(verified, data)
    local message = encdec.decode(verified.traffic_key, data)
    local acks = data_model.ack(message)
    if acks then
        for ack in acks do
            if verified.ack < ack.ack then
                verified.ack = ack.ack
            end
            for counter, previous in pairs(verified.history) do
                if counter < ack.ack then
                    verified.history[counter] = nil
                end
            end
        end
    end
end

local function consume(host, port, data)
    local peername = to_peername(host, port)
    local verified = state.verified[peername]
    if verified then
        decode(verified, data)
    else
        verify(host, port, data)
    end
end

local function produce(id)
    local verified = state.verified[verified.id]
    if verified then
        if verified.new then
            verified.counter = verified.counter + 1
            local new = verified.new
            verified.new = nil
            return encdec.delta_compress_encode(
                new,
                verified.counter,
                verified.history[verified.ack] or "",
                verified.ack,
                verified.traffic_key
            )
        end
    end
end

local function on_timer_event(loop, timer_event)
    local now = os.clock()
    for id, pending in pairs(state.pending) do
        if now - pending.now > authentication_key_period then
            print("timeout", pending.id)
            state.pending[id] = nil
        end
    end
    for id, verified in pairs(state.verified) do
        if now - verified.now > traffic_key_period then
            print("timeout", verified.id)
            state.verified[to_peername(verified.host, verified.port)] = nil
            state.verified[verified.id] = nil        
        end
    end
end

local function start()
    local period = 1
    local timer = ev.Timer.new(on_timer_event, period, period)
    timer:start(ev.Loop.default)
    state = {}
    state.verified = {}
    state.pending = {}
    state.timer = timer
end

local function stop()
    state.timer:stop(ev.Loop.default)
    state = nil
end

return {
    start = start,
    stop = stop,
    queue = queue,
    consume = consume,
    expect = expect,
    produce = produce
}
