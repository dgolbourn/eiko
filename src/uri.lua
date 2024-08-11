local socket = require "socket"

local function uri(protocol, host, port, family)
    if not family then
        local addrinfo = socket.dns.getaddrinfo(host)
        host = addrinfo[1].addr
        family = addrinfo[1].family
    end
    local uri = host
    if family == "inet6" then
        uri = "[" .. uri .. "]"
    end
    return protocol .. "://" .. uri .. ":" .. port
end

return uri
