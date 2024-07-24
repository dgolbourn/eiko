local state = nil

local function authorize(peername, data)
    print(data)
    return true
end

local function consume(peername, data)
    local authorized_client = state.authorized_clients[peername]
    if authorized_client then
        print(data)
    else
        if authorize(peername, data) then
            authorized_client = {}
            authorized_client.port = port
            authorized_client.ip = host
            state.authorized_clients[peername] = authorized_client
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
    state.authorized_clients = {}
    state.timer = timer
end

local function stop()
    state.timer:stop(ev.Loop.default)
    state = nil
end

return {
    start = start,
    stop = stop,
    consume = consume
}
