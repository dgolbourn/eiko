local socket = require("socket")
local ev = require("ev")

udp_state = nil

local function on_server_io_event(loop, io, revents)
    print("on_server_io_event")
    client_datagram, client_ip, client_port = udp_state.udp:receivefrom()
    print(client_datagram)
    udp_state.udp:sendto("ACK", client_ip, client_port)
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
    udp:close()
    udp = nil
end

return {
    start = start,
    stop = stop
}
