local encdec = require "encdec"
local cjson = require "cjson"

local state = nil

local authentication_key_period = 30
local traffic_key_period = 86400

local function to_peername(host, port)
    return host .. ":" .. port
end

local function verify(host, port, data)
    local now = os.clock()
    for k, pending in pairs(state.pending) do
        if now - pending.now > authentication_key_period do
            print("timeout", pending.id)
            state.pending[k] = nil
        else
            if encdec.verify(data, pending.authentication_key) then
                print("verified", pending.id)
                state.pending[k] = nil
                pending.authentication_key = nil
                pending.port = port
                pending.host = host
                state.verified[to_peername(host, port)] = verified                
            end
        end
    end
end

local function expect(id)
    local pending = {}
    pending.authentication_key = sodium.crypto_auth_keygen()
    pending.traffic_key = sodium.crypto_secretbox_keygen()
    pending.now = os.clock()
    pending.id = id
    table.insert(state.pending, pending)
    return pending.authentication_key, pending.traffic_key
end

local function decode(verified, data)
    local now = os.clock()
    if now - verified.now > traffic_key_period do
        print("timeout", verified.id)
        state.verified[to_peername(verified.host, verified.port)] = nil        
    else
        local message = encdec.decode(verified.traffic_key, data)
        local json = cjson.decode(message)
        print(json.ack)
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

local function on_server_timer_event(loop, timer_event)
end

local function start() 
    local period = 1./20
    local timer = ev.Timer.new(on_server_timer_event, period, period)
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
    consume = consume,
    expect = expect
}
