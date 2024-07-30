local zmq = require "lzmq"
local socket = require 'socket'

local publish = zmq.context():socket(zmq.PUB,{bind = {"ipc://waa"}})

print(publish:get_fd())

while true do
    publish:send("waaa")
    socket.sleep(1)
end
