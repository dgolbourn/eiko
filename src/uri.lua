local socket = require "socket"

local function geturi(sock)
    local host, port, family = sock:getpeername()
    local type = sock:getsockname()
    local uri = host
    if family == "inet6" then
        host = "[" .. host .. "]"
    end
    uri = uri .. ":" .. port
    if type = "stream" then
        uri = "tcp://" .. uri
    else
        uri = "udp://" .. uri
    end
    return uri
end
