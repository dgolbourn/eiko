local config = require "config"
local zmq = require "lzmq"


ipc_context = zmq.context{io_threads = 1}

local event = ipc_context:socket{zmq.PAIR,
    bind = config.event.pair.command
}

event_connection_request = event:recv()
print(event_connection_request)

event:send('{"_kind":"event_connection_response","id":"JaneBloggs83","authentication_token":"asdf","traffic_key":"qwer"}\n')

print(event:recv())
