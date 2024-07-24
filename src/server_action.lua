local encdec = require "encdec"

local state = nil

local authentication_key_lifetime = 30
local traffic_key_lifetime = 86400

local function verify(data)
    local now = os.clock()
    for k, pending in pairs(state.pending) do
        if now - pending.now > authentication_key_lifetime do
            print("timeout", pending.id)
            state.pending[k] = nil
        else
            local verified = encdec.verify(data, pa.authentication_key)
            if verified then
                print("verified", pending.id)
                state.pending[k] = nil
                pending.authentication_key = nil
                return pending
            end
        end
    end
end

local function expect(id, authentication_key, traffic_key)
    local pending = {}
    pending.authentication_key = authentication_key
    pending.traffic_key = traffic_key
    pending.now = os.clock()
    pending.id = id
    table.insert(state.pending, pending)
end

local function consume(host, port, data)
    local peername = host .. ":" .. port
    local verified = state.verified[peername]
    if verified then
        print(data)
    else
        verified = verify(data)
        if verified then
            verified.port = port
            verified.host = host
            state.verified[peername] = verified
        end
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
