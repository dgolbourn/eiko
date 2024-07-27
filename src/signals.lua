local handle = io.popen("bash -c \"kill -l SIGRTMIN\"")
local sigrtmin = tonumber(handle:read("*a"))
handle:close()

local signal = require "signal"

local function realtime(id)
    return sigrtmin + id
end

signal.realtime = realtime

return signal
