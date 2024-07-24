local socket = require "socket"
local ev = require "ev"
local action = require "eiko.server_action"

local udp_state = nil

local function on_server_io_event(loop, io, revents)
    print("on_server_io_event")
    data, host, port = udp_state.udp:receivefrom()
    peername = host .. ':' .. port
    print(peername, data)
    action.consume(peername, data)
end

local function start(host, port)
    local udp = socket.udp()
    udp:settimeout(0)
    udp:setsockname(host, port)
    local io_watcher = ev.IO.new(on_server_io_event, udp:getfd(), ev.READ)
    io_watcher:start(ev.Loop.default)
    udp_state = {}
    udp_state.udp = udp
    udp_state.io_watcher = io_watcher
end

local function stop()
    udp_state.io_watcher:stop(ev.Loop.default)
    udp_state.udp:close()
    udp_state = nil
end

return {
    start = start,
    stop = stop
}
