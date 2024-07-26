local handle = io.popen("bash -c \"kill -l SIGRTMIN\"")
local sigrtmin = tonumber(handle:read("*a"))
handle:close()

local function realtime(id)
    return sigrtmin + id
end

signal = require "signal"

signal.realtime = realtime

return signal
