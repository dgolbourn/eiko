local function io_event(loop, io, revents)
    local client_state = {}
    local client = state.tcp:accept()
    local peername = client:getpeername()
    local fd = client:getfd()
    local new = socket.tcp()
    client.setfd(socket._SOCKETINVALID)
    new:setfd(fd)
end

local function start(loop)
    log:info("starting authenticator")
    loop = loop or ev.Loop.default
    state = {}
    state.tcp = socket.tcp()
    state.tcp:bind(config.authenticator.host, config.authenticator.port)
    state.tcp:listen(config.authenticator.max_clients)
    state.tcp:settimeout(0)
    state.io_watcher = ev.IO.new(io_event, state.tcp:getfd(), ev.READ)
    state.io_watcher:start(loop)
end

return {
    start = start,
    stop = stop
}
